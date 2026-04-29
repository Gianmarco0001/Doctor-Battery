import SwiftUI
import ServiceManagement
import AppKit

enum SettingsKeys {
    static let logIntervalMin = "logIntervalMin"
    static let lowBatteryThreshold = "lowBatteryThreshold"
    static let temperatureThreshold = "temperatureThreshold"
    static let healthAnomalyThreshold = "healthAnomalyThreshold"
    static let calibrationNotify = "calibrationNotify"
    static let launchAtLogin = "launchAtLogin"
    static let showInMenuBar = "showInMenuBar"
}

final class SettingsModel: ObservableObject {
    @Published var logIntervalMin: Int {
        didSet { UserDefaults.standard.set(logIntervalMin, forKey: SettingsKeys.logIntervalMin) }
    }
    @Published var lowBatteryThreshold: Int {
        didSet { UserDefaults.standard.set(lowBatteryThreshold, forKey: SettingsKeys.lowBatteryThreshold) }
    }
    @Published var temperatureThreshold: Double {
        didSet { UserDefaults.standard.set(temperatureThreshold, forKey: SettingsKeys.temperatureThreshold) }
    }
    @Published var healthAnomalyThreshold: Double {
        didSet { UserDefaults.standard.set(healthAnomalyThreshold, forKey: SettingsKeys.healthAnomalyThreshold) }
    }
    @Published var calibrationNotify: Bool {
        didSet { UserDefaults.standard.set(calibrationNotify, forKey: SettingsKeys.calibrationNotify) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: SettingsKeys.launchAtLogin)
            applyLaunchAtLogin(launchAtLogin)
        }
    }
    static let shared = SettingsModel()

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: SettingsKeys.logIntervalMin) == nil {
            d.set(5, forKey: SettingsKeys.logIntervalMin)
            d.set(20, forKey: SettingsKeys.lowBatteryThreshold)
            d.set(40.0, forKey: SettingsKeys.temperatureThreshold)
            d.set(2.0, forKey: SettingsKeys.healthAnomalyThreshold)
            d.set(true, forKey: SettingsKeys.calibrationNotify)
            d.set(false, forKey: SettingsKeys.launchAtLogin)
        }
        self.logIntervalMin = d.integer(forKey: SettingsKeys.logIntervalMin)
        self.lowBatteryThreshold = d.integer(forKey: SettingsKeys.lowBatteryThreshold)
        self.temperatureThreshold = d.double(forKey: SettingsKeys.temperatureThreshold)
        self.healthAnomalyThreshold = d.double(forKey: SettingsKeys.healthAnomalyThreshold)
        self.calibrationNotify = d.bool(forKey: SettingsKeys.calibrationNotify)
        self.launchAtLogin = d.bool(forKey: SettingsKeys.launchAtLogin)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        let svc = SMAppService.mainApp
        do {
            if enabled {
                if svc.status != .enabled { try svc.register() }
            } else {
                if svc.status == .enabled { try svc.unregister() }
            }
        } catch {
            NSLog("Launch at login error: \(error.localizedDescription)")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model = SettingsModel.shared

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(LocalizedStringKey("Generale"), systemImage: "gear") }
            notificationsTab
                .tabItem { Label(LocalizedStringKey("Notifiche"), systemImage: "bell") }
            advancedTab
                .tabItem { Label(LocalizedStringKey("Avanzate"), systemImage: "wrench") }
        }
        .frame(width: 520, height: 380)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle(LocalizedStringKey("Avvia al login"), isOn: $model.launchAtLogin)
                LabeledContent(NSLocalizedString("Intervallo logging (minuti)", comment: "")) {
                    HStack(spacing: 8) {
                        Text("\(model.logIntervalMin)")
                            .frame(minWidth: 24, alignment: .trailing)
                            .monospacedDigit()
                        Stepper("", value: $model.logIntervalMin, in: 1...60)
                            .labelsHidden()
                    }
                }
            }
            Section {
                Text(LocalizedStringKey("Note privacy: tutti i dati restano in locale, nessuna telemetria."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var notificationsTab: some View {
        Form {
            Section {
                LabeledContent(NSLocalizedString("Soglia batteria bassa (%)", comment: "")) {
                    HStack(spacing: 8) {
                        Text("\(model.lowBatteryThreshold)")
                            .frame(minWidth: 32, alignment: .trailing)
                            .monospacedDigit()
                        Stepper("", value: $model.lowBatteryThreshold, in: 5...50, step: 5)
                            .labelsHidden()
                    }
                }
                LabeledContent(NSLocalizedString("Soglia temperatura (°C)", comment: "")) {
                    HStack(spacing: 8) {
                        Text(String(format: "%.0f", model.temperatureThreshold))
                            .frame(minWidth: 32, alignment: .trailing)
                            .monospacedDigit()
                        Stepper("", value: $model.temperatureThreshold, in: 35...50, step: 1)
                            .labelsHidden()
                    }
                }
                LabeledContent(NSLocalizedString("Soglia anomalia salute (%/settimana)", comment: "")) {
                    HStack(spacing: 8) {
                        Text(String(format: "%.1f", model.healthAnomalyThreshold))
                            .frame(minWidth: 32, alignment: .trailing)
                            .monospacedDigit()
                        Stepper("", value: $model.healthAnomalyThreshold, in: 0.5...10, step: 0.5)
                            .labelsHidden()
                    }
                }
                Toggle(LocalizedStringKey("Notifica calibrazione consigliata"),
                       isOn: $model.calibrationNotify)
            }
        }
        .formStyle(.grouped)
    }

    private var advancedTab: some View {
        Form {
            Section {
                Button(LocalizedStringKey("Apri cartella dati")) {
                    if let path = HistoryStore.shared.dbPath() {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
                Button(LocalizedStringKey("Reset storico"), role: .destructive) {
                    resetHistory()
                }
            }
            Section {
                LabeledContent(NSLocalizedString("Versione", comment: "")) {
                    Text(versionString).font(.system(.body, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
    }

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func resetHistory() {
        guard let path = HistoryStore.shared.dbPath() else { return }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Reset storico", comment: "")
        alert.informativeText = "Questo cancellerà tutto lo storico. Continuare?"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            try? FileManager.default.removeItem(atPath: path)
            NSApp.terminate(nil)
        }
    }
}
