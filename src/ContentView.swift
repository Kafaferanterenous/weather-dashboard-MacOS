import SwiftUI
import Charts

@MainActor
final class WeatherStore: ObservableObject {
    @Published var place: Place
    @Published private(set) var savedPlaces: [Place]
    @Published var dashboard: Dashboard?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    var allPlaces: [Place] { Place.presets + savedPlaces }

    init() {
        let defaults = UserDefaults.standard
        let customs: [Place]
        if let data = defaults.data(forKey: "customPlaces"),
           let decoded = try? JSONDecoder().decode([Place].self, from: data) {
            customs = decoded
        } else {
            customs = []
        }
        savedPlaces = customs
        let saved = defaults.string(forKey: "selectedPlace") ?? "Adelaide"
        place = (Place.presets + customs).first { $0.name == saved } ?? Place.presets[0]
        scheduleAutoRefresh()
    }

    // Single periodic refresh drives both the main window and the menu-bar panel.
    private func scheduleAutoRefresh() {
        Task { [weak self] in
            while let store = self {
                try? await Task.sleep(nanoseconds: 1_800_000_000_000)
                await store.load()
            }
        }
    }

    func select(_ newPlace: Place) {
        guard newPlace != place else { return }
        place = newPlace
        UserDefaults.standard.set(newPlace.name, forKey: "selectedPlace")
        Task { await load() }
    }

    func addAndSelect(_ geo: GeoPlace) {
        let target = Place(name: geo.name, latitude: geo.latitude, longitude: geo.longitude)
        if !allPlaces.contains(where: { $0.id == target.id }) {
            savedPlaces.append(target)
            saveCustoms()
        }
        select(target)
    }

    private func saveCustoms() {
        if let data = try? JSONEncoder().encode(savedPlaces) {
            UserDefaults.standard.set(data, forKey: "customPlaces")
        }
    }

    func isPreset(_ candidate: Place) -> Bool {
        Place.presets.contains(candidate)
    }

