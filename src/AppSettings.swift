import Foundation
import SwiftUI

enum TempUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var symbol: String { self == .fahrenheit ? "°F" : "°C" }
}

enum WindSpeedUnit: String, CaseIterable, Identifiable {
    case kmh, mph
    var id: String { rawValue }
    var symbol: String { self == .mph ? "mph" : "km/h" }
}

enum Language: String, CaseIterable, Identifiable {
    case english, polish, italian, chinese
    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .english: return "English"
        case .polish: return "Polski"
        case .italian: return "Italiano"
        case .chinese: return "中文（简体）"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english: return "en_AU"
        case .polish: return "pl_PL"
        case .italian: return "it_IT"
        case .chinese: return "zh_CN"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "wd_language") }
    }
    @Published var fontScale: Double {
        didSet { UserDefaults.standard.set(fontScale, forKey: "wd_font_scale") }
    }
    @Published var tempUnit: TempUnit {
        didSet { UserDefaults.standard.set(tempUnit.rawValue, forKey: "wd_temp_unit") }
    }
    @Published var windUnit: WindSpeedUnit {
        didSet { UserDefaults.standard.set(windUnit.rawValue, forKey: "wd_wind_unit") }
    }
    @Published var stayInMenuBar: Bool {
        didSet { UserDefaults.standard.set(stayInMenuBar, forKey: "wd_menubar_keepalive") }
    }
    @Published var settingsRequest = 0

    func requestSettings() { settingsRequest += 1 }

    private var formatCache: [String: DateFormatter] = [:]

    init() {
        let defaults = UserDefaults.standard
        language = defaults.string(forKey: "wd_language")
            .flatMap(Language.init(rawValue:)) ?? .english
        let stored = defaults.double(forKey: "wd_font_scale")
        fontScale = stored > 0 ? stored : 1.0
        tempUnit = defaults.string(forKey: "wd_temp_unit")
            .flatMap(TempUnit.init(rawValue:)) ?? .celsius
        windUnit = defaults.string(forKey: "wd_wind_unit")
            .flatMap(WindSpeedUnit.init(rawValue:)) ?? .kmh
        stayInMenuBar = defaults.bool(forKey: "wd_menubar_keepalive")
    }

    // Data is fetched and stored in metric (C, km/h, mm); converted at display time.
    func temp(_ celsius: Double) -> Double {
        tempUnit == .fahrenheit ? celsius * 9.0 / 5.0 + 32.0 : celsius
    }
    func tempText(_ celsius: Double) -> String {
        "\(Int(temp(celsius).rounded()))"
    }
    func wind(_ kmh: Double) -> Double {
        windUnit == .mph ? kmh * 0.621371 : kmh
    }
    func windText(_ kmh: Double) -> String {
        "\(Int(wind(kmh).rounded())) \(windUnit.symbol)"
    }

    func scaled(_ size: CGFloat) -> Font {
        .system(size: size * fontScale)
    }

    func formatted(_ date: Date, dateFormat: String) -> String {
        let key = "\(language.rawValue)|\(dateFormat)"
        let formatter: DateFormatter
        if let cached = formatCache[key] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.dateFormat = dateFormat
            formatter.locale = Locale(identifier: language.localeIdentifier)
            formatCache[key] = formatter
        }
        return formatter.string(from: date)
    }

    func t(_ key: String) -> String {
        Self.string(key, for: language)
    }

    func tf(_ key: String, _ args: CVarArg...) -> String {
        String(format: Self.string(key, for: language), arguments: args)
    }

    private static func string(_ key: String, for lang: Language) -> String {
        if let s = tables[lang]?[key] { return s }
        return tables[.english]?[key] ?? key
    }

    private static let tables: [Language: [String: String]] = [
        .english: [
            "fetching": "Fetching forecast…",
            "noData": "No data yet.",
            "tryAgain": "Try again",
            "updated": "Updated %@",
            "clockHelp": "Current local date and time",
            "searchCity": "Search any city worldwide",
            "manageLocs": "Manage saved locations",
            "refreshNow": "Refresh now",
            "savedLocations": "Saved locations",
            "done": "Done", "close": "Close",
            "builtinLocked": "Built-in city (cannot be removed)",
            "customCity": "Custom city",
            "currentLoc": "Current",
            "builtin": "Built-in",
            "removeLoc": "Remove this location",
            "cityNamePH": "City name…",
            "noMatches": "No matches found.",
            "feelsLike": "Feels like %@°",
            "humidity": "Humidity", "wind": "Wind", "gusts": "Gusts",
            "uvIndex": "UV index", "pressure": "Pressure",
            "rainNow": "Rain now", "airQuality": "Air quality", "pollen": "Pollen",
            "today": "TODAY",
            "next48": "Next 48 hours",
            "tabTemperature": "Temperature", "tabRainfall": "Rainfall", "tabWind": "Wind",
            "grainsFormat": "%1$.0f grains",
            "wmoUnknown": "Unknown",
            "aqiGood": "Good", "aqiModerate": "Moderate", "aqiSensitive": "Sensitive",
            "aqiUnhealthy": "Unhealthy", "aqiVeryBad": "Very bad", "aqiHazardous": "Hazardous",
            "levelLow": "Low", "levelModerate": "Moderate", "levelHigh": "High",
            "levelVeryHigh": "Very high", "levelExtreme": "Extreme",
            "settings": "Settings", "version": "Version",
            "fontSize": "Font size", "languageLabel": "Language",
            "unitsHeader": "Units",
            "stayInMenuBar": "Stay in menu bar after closing window",
            "openDashboard": "Open dashboard",
            "wmo0": "Clear sky", "wmo1": "Mainly clear",
            "wmo2": "Partly cloudy", "wmo3": "Overcast",
            "wmo45": "Fog", "wmo48": "Rime fog",
            "wmo51": "Light drizzle", "wmo53": "Drizzle", "wmo55": "Heavy drizzle",
            "wmo56": "Freezing drizzle", "wmo57": "Freezing drizzle",
            "wmo61": "Light rain", "wmo63": "Rain", "wmo65": "Heavy rain",
            "wmo66": "Freezing rain", "wmo67": "Freezing rain",
            "wmo71": "Light snow", "wmo73": "Snow", "wmo75": "Heavy snow",
            "wmo77": "Snow grains",
            "wmo80": "Light showers", "wmo81": "Showers", "wmo82": "Violent showers",
            "wmo85": "Snow showers", "wmo86": "Snow showers",
            "wmo95": "Thunderstorm", "wmo96": "Storm with hail", "wmo99": "Storm with hail"
        ],
        .polish: [
            "fetching": "Pobieram prognozę…",
            "noData": "Brak danych.",
            "tryAgain": "Spróbuj ponownie",
            "updated": "Zaktualizowano %@",
            "clockHelp": "Aktualna lokalna data i godzina",
            "searchCity": "Szukaj miasta na całym świecie",
            "manageLocs": "Zarządzaj zapisanymi lokalizacjami",
            "refreshNow": "Odśwież teraz",
            "savedLocations": "Zapisane lokalizacje",
            "done": "Gotowe", "close": "Zamknij",
            "builtinLocked": "Miasto wbudowane (nie można usunąć)",
            "customCity": "Własne miasto",
            "currentLoc": "Bieżąca",
            "builtin": "Wbudowane",
            "removeLoc": "Usuń tę lokalizację",
            "cityNamePH": "Nazwa miasta…",
            "noMatches": "Brak wyników.",
            "feelsLike": "Odczuwalne %@°",
            "humidity": "Wilgotność", "wind": "Wiatr", "gusts": "Porywy",
            "uvIndex": "Indeks UV", "pressure": "Ciśnienie",
            "rainNow": "Deszcz teraz", "airQuality": "Jakość powietrza", "pollen": "Pyłki",
            "today": "DZIŚ",
            "next48": "Najbliższe 48 godzin",
            "tabTemperature": "Temperatura", "tabRainfall": "Opady", "tabWind": "Wiatr",
            "grainsFormat": "%1$.0f ziaren",
            "wmoUnknown": "Nieznane",
            "aqiGood": "Dobra", "aqiModerate": "Umiarkowana", "aqiSensitive": "Dla wrażliwych",
            "aqiUnhealthy": "Niezdrowa", "aqiVeryBad": "Bardzo zła", "aqiHazardous": "Groźna",
            "levelLow": "Niski", "levelModerate": "Umiarkowany", "levelHigh": "Wysoki",
            "levelVeryHigh": "Bardzo wysoki", "levelExtreme": "Ekstremalny",
            "settings": "Ustawienia", "version": "Wersja",
            "fontSize": "Rozmiar czcionki", "languageLabel": "Język",
            "unitsHeader": "Jednostki",
            "stayInMenuBar": "Pozostań w pasku menu po zamknięciu okna",
            "openDashboard": "Otwórz panel",
            "wmo0": "Czyste niebo", "wmo1": "Przeważnie bezchmurnie",
            "wmo2": "Częściowe zachmurzenie", "wmo3": "Pochmurno",
            "wmo45": "Mgła", "wmo48": "Mgła osadzająca szron",
            "wmo51": "Lekka mżawka", "wmo53": "Mżawka", "wmo55": "Gęsta mżawka",
            "wmo56": "Marznąca mżawka", "wmo57": "Marznąca mżawka",
            "wmo61": "Słaby deszcz", "wmo63": "Deszcz", "wmo65": "Silny deszcz",
            "wmo66": "Marznący deszcz", "wmo67": "Marznący deszcz",
            "wmo71": "Słabe opady śniegu", "wmo73": "Śnieg", "wmo75": "Silne opady śniegu",
            "wmo77": "Ziarna śniegu",
            "wmo80": "Przelotne opady", "wmo81": "Silne przelotne opady",
            "wmo82": "Gwałtowne nawałnice",
            "wmo85": "Przelotne opady śniegu", "wmo86": "Przelotne opady śniegu",
            "wmo95": "Burza z piorunami", "wmo96": "Burza z gradem", "wmo99": "Burza z gradem"
        ],
        .italian: [
            "fetching": "Carico le previsioni…",
            "noData": "Nessun dato.",
            "tryAgain": "Riprova",
            "updated": "Aggiornato %@",
            "clockHelp": "Data e ora locali attuali",
            "searchCity": "Cerca qualsiasi città nel mondo",
            "manageLocs": "Gestisci le città salvate",
            "refreshNow": "Aggiorna ora",
            "savedLocations": "Città salvate",
            "done": "Fatto", "close": "Chiudi",
            "builtinLocked": "Città integrata (non rimovibile)",
            "customCity": "Città personalizzata",
            "currentLoc": "Attuale",
            "builtin": "Integrata",
            "removeLoc": "Rimuovi questa città",
            "cityNamePH": "Nome della città…",
            "noMatches": "Nessun risultato.",
            "feelsLike": "Percepiti %@°",
            "humidity": "Umidità", "wind": "Vento", "gusts": "Raffiche",
            "uvIndex": "Indice UV", "pressure": "Pressione",
            "rainNow": "Pioggia ora", "airQuality": "Qualità dell'aria", "pollen": "Polline",
            "today": "OGGI",
            "next48": "Prossime 48 ore",
            "tabTemperature": "Temperatura", "tabRainfall": "Precipitazioni", "tabWind": "Vento",
            "grainsFormat": "%1$.0f granelli",
            "wmoUnknown": "Sconosciuto",
            "aqiGood": "Buona", "aqiModerate": "Moderata", "aqiSensitive": "Per sensibili",
            "aqiUnhealthy": "Malsana", "aqiVeryBad": "Molto cattiva", "aqiHazardous": "Pericolosa",
            "levelLow": "Basso", "levelModerate": "Moderato", "levelHigh": "Alto",
            "levelVeryHigh": "Molto alto", "levelExtreme": "Estremo",
            "settings": "Impostazioni", "version": "Versione",
            "fontSize": "Dimensione testo", "languageLabel": "Lingua",
            "unitsHeader": "Unità",
            "stayInMenuBar": "Resta nella barra dei menu dopo la chiusura della finestra",
            "openDashboard": "Apri il pannello",
            "wmo0": "Cielo sereno", "wmo1": "Prevalentemente sereno",
            "wmo2": "Parzialmente nuvoloso", "wmo3": "Coperto",
            "wmo45": "Nebbia", "wmo48": "Nebbia con brina",
            "wmo51": "Pioviggine leggera", "wmo53": "Pioviggine", "wmo55": "Pioviggine forte",
            "wmo56": "Pioviggine congelante", "wmo57": "Pioviggine congelante",
            "wmo61": "Pioggia debole", "wmo63": "Pioggia", "wmo65": "Pioggia forte",
            "wmo66": "Pioggia congelante", "wmo67": "Pioggia congelante",
            "wmo71": "Neve debole", "wmo73": "Neve", "wmo75": "Neve forte",
            "wmo77": "Granuli di neve",
            "wmo80": "Rovesci leggeri", "wmo81": "Rovesci", "wmo82": "Rovesci violenti",
            "wmo85": "Rovesci di neve", "wmo86": "Rovesci di neve",
            "wmo95": "Temporale", "wmo96": "Temporale con grandine", "wmo99": "Temporale con grandine"
        ],
        .chinese: [
            "fetching": "正在获取天气预报…",
            "noData": "暂无数据。",
            "tryAgain": "重试",
            "updated": "已于%@更新",
            "clockHelp": "当地时间与日期",
            "searchCity": "搜索全球任意城市",
            "manageLocs": "管理已保存的位置",
            "refreshNow": "立即刷新",
            "savedLocations": "已保存的位置",
            "done": "完成", "close": "关闭",
            "builtinLocked": "内置城市（无法删除）",
            "customCity": "自定义城市",
            "currentLoc": "当前",
            "builtin": "内置",
            "removeLoc": "删除此位置",
            "cityNamePH": "城市名称…",
            "noMatches": "未找到匹配结果。",
            "feelsLike": "体感 %@°",
            "humidity": "湿度", "wind": "风速", "gusts": "阵风",
            "uvIndex": "紫外线指数", "pressure": "气压",
            "rainNow": "当前降水", "airQuality": "空气质量", "pollen": "花粉",
            "today": "今天",
            "next48": "未来48小时",
            "tabTemperature": "温度", "tabRainfall": "降雨", "tabWind": "风速",
            "grainsFormat": "%1$.0f 粒",
            "wmoUnknown": "未知",
            "aqiGood": "优", "aqiModerate": "良", "aqiSensitive": "敏感人群不健康",
            "aqiUnhealthy": "不健康", "aqiVeryBad": "非常不健康", "aqiHazardous": "危险",
            "levelLow": "低", "levelModerate": "中等", "levelHigh": "高",
            "levelVeryHigh": "很高", "levelExtreme": "极高",
            "settings": "设置", "version": "版本",
            "fontSize": "字体大小", "languageLabel": "语言",
            "unitsHeader": "单位",
            "stayInMenuBar": "关闭窗口后保留在菜单栏",
            "openDashboard": "打开面板",
            "wmo0": "晴", "wmo1": "大部晴朗",
            "wmo2": "局部多云", "wmo3": "阴天",
            "wmo45": "雾", "wmo48": "冻雾",
            "wmo51": "小毛毛雨", "wmo53": "毛毛雨", "wmo55": "大毛毛雨",
            "wmo56": "冻毛毛雨", "wmo57": "冻毛毛雨",
            "wmo61": "小雨", "wmo63": "中雨", "wmo65": "大雨",
            "wmo66": "冻雨", "wmo67": "冻雨",
            "wmo71": "小雪", "wmo73": "中雪", "wmo75": "大雪",
            "wmo77": "雪粒",
            "wmo80": "小阵雨", "wmo81": "阵雨", "wmo82": "强阵雨",
            "wmo85": "阵雪", "wmo86": "阵雪",
            "wmo95": "雷暴", "wmo96": "雷暴伴冰雹", "wmo99": "雷暴伴冰雹"
        ]
    ]
}
