import Foundation

struct Place: Identifiable, Hashable, Codable {
    let name: String
    let latitude: Double
    let longitude: Double
    var id: String { name }
}

struct GeoPlace: Identifiable, Decodable {
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?

    var id: String { "\(name)|\(latitude)|\(longitude)" }
    var subtitle: String {
        [admin1, country].compactMap { $0 }.joined(separator: ", ")
    }
}

extension Place {
    static let presets: [Place] = [
        Place(name: "Adelaide", latitude: -34.9287, longitude: 138.5986),
        Place(name: "Melbourne", latitude: -37.8136, longitude: 144.9631),
        Place(name: "Sydney", latitude: -33.8688, longitude: 151.2093),
        Place(name: "Brisbane", latitude: -27.4698, longitude: 153.0251),
        Place(name: "Perth", latitude: -31.9505, longitude: 115.8605),
        Place(name: "Canberra", latitude: -35.2809, longitude: 149.1300),
        Place(name: "Hobart", latitude: -42.8821, longitude: 147.3272),
        Place(name: "Darwin", latitude: -12.4634, longitude: 130.8456),
        Place(name: "Auckland", latitude: -36.8485, longitude: 174.7633),
        Place(name: "London", latitude: 51.5072, longitude: -0.1276)
    ]
}

struct CurrentConditions {
    let time: Date
    let temperature: Double
    let feelsLike: Double
    let humidity: Int
    let isDay: Bool
    let code: Int
    let wind: Double
    let windDirection: Double
    let gusts: Double
    let precipitation: Double
    let uvIndex: Double
    let pressure: Double
}

struct DayForecast: Identifiable {
    let date: Date
    let code: Int
    let high: Double
    let low: Double
    let sunrise: String
    let sunset: String
    let uvMax: Double
    let rainMillimetres: Double
    let rainProbability: Int
    let windMax: Double
    let windDirection: Double
    var id: Date { date }
}

struct HourPoint: Identifiable {
    let time: Date
    let temperature: Double
    let rainProbability: Int
    let precipitation: Double
    let wind: Double
    var id: Date { time }
}

struct Dashboard {
    let current: CurrentConditions
    let days: [DayForecast]
    let hours: [HourPoint]
    let air: AirQuality?
}

struct AirQuality {
    let usAqi: Int?
    let grassPollen: Double?
    let alderPollen: Double?
    let birchPollen: Double?
    let mugwortPollen: Double?
    let olivePollen: Double?
    let ragweedPollen: Double?

    var pollenMax: Double? {
        [grassPollen, alderPollen, birchPollen, mugwortPollen,
         olivePollen, ragweedPollen].compactMap { $0 }.max()
    }

    static func aqiLabel(_ value: Int) -> String {
        let s = AppSettings.shared
        switch value {
        case ..<51: return s.t("aqiGood")
        case ..<101: return s.t("aqiModerate")
        case ..<151: return s.t("aqiSensitive")
        case ..<201: return s.t("aqiUnhealthy")
        case ..<301: return s.t("aqiVeryBad")
        default: return s.t("aqiHazardous")
        }
    }

    static func pollenLabel(_ value: Double) -> String {
        let s = AppSettings.shared
        switch value {
        case ..<10: return s.t("levelLow")
        case ..<30: return s.t("levelModerate")
        case ..<70: return s.t("levelHigh")
        default: return s.t("levelVeryHigh")
        }
    }
}

struct AirQualityResponse: Decodable {
    let current: Block

    struct Block: Decodable {
        let usAqi: Int?
        let grassPollen: Double?
        let alderPollen: Double?
        let birchPollen: Double?
        let mugwortPollen: Double?
        let olivePollen: Double?
        let ragweedPollen: Double?

        enum CodingKeys: String, CodingKey {
            case usAqi = "us_aqi"
            case grassPollen = "grass_pollen"
            case alderPollen = "alder_pollen"
            case birchPollen = "birch_pollen"
            case mugwortPollen = "mugwort_pollen"
            case olivePollen = "olive_pollen"
            case ragweedPollen = "ragweed_pollen"
        }

        var asAirQuality: AirQuality {
            AirQuality(usAqi: usAqi, grassPollen: grassPollen,
                       alderPollen: alderPollen, birchPollen: birchPollen,
                       mugwortPollen: mugwortPollen, olivePollen: olivePollen,
                       ragweedPollen: ragweedPollen)
        }
    }
}

enum WMO {
    static func description(_ code: Int) -> String {
        AppSettings.shared.t(code == -1 ? "wmoUnknown" : "wmo\(code)")
    }

    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.max.fill" : "cloud.moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 80, 81, 82: return "cloud.rain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func uvLabel(_ uv: Double) -> String {
        let s = AppSettings.shared
        switch uv {
        case ..<3: return s.t("levelLow")
        case ..<6: return s.t("levelModerate")
        case ..<8: return s.t("levelHigh")
        case ..<11: return s.t("levelVeryHigh")
        default: return s.t("levelExtreme")
        }
    }

    static func compass(_ degrees: Double) -> String {
        let points = ["N","NNE","NE","ENE","E","ESE","SE","SSE",
                      "S","SSW","SW","WSW","W","WNW","NW","NNW"]
        var index = Int((degrees / 22.5).rounded()) % 16
        if index < 0 { index += 16 }
        return points[index]
    }
}

struct ForecastAPIResponse: Decodable {
    let timezone: String
    let current: CurrentBlock
    let hourly: HourlyBlock
    let daily: DailyBlock

    struct CurrentBlock: Decodable {
        let time: String
        let temperature2m: Double
        let apparentTemperature: Double
        let relativeHumidity2m: Int
        let isDay: Int
        let weatherCode: Int
        let windSpeed10m: Double
        let windDirection10m: Double
        let windGusts10m: Double
        let precipitation: Double
        let uvIndex: Double?
        let surfacePressure: Double

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity2m = "relative_humidity_2m"
            case isDay = "is_day"
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
            case windGusts10m = "wind_gusts_10m"
            case precipitation
            case uvIndex = "uv_index"
            case surfacePressure = "surface_pressure"
        }
    }

    struct HourlyBlock: Decodable {
        let time: [String]
        let temperature2m: [Double]
        let precipitationProbability: [Int?]
        let precipitation: [Double?]
        let windSpeed10m: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case precipitationProbability = "precipitation_probability"
            case precipitation
            case windSpeed10m = "wind_speed_10m"
        }
    }

    struct DailyBlock: Decodable {
        let time: [String]
        let weatherCode: [Int]
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]
        let sunrise: [String]
        let sunset: [String]
        let uvIndexMax: [Double?]
        let precipitationSum: [Double?]
        let precipitationProbabilityMax: [Int?]
        let windSpeed10mMax: [Double?]
        let windDirection10mDominant: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case sunrise
            case sunset
            case uvIndexMax = "uv_index_max"
            case precipitationSum = "precipitation_sum"
            case precipitationProbabilityMax = "precipitation_probability_max"
            case windSpeed10mMax = "wind_speed_10m_max"
            case windDirection10mDominant = "wind_direction_10m_dominant"
        }
    }
}
