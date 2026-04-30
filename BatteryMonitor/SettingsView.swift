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
    static let preferredLanguage = "preferredLanguage"
}

@MainActor
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
    @StateObject private var model = SettingsModel.shared
    @State private var langSelection: String = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first ?? ""

    var body: some View {
        ZStack {
            Color.dbBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(LocalizedStringKey("Impostazioni"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.dbText)

                    sectionGroup(title: NSLocalizedString("Generale", comment: "")) {
                        toggleRow(label: NSLocalizedString("Avvia al login", comment: ""),
                                  binding: $model.launchAtLogin)
                        Divider().background(Color.dbBorder)
                        intStepperRow(label: NSLocalizedString("Intervallo logging (minuti)", comment: ""),
                                      value: $model.logIntervalMin, range: 1...60, step: 1,
                                      display: { "\($0) min" })
                        Divider().background(Color.dbBorder)
                        languageRow
                    }

                    sectionGroup(title: NSLocalizedString("Notifiche", comment: "")) {
                        toggleRow(label: NSLocalizedString("Notifiche anomalie", comment: ""),
                                  binding: $model.calibrationNotify)
                        Divider().background(Color.dbBorder)
                        intStepperRow(label: NSLocalizedString("Soglia batteria bassa (%)", comment: ""),
                                      value: $model.lowBatteryThreshold, range: 5...50, step: 5,
                                      display: { "\($0) %" }, valueColor: .dbWarn)
                        Divider().background(Color.dbBorder)
                        doubleStepperRow(label: NSLocalizedString("Soglia temperatura (°C)", comment: ""),
                                         value: $model.temperatureThreshold, range: 35...50, step: 1,
                                         display: { String(format: "%.0f °C", $0) }, valueColor: .dbWarn)
                        Divider().background(Color.dbBorder)
                        doubleStepperRow(label: NSLocalizedString("Soglia anomalia salute (%/settimana)", comment: ""),
                                         value: $model.healthAnomalyThreshold, range: 0.5...10, step: 0.5,
                                         display: { String(format: "%.1f %%", $0) }, valueColor: .dbAccent2)
                    }

                    sectionGroup(title: NSLocalizedString("Avanzate", comment: "")) {
                        buttonRow(label: NSLocalizedString("Apri cartella dati", comment: ""),
                                  icon: "folder") {
                            if let path = HistoryStore.shared.dbPath() {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            }
                        }
                        Divider().background(Color.dbBorder)
                        buttonRow(label: NSLocalizedString("Reset storico", comment: ""),
                                  icon: "trash", color: .dbBad, action: resetHistory)
                        Divider().background(Color.dbBorder)
                        infoRow(label: NSLocalizedString("Versione", comment: ""), value: versionString)
                    }

                    Text(LocalizedStringKey("Note privacy: tutti i dati restano in locale, nessuna telemetria."))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dbText3)
                        .padding(.top, 4)
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 540, height: 580)
        .preferredColorScheme(.dark)
    }

    private var languageRow: some View {
        HStack {
            Text(LocalizedStringKey("Lingua"))
                .font(.system(size: 13))
                .foregroundStyle(Color.dbText)
            Spacer()
            Picker("", selection: $langSelection) {
                Text("Sistema").tag("")
                Text("Italiano").tag("it")
                Text("English").tag("en")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 140)
            .onChange(of: langSelection) { newLang in
                if newLang.isEmpty {
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                } else {
                    UserDefaults.standard.set([newLang], forKey: "AppleLanguages")
                }
                UserDefaults.standard.synchronize()
                showRestartAlert()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func sectionGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.dbText3)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.dbSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.dbBorder, lineWidth: 1)
            )
        }
    }

    private func toggleRow(label: String, binding: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.dbText)
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.dbAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func intStepperRow(label: String, value: Binding<Int>, range: ClosedRange<Int>,
                               step: Int, display: @escaping (Int) -> String,
                               valueColor: Color = .dbText2) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.dbText)
            Spacer()
            Text(display(value.wrappedValue))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(valueColor)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func doubleStepperRow(label: String, value: Binding<Double>, range: ClosedRange<Double>,
                                  step: Double, display: @escaping (Double) -> String,
                                  valueColor: Color = .dbText2) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.dbText)
            Spacer()
            Text(display(value.wrappedValue))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(valueColor)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func buttonRow(label: String, icon: String, color: Color = .dbText,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.dbText3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.dbText)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color.dbText2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func showRestartAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Riavvio richiesto", comment: "")
        alert.informativeText = NSLocalizedString("Il cambio lingua richiede il riavvio dell'app.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Riavvia", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Più tardi", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            relaunchApp()
        }
    }

    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.run()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            NSApp.terminate(nil)
        }
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
