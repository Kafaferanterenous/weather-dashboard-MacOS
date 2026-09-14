import Foundation

enum WeatherError: LocalizedError {
    case badURL
    case badResponse
    case serverStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Could not build the request URL."
        case .badResponse: return "Server returned an invalid response."
        case .serverStatus(let code): return "Weather service error (HTTP \(code))."
        }
    }
}

struct WeatherService {
    func fetch(place: Place) async throws -> Dashboard {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "10"),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation,uv_index,surface_pressure"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,precipitation,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,wind_direction_10m_dominant")
        ]
        guard let url = components?.url else { throw WeatherError.badURL }

        async let airTask = fetchAirQuality(place: place)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw WeatherError.badResponse }
        guard http.statusCode == 200 else { throw WeatherError.serverStatus(http.statusCode) }

        let decoded = try JSONDecoder().decode(ForecastAPIResponse.self, from: data)
        var dashboard = Self.map(decoded)
        dashboard = Dashboard(current: dashboard.current,
                              days: dashboard.days,
                              hours: dashboard.hours,
                              air: await airTask)
        return dashboard
    }

    func geocode(_ query: String) async throws -> [GeoPlace] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { throw WeatherError.badURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WeatherError.badResponse
        }
        struct GeoSearchResponse: Decodable { let results: [GeoPlace]? }
        return try JSONDecoder().decode(GeoSearchResponse.self, from: data).results ?? []
    }

    private func fetchAirQuality(place: Place) async -> AirQuality? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "current", value: "us_aqi,grass_pollen,alder_pollen,birch_pollen,mugwort_pollen,olive_pollen,ragweed_pollen")
        ]
        guard let url = components?.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(AirQualityResponse.self, from: data).current.asAirQuality
        } catch {
            return nil
        }
    }

    static func map(_ r: ForecastAPIResponse) -> Dashboard {
        let zone = TimeZone(identifier: r.timezone) ?? .current

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        timeFormatter.timeZone = zone
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = zone
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")

        let current = CurrentConditions(
            time: timeFormatter.date(from: r.current.time) ?? Date(),
            temperature: r.current.temperature2m,
            feelsLike: r.current.apparentTemperature,
            humidity: r.current.relativeHumidity2m,
            isDay: r.current.isDay == 1,
            code: r.current.weatherCode,
            wind: r.current.windSpeed10m,
            windDirection: r.current.windDirection10m,
            gusts: r.current.windGusts10m,
            precipitation: r.current.precipitation,
            uvIndex: r.current.uvIndex ?? 0,
            pressure: r.current.surfacePressure
        )

        var days: [DayForecast] = []
        days.reserveCapacity(r.daily.time.count)
        for i in r.daily.time.indices {
            days.append(DayForecast(
                date: dayFormatter.date(from: r.daily.time[i]) ?? Date(),
                code: r.daily.weatherCode[i],
                high: r.daily.temperature2mMax[i],
                low: r.daily.temperature2mMin[i],
                sunrise: r.daily.sunrise[i],
                sunset: r.daily.sunset[i],
                uvMax: r.daily.uvIndexMax[i] ?? 0,
                rainMillimetres: r.daily.precipitationSum[i] ?? 0,
                rainProbability: r.daily.precipitationProbabilityMax[safe: i].flatMap { $0 } ?? 0,
                windMax: r.daily.windSpeed10mMax[safe: i].flatMap { $0 } ?? 0,
                windDirection: r.daily.windDirection10mDominant[safe: i].flatMap { $0 } ?? 0
            ))
        }

        var hours: [HourPoint] = []
        hours.reserveCapacity(r.hourly.time.count)
        for i in r.hourly.time.indices {
            guard let t = timeFormatter.date(from: r.hourly.time[i]) else { continue }
            hours.append(HourPoint(
                time: t,
                temperature: r.hourly.temperature2m[i],
                rainProbability: r.hourly.precipitationProbability[safe: i].flatMap { $0 } ?? 0,
                precipitation: r.hourly.precipitation[safe: i].flatMap { $0 } ?? 0,
                wind: r.hourly.windSpeed10m[safe: i].flatMap { $0 } ?? 0
            ))
        }

        let cutoff = Date().addingTimeInterval(-3600)
        let upcoming = Array(hours.filter { $0.time >= cutoff }.prefix(48))

        return Dashboard(current: current, days: days, hours: upcoming, air: nil)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
