import SwiftUI
import AppKit

@main
struct DoctorBatteryApp: App {
    @StateObject private var vm = AppViewModel()

    init() {
        Notifier.shared.requestAuthIfNeeded()
    }

    var body: some Scene {
        WindowGroup("Doctor Battery") {
            ContentView(vm: vm)
                .frame(minWidth: 820, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(LocalizedStringKey("Informazioni su Doctor Battery")) {
                    showAbout()
                }
            }
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            MenuBarContent(vm: vm)
        } label: {
            MenuBarLabel(model: vm.menuBar)
        }
        .menuBarExtraStyle(.window)
    }

    private func showAbout() {
        let opts: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Doctor Battery",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            .version: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1",
            .credits: NSAttributedString(
                string: "Open source battery diagnostics for Mac, iOS and iPadOS.\n\nAll data stays local — no telemetry.\n\nUses libimobiledevice (LGPL).",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            )
        ]
        NSApp.orderFrontStandardAboutPanel(options: opts)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: MenuBarModel
    var body: some View {
        if model.hasSnapshot {
            HStack(spacing: 4) {
                Image(systemName: batteryIcon(percent: model.percent, charging: model.isCharging))
                Text("\(model.percent)%")
                    .font(.system(.caption, design: .monospaced))
            }
        } else {
            Image(systemName: "battery.0")
        }
    }

    private func batteryIcon(percent: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default:    return "battery.100"
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var vm: AppViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let s = vm.macSnapshot {
                Text("Mac").font(.headline)
                miniRow(LocalizedStringKey("Carica"), String(format: "%.0f %%", s.nominalChargePercent))
                miniRow(LocalizedStringKey("Salute"), String(format: "%.1f %%", s.healthPercent))
                miniRow(LocalizedStringKey("Cicli"), "\(s.cycleCount)")
                miniRow(LocalizedStringKey("Potenza"), String(format: "%.2f W", s.wattage))
                miniRow(LocalizedStringKey("Temp"), String(format: "%.1f °C", s.temperatureC))
                Divider()
            }
            ForEach(vm.iosDevices) { d in
                let snap = vm.iosSnapshots[d.udid]
                Text(d.name).font(.headline)
                if let s = snap {
                    miniRow(LocalizedStringKey("Carica"), "\(s.chargePercent) %")
                    if let h = s.healthPercent {
                        miniRow(LocalizedStringKey("Salute"), String(format: "%.1f %%", h))
                    }
                    if let c = s.cycleCount { miniRow(LocalizedStringKey("Cicli"), "\(c)") }
                }
                Divider()
            }
            Button(LocalizedStringKey("Apri finestra")) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            Button(LocalizedStringKey("Esci")) { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 240)
    }

    private func miniRow(_ k: LocalizedStringKey, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary).font(.caption)
            Spacer()
            Text(v).font(.system(.caption, design: .monospaced))
        }
    }
}