    func remove(_ target: Place) {
        guard !isPreset(target) else { return }
        savedPlaces.removeAll { $0.id == target.id }
        saveCustoms()
        if place == target, let fallback = Place.presets.first {
            place = fallback
            UserDefaults.standard.set(fallback.name, forKey: "selectedPlace")
            Task { await load() }
        }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            dashboard = try await WeatherService().fetch(place: place)
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: WeatherStore
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            BackgroundGradient(code: store.dashboard?.current.code,
                               isDay: store.dashboard?.current.isDay ?? true)
            VStack(spacing: 14) {
                HeaderView(store: store)
                mainContent
                FooterView(store: store)
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
        .environmentObject(settings)
        .task { await store.load() }
    }

    @ViewBuilder private var mainContent: some View {
        if let dash = store.dashboard {
            HeroCard(current: dash.current, air: dash.air)
            DaysStrip(days: dash.days)
            ChartsCard(hours: dash.hours)
            if let message = store.errorMessage {
                Text(message)
                    .font(settings.scaled(11))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.5))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else if store.isLoading {
            Spacer()
            ProgressView().controlSize(.large)
            Text(settings.t("fetching"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(store.errorMessage ?? settings.t("noData"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Button(settings.t("tryAgain")) { Task { await store.load() } }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            Spacer()
        }
    }
}

struct BackgroundGradient: View {
    let code: Int?
    let isDay: Bool

    static func colors(code: Int?, isDay: Bool) -> [Color] {
        guard let code = code else {
            return [Color(red: 0.10, green: 0.12, blue: 0.20),
                    Color(red: 0.16, green: 0.19, blue: 0.31)]
        }
        if code <= 1 {
            return isDay
                ? [Color(red: 0.13, green: 0.42, blue: 0.78), Color(red: 0.46, green: 0.72, blue: 0.94)]
                : [Color(red: 0.05, green: 0.07, blue: 0.17), Color(red: 0.11, green: 0.15, blue: 0.30)]
        }
        if (95...99).contains(code) {
            return [Color(red: 0.10, green: 0.11, blue: 0.17), Color(red: 0.23, green: 0.24, blue: 0.34)]
        }
        if (51...67).contains(code) || (80...86).contains(code) {
            return [Color(red: 0.15, green: 0.20, blue: 0.32), Color(red: 0.30, green: 0.37, blue: 0.50)]
        }
        if (71...77).contains(code) {
            return [Color(red: 0.43, green: 0.50, blue: 0.60), Color(red: 0.67, green: 0.73, blue: 0.81)]
        }
        return [Color(red: 0.23, green: 0.27, blue: 0.37), Color(red: 0.39, green: 0.45, blue: 0.56)]
    }

    var body: some View {
        LinearGradient(colors: Self.colors(code: code, isDay: isDay),
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

struct HeaderView: View {
    @ObservedObject var store: WeatherStore
    @ObservedObject private var settings = AppSettings.shared
    @State private var showSearch = false
    @State private var showManage = false
    @State private var showSettingsSheet = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                    Text(store.place.name)
                        .font(settings.scaled(20).bold())
                }
                if let updated = store.lastUpdated {
                    Text(settings.tf("updated", updated.formatted(date: .omitted, time: .shortened)))
                        .font(settings.scaled(11))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            Spacer()
            TimelineView(.everyMinute) { timeline in
                Text(settings.formatted(timeline.date, dateFormat: "EEE d MMM  ·  HH:mm"))
                    .font(settings.scaled(13).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.22),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .help(settings.t("clockHelp"))
            }
            if store.isLoading && store.dashboard != nil {
                ProgressView().controlSize(.small)
            }
            Picker("Location", selection: Binding(
                get: { store.place },
                set: { store.select($0) }
            )) {
                ForEach(store.allPlaces) { place in
                    Text(place.name).tag(place)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 170)
            Button {
                showSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .help(settings.t("searchCity"))
            Button {
                showManage = true
            } label: {
                Image(systemName: "list.bullet")
            }
            .buttonStyle(.bordered)
            .help(settings.t("manageLocs"))
            Button {
                Task { await store.load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(store.isLoading)
            .help(settings.t("refreshNow"))
            Button {
                showSettingsSheet = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.bordered)
            .help(settings.t("settings"))
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet(store: store)
        }
        .sheet(isPresented: $showManage) {
            ManageSheet(store: store)
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheetView()
        }
        .onChange(of: settings.settingsRequest) { _ in
            showSettingsSheet = true
        }
    }
}

struct SettingsSheetView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private var versionText: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(v) (build \(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(settings.t("settings"))
                .font(settings.scaled(17).weight(.bold))

            HStack {
                Text(settings.t("version"))
                    .font(settings.scaled(13))
                Spacer()
                Text(versionText)
                    .font(settings.scaled(13).monospacedDigit().weight(.semibold))
                    .foregroundStyle(.yellow)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.t("fontSize"))
                    .font(settings.scaled(13))
                HStack {
                    Slider(value: $settings.fontScale, in: 0.85...1.30, step: 0.05)
                    Text("\(Int((settings.fontScale * 100).rounded()))%")
                        .font(settings.scaled(12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                Text("Adelaide · \(settings.tempText(21))° · \(settings.t("levelModerate").lowercased())")
                    .font(settings.scaled(14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.t("unitsHeader"))
                    .font(settings.scaled(13))
                HStack(spacing: 18) {
                    Picker(settings.t("tabTemperature"), selection: $settings.tempUnit) {
                        ForEach(TempUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    Picker(settings.t("tabWind"), selection: $settings.windUnit) {
                        ForEach(WindSpeedUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    Spacer()
                }
            }

            Toggle(isOn: $settings.stayInMenuBar) {
                Text(settings.t("stayInMenuBar"))
                    .font(settings.scaled(13))
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.t("languageLabel"))
                    .font(settings.scaled(13))
                Picker("", selection: $settings.language) {
                    ForEach(Language.allCases) { lang in
                        Text(lang.nativeName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(settings.t("close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

struct ManageSheet: View {
    @ObservedObject var store: WeatherStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(settings.t("savedLocations"))
                    .font(settings.scaled(15).bold())
                Spacer()
                Button(settings.t("done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Divider()
            List {
                ForEach(store.allPlaces) { candidate in
                    HStack(spacing: 10) {
                        Image(systemName: store.isPreset(candidate) ? "lock.fill" : "star.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(store.isPreset(candidate) ? settings.t("builtinLocked") : settings.t("customCity"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(candidate.name)
                                .fontWeight(.medium)
                            if candidate == store.place {
                                Text(settings.t("currentLoc"))
                                    .font(settings.scaled(10).weight(.semibold))
                                    .foregroundStyle(.yellow)
                            } else if !store.isPreset(candidate) {
                                Text(String(format: "%.2f°, %.2f°",
                                            candidate.latitude, candidate.longitude))
                                    .font(settings.scaled(11))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(settings.t("builtin"))
                                    .font(settings.scaled(11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !store.isPreset(candidate) {
                            Button {
                                store.remove(candidate)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help(settings.t("removeLoc"))
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .padding(16)
        .frame(width: 440, height: 460)
    }
}

struct SearchSheet: View {
    @ObservedObject var store: WeatherStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [GeoPlace] = []
    @State private var searching = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(settings.t("cityNamePH"), text: $query)
                    .textFieldStyle(.plain)
                    .font(settings.scaled(18))
                if searching {
                    ProgressView().controlSize(.small)
                }
                Button(settings.t("close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Divider()
            if results.isEmpty && !searching && query.count >= 2 {
                Text(settings.t("noMatches"))
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
            }
            List(results) { geo in
                Button {
                    store.addAndSelect(geo)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(geo.name)
                                .fontWeight(.medium)
                            Text(geo.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.tint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
        .padding(16)
        .frame(width: 480, height: 520)
        .task(id: query) {
            guard query.count >= 2 else {
                results = []
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        searching = true
        defer { searching = false }
        do {
            results = try await WeatherService().geocode(query)
        } catch {
            results = []
        }
    }
}

struct HeroCard: View {
    let current: CurrentConditions
    let air: AirQuality?
    @EnvironmentObject var settings: AppSettings

    private var iconColor: Color {
        switch current.code {
        case 0, 1: return current.isDay ? .yellow : .lavenderish
        case 95...99: return .orange
        case 51...67, 80...86: return Color(red: 0.55, green: 0.75, blue: 1.0)
        case 71...86: return Color(red: 0.85, green: 0.92, blue: 1.0)
        default: return .white
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 26) {
            Image(systemName: WMO.symbol(current.code, isDay: current.isDay))
                .font(.system(size: 72))
                .foregroundStyle(iconColor)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                .frame(width: 108)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 2) {
                    Text(settings.tempText(current.temperature))
                        .font(settings.scaled(84).weight(.light))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    Text(settings.tempUnit.symbol)
                        .font(settings.scaled(16).weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .padding(.top, 16)
                }
                Text(WMO.description(current.code))
                    .font(settings.scaled(20).weight(.semibold))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                Text(settings.tf("feelsLike", settings.tempText(current.feelsLike)))
                    .font(settings.scaled(13))
                    .foregroundStyle(Color.white.opacity(0.82))
            }

            Spacer()

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible())
            ], spacing: 10) {
                MetricPill(label: settings.t("humidity"), value: "\(current.humidity)%")
                MetricPill(label: settings.t("wind"), value: settings.windText(current.wind) + " " + WMO.compass(current.windDirection))
                MetricPill(label: settings.t("gusts"), value: settings.windText(current.gusts))
                MetricPill(label: settings.t("uvIndex"), value: current.uvIndex.formatted(.number.precision(.fractionLength(1))) + " · " + WMO.uvLabel(current.uvIndex))
                MetricPill(label: settings.t("pressure"), value: "\(Int(current.pressure.rounded())) hPa")
                MetricPill(label: settings.t("rainNow"), value: String(format: "%.1f mm", current.precipitation))
                if let air = air {
                    if let aqi = air.usAqi {
                        MetricPill(label: settings.t("airQuality"), value: "\(aqi) · \(AirQuality.aqiLabel(aqi))")
                    }
                    if let pollen = air.pollenMax {
                        MetricPill(label: settings.t("pollen"),
                                   value: settings.tf("grainsFormat", pollen) + " · " + AirQuality.pollenLabel(pollen))
                    }
                }
            }
            .frame(maxWidth: 470)
        }
        .padding(22)
        .background(Color.black.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18))
        )
        .shadow(color: .black.opacity(0.30), radius: 12, y: 5)
    }
}

extension Color {
    static let lavenderish = Color(red: 0.78, green: 0.76, blue: 1.0)
}

struct MetricPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.72))
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }
}

struct DaysStrip: View {
    let days: [DayForecast]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    DayCard(day: day, isToday: index == 0)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct DayCard: View {
    let day: DayForecast
    let isToday: Bool
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 7) {
            Text(isToday ? settings.t("today")
                         : settings.formatted(day.date, dateFormat: "EEE").uppercased())
                .font(settings.scaled(11).weight(.bold))
                .tracking(0.5)
                .foregroundStyle(isToday ? Color.yellow : Color.white.opacity(0.75))
            Image(systemName: WMO.symbol(day.code, isDay: true))
                .font(.system(size: 27))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(height: 34)
            Text(settings.tempText(day.high) + "°")
                .font(settings.scaled(18).weight(.bold))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            Text(settings.tempText(day.low) + "°")
                .font(settings.scaled(13).weight(.medium))
                .foregroundStyle(Color.white.opacity(0.78))
            HStack(spacing: 3) {
                Image(systemName: "drop.fill").font(.system(size: 8))
                Text("\(day.rainProbability)%")
            }
            .font(settings.scaled(11).weight(.semibold))
            .foregroundStyle(Color(red: 0.60, green: 0.86, blue: 1.0))
            HStack(spacing: 3) {
                Image(systemName: "wind").font(.system(size: 9))
                Text(settings.windText(day.windMax))
            }
            .font(settings.scaled(11))
            .foregroundStyle(Color.white.opacity(0.72))
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 8)
        .frame(width: 112, height: 174)
        .background(Color.black.opacity(isToday ? 0.10 : 0.26),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(Color.white.opacity(isToday ? 0.16 : 0.08),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isToday ? Color.yellow.opacity(0.65) : Color.white.opacity(0.14),
                              lineWidth: isToday ? 1.5 : 1)
        )
    }
}

enum ChartTab: String, CaseIterable, Identifiable {
    case temperature = "Temperature"
    case rainfall = "Rainfall"
    case wind = "Wind"
    var id: String { rawValue }
}

struct ChartsCard: View {
    let hours: [HourPoint]
    @State private var tab: ChartTab = .temperature
    @EnvironmentObject var settings: AppSettings

    private func tabName(_ value: ChartTab) -> String {
        switch value {
        case .temperature: return settings.t("tabTemperature")
        case .rainfall: return settings.t("tabRainfall")
        case .wind: return settings.t("tabWind")
        }
    }

    // Unit shown next to the title; rainfall carries two scales (mm left, % right).
    private var unitHint: String {
        switch tab {
        case .temperature: return settings.tempUnit.symbol
        case .rainfall: return "mm · %"
        case .wind: return settings.windUnit.symbol
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(settings.t("next48"))
                    .font(settings.scaled(15).bold())
                Text(unitHint)
                    .font(settings.scaled(11).weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.20),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Spacer()
                Picker("Metric", selection: $tab) {
                    ForEach(ChartTab.allCases) { item in
                        Text(tabName(item)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 360)
            }
            Group {
                switch tab {
                case .temperature: temperatureChart
                case .rainfall: rainfallChart
                case .wind: windChart
                }
            }
            .frame(height: 200)
        }
        .padding(18)
        .background(Color.black.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18))
        )
        .shadow(color: .black.opacity(0.30), radius: 12, y: 5)
    }

    private var temperatureChart: some View {
        Chart(hours) { point in
            AreaMark(x: .value("Time", point.time),
                     y: .value("Temp", settings.temp(point.temperature)))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [.orange.opacity(0.38), .orange.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", point.time),
                     y: .value("Temp", settings.temp(point.temperature)))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.orange)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisValueLabel(format: .dateTime.hour(), centered: true)
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
            }
        }
    }

    // Swift Charts has no native dual scale, so the 0-100% line is mapped onto
    // the mm domain (percent * maxRain/100) and the trailing axis labels are
    // un-scaled back to percentages — visually a true independent axis.
    private var rainfallChart: some View {
        let maxRain = max(hours.map(\.precipitation).max() ?? 0, 1)
        let scale = maxRain / 100.0
        return Chart(hours) { point in
            BarMark(x: .value("Time", point.time),
                    y: .value("Rain mm", point.precipitation), width: .fixed(7))
                .cornerRadius(2)
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.55, green: 0.83, blue: 1.0),
                                                         Color(red: 0.20, green: 0.50, blue: 0.95)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", point.time),
                     y: .value("Chance", Double(point.rainProbability) * scale))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.white.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisValueLabel(format: .dateTime.hour(), centered: true)
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
            }
            AxisMarks(position: .trailing,
                      values: [0, 25, 50, 75, 100].map { Double($0) * scale }) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int((v / scale).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                AxisGridLine().foregroundStyle(.white.opacity(0.04))
            }
        }
    }

    private var windChart: some View {
        Chart(hours) { point in
            AreaMark(x: .value("Time", point.time),
                     y: .value("Wind", settings.wind(point.wind)))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [Color.teal.opacity(0.40), .teal.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", point.time),
                     y: .value("Wind", settings.wind(point.wind)))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.teal)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisValueLabel(format: .dateTime.hour(), centered: true)
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
            }
        }
    }
}

struct FooterView: View {
    let store: WeatherStore

    private func hhmm(_ iso: String) -> String {
        String(iso.suffix(5))
    }

    var body: some View {
        HStack(spacing: 16) {
            if let today = store.dashboard?.days.first {
                Label(hhmm(today.sunrise), systemImage: "sunrise.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                Label(hhmm(today.sunset), systemImage: "sunset.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.pink)
            }
            Spacer()
            Text("Data: Open-Meteo.com — free weather & air quality, no API key")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
