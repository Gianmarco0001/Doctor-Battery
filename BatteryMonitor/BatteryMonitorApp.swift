import SwiftUI
import AppKit

@main
struct DoctorBatteryApp: App {
    @StateObject private var vm = AppViewModel()
    @StateObject private var settings = SettingsModel.shared

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
            MenuBarLabel(vm: vm)
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
    @ObservedObject var vm: AppViewModel
    var body: some View {
        if let s = vm.macSnapshot {
            HStack(spacing: 4) {
                Image(systemName: s.isCharging ? "battery.100.bolt" : "battery.75")
                Text(String(format: "%.0f%%", s.nominalChargePercent))
                    .font(.system(.caption, design: .monospaced))
            }
        } else {
            Image(systemName: "battery.0")
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
