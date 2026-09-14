import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Default OFF = quit on close (long-standing behaviour). The settings
        // toggle keeps the app alive in the menu bar instead.
        !UserDefaults.standard.bool(forKey: "wd_menubar_keepalive")
    }
}

@main
struct WeatherDashboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = WeatherStore()

    var body: some Scene {
        WindowGroup(id: "dashboard") {
            ContentView()
                .frame(minWidth: 860, minHeight: 620)
                .environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .systemServices) { }
            CommandGroup(after: .appInfo) {
                Button("Settings…") {
                    AppSettings.shared.requestSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(store)
                .environmentObject(AppSettings.shared)
        } label: {
            if let current = store.dashboard?.current {
                Image(systemName: WMO.symbol(current.code, isDay: current.isDay))
                Text(AppSettings.shared.tempText(current.temperature) + AppSettings.shared.tempUnit.symbol)
            } else {
                Image(systemName: "cloud.sun")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject var store: WeatherStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let dash = store.dashboard {
                let current = dash.current
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text(store.place.name)
                        .font(settings.scaled(14).bold())
                    Spacer()
                    Text(WMO.description(current.code))
                        .font(settings.scaled(12))
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: WMO.symbol(current.code, isDay: current.isDay))
                        .font(.system(size: 40))
                        .foregroundStyle(Color.yellow.opacity(current.isDay ? 1.0 : 0.85))
                    Text(settings.tempText(current.temperature) + "°")
                        .font(settings.scaled(34).weight(.light).monospacedDigit())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.tf("feelsLike", settings.tempText(current.feelsLike)))
                            .font(settings.scaled(11))
                            .foregroundStyle(.secondary)
                        Text(settings.windText(current.wind) + " " + WMO.compass(current.windDirection))
                            .font(settings.scaled(11))
                            .foregroundStyle(.secondary)
                        Text(settings.t("humidity") + " \(current.humidity)%")
                            .font(settings.scaled(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let updated = store.lastUpdated {
                    Text(settings.tf("updated", updated.formatted(date: .omitted, time: .shortened)))
                        .font(settings.scaled(10))
                        .foregroundStyle(.tertiary)
                }
            } else if store.isLoading {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
            } else {
                Text(store.errorMessage ?? settings.t("noData"))
                    .font(settings.scaled(12))
                    .foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Button {
                    Task { await store.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.isLoading)
                .help(settings.t("refreshNow"))
                Spacer()
                Button(settings.t("openDashboard")) {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 280)
        .task { await store.load() }
    }
}
