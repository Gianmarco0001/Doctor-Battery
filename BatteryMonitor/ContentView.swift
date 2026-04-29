import SwiftUI
import Charts
import AppKit

enum Selection: Hashable {
    case mac
    case ios(String)
    case compare
}

final class AppViewModel: ObservableObject {
    @Published var selection: Selection = .mac
    @Published var macSnapshot: BatterySnapshot?
    @Published var iosDevices: [IOSDevice] = []
    @Published var iosSnapshots: [String: IOSBatterySnapshot] = [:]
    @Published var libimobileMissing: Bool = false

    @Published var macWattageHistory: [(Date, Double)] = []
    @Published var lastFullDischarge: Date?

    private var fastTimer: Timer?
    private var slowTimer: Timer?
    private var loggingTimer: Timer?
    private var lastLoggedMac: Date = .distantPast
    private var lastLoggedIOS: [String: Date] = [:]
    private let logInterval: TimeInterval = 5 * 60

    init() {
        refreshAll()
        rescanDevices()
        fastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
        slowTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            self?.rescanDevices()
        }
        loggingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.maybeLog()
        }
    }

    deinit { fastTimer?.invalidate(); slowTimer?.invalidate(); loggingTimer?.invalidate() }

    func refreshAll() {
        let mac = BatteryReader.read()
        var iosSnaps: [String: IOSBatterySnapshot] = [:]
        for d in iosDevices {
            if let s = IOSDeviceReader.battery(for: d) { iosSnaps[d.udid] = s }
        }
        DispatchQueue.main.async {
            self.macSnapshot = mac
            self.iosSnapshots = iosSnaps
            if let m = mac {
                Notifier.shared.evaluateMac(m)
                self.appendWattage(m)
                if !m.isCharging && m.nominalChargePercent < 5 { self.lastFullDischarge = Date() }
            }
            for d in self.iosDevices {
                if let s = iosSnaps[d.udid] {
                    Notifier.shared.evaluateIOS(udid: d.udid, name: d.name, snapshot: s)
                }
            }
        }
    }

    private func appendWattage(_ s: BatterySnapshot) {
        macWattageHistory.append((s.timestamp, s.wattage))
        let cutoff = Date().addingTimeInterval(-30 * 60)
        macWattageHistory.removeAll { $0.0 < cutoff }
    }

    func macWattageMovingAvg(window: TimeInterval) -> Double? {
        let cutoff = Date().addingTimeInterval(-window)
        let recent = macWattageHistory.filter { $0.0 >= cutoff }
        guard !recent.isEmpty else { return nil }
        return recent.map(\.1).reduce(0, +) / Double(recent.count)
    }

    private func maybeLog() {
        let now = Date()
        if let m = macSnapshot, now.timeIntervalSince(lastLoggedMac) >= logInterval {
            HistoryStore.shared.recordMac(m)
            lastLoggedMac = now
        }
        for (udid, snap) in iosSnapshots {
            let last = lastLoggedIOS[udid] ?? .distantPast
            if now.timeIntervalSince(last) >= logInterval {
                HistoryStore.shared.recordIOS(udid: udid, snapshot: snap)
                lastLoggedIOS[udid] = now
            }
        }
    }

    func rescanDevices() {
        let status = IOSDeviceReader.toolchain()
        let missing: Bool
        let devs: [IOSDevice]
        switch status {
        case .ok: missing = false; devs = IOSDeviceReader.listDevices()
        case .missing: missing = true; devs = []
        }
        DispatchQueue.main.async {
            self.libimobileMissing = missing
            self.iosDevices = devs
        }
    }
}

struct ContentView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    private var sidebar: some View {
        List(selection: Binding(
            get: { vm.selection },
            set: { if let v = $0 { vm.selection = v } }
        )) {
            Section(LocalizedStringKey("Mac")) {
                Label(LocalizedStringKey("Questo Mac"), systemImage: "laptopcomputer").tag(Selection.mac)
            }
            Section(LocalizedStringKey("Confronto")) {
                Label(LocalizedStringKey("Tutti i dispositivi"), systemImage: "chart.line.uptrend.xyaxis").tag(Selection.compare)
            }
            Section("Dispositivi iOS / iPadOS") {
                if vm.libimobileMissing {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("libimobiledevice non installato", systemImage: "exclamationmark.triangle").font(.caption)
                        Text("brew install libimobiledevice").font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                } else if vm.iosDevices.isEmpty {
                    Text("Nessun dispositivo").foregroundStyle(.secondary).font(.caption)
                } else {
                    ForEach(vm.iosDevices) { dev in
                        Label {
                            VStack(alignment: .leading) {
                                Text(dev.name)
                                if dev.unreachableReason != nil {
                                    Text("⚠ \(dev.connection.rawValue)")
                                        .font(.caption2).foregroundStyle(.orange)
                                } else {
                                    Text(dev.connection.rawValue)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: dev.connection == .usb ? "cable.connector" : "wifi")
                        }
                        .tag(Selection.ios(dev.udid))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private var detail: some View {
        switch vm.selection {
        case .mac:
            MacDetailView(vm: vm)
        case .ios(let udid):
            if let dev = vm.iosDevices.first(where: { $0.udid == udid }) {
                IOSDetailView(device: dev, snapshot: vm.iosSnapshots[udid])
            } else {
                Text("Dispositivo non più disponibile").foregroundStyle(.secondary)
            }
        case .compare:
            CompareView(vm: vm)
        }
    }
}

struct CompareView: View {
    @ObservedObject var vm: AppViewModel
    @State private var range: HistoryCard.HistoryRange = .month
    @State private var data: [(deviceId: String, label: String, points: [HistoryPoint])] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.title)
                    Text(LocalizedStringKey("Tutti i dispositivi")).font(.title2.bold())
                    Spacer()
                    Button {
                        vm.refreshAll()
                        reload()
                    } label: {
                        Label("Aggiorna", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    Picker("", selection: $range) {
                        ForEach(HistoryCard.HistoryRange.allCases) { r in Text(r.rawValue).tag(r) }
                    }.pickerStyle(.segmented).fixedSize()
                }
                Card("Trend salute") {
                    if data.isEmpty {
                        Text(LocalizedStringKey("In raccolta dati… (uno snapshot ogni 5 minuti)"))
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        Chart {
                            ForEach(data, id: \.deviceId) { series in
                                ForEach(series.points, id: \.timestamp) { p in
                                    if let h = p.healthPercent {
                                        LineMark(x: .value("t", p.timestamp), y: .value("Salute %", h))
                                            .foregroundStyle(by: .value("Device", series.label))
                                    }
                                }
                            }
                        }
                        .chartYScale(domain: 60...100)
                        .frame(height: 220)
                    }
                }
                Card("Carica nel tempo") {
                    if data.isEmpty {
                        Text(LocalizedStringKey("In raccolta dati… (uno snapshot ogni 5 minuti)"))
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        Chart {
                            ForEach(data, id: \.deviceId) { series in
                                ForEach(series.points, id: \.timestamp) { p in
                                    if let c = p.chargePercent {
                                        LineMark(x: .value("t", p.timestamp), y: .value("Carica %", c))
                                            .foregroundStyle(by: .value("Device", series.label))
                                    }
                                }
                            }
                        }
                        .chartYScale(domain: 0...100)
                        .frame(height: 180)
                    }
                }
                ForEach(data, id: \.deviceId) { series in
                    if let f = HealthAnalytics.forecast(points: series.points) {
                        ForecastCard(label: series.label, forecast: f)
                    }
                }
            }
            .padding(20)
        }
        .onAppear { reload() }
        .onChange(of: range) { _ in reload() }
        .onChange(of: vm.iosDevices) { _ in reload() }
    }

    private func reload() {
        let since = Date().addingTimeInterval(-range.seconds)
        var out: [(String, String, [HistoryPoint])] = []
        let macPts = HistoryStore.shared.points(deviceId: "mac", since: since)
        if !macPts.isEmpty { out.append(("mac", "Mac", macPts)) }
        for d in vm.iosDevices {
            let pts = HistoryStore.shared.points(deviceId: d.udid, since: since)
            if !pts.isEmpty { out.append((d.udid, d.name, pts)) }
        }
        data = out
    }
}

struct ForecastCard: View {
    let label: String
    let forecast: HealthForecast

    var body: some View {
        Card("\(NSLocalizedString("Previsione salute", comment: "")) — \(label)") {
            row(NSLocalizedString("Salute (raw FCC)", comment: ""),
                String(format: "%.1f %%", forecast.currentHealth))
            row(NSLocalizedString("Trend salute", comment: ""),
                String(format: "%.3f %%/giorno", forecast.slopePerDay))
            if let d = forecast.dateAtThreshold {
                row(NSLocalizedString("Salute prevista a 80 %", comment: ""), formatDate(d))
            }
            if let c = forecast.cyclesUntilThreshold {
                row(NSLocalizedString("Cicli stimati restanti", comment: ""), "\(c)")
            }
            ProgressView(value: forecast.confidence) {
                Text("R² \(String(format: "%.2f", forecast.confidence))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }
}

struct MacDetailView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let s = vm.macSnapshot {
                    header(s)
                    chargeCard(s)
                    healthCard(s)
                    powerCard(s)
                    if let a = s.adapter { adapterCard(a) }
                    infoCard(s)
                    HistoryCard(deviceId: "mac", title: "Storico Mac")
                } else {
                    Text("Nessuna batteria rilevata").foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ s: BatterySnapshot) -> some View {
        HStack {
            Image(systemName: "battery.100.bolt").font(.title)
            VStack(alignment: .leading) {
                Text(LocalizedStringKey("Questo Mac")).font(.title2.bold())
                Text(s.deviceName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                vm.refreshAll()
            } label: { Label("Aggiorna", systemImage: "arrow.clockwise") }
            .buttonStyle(.borderless)
            Text(s.timestamp, style: .time).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chargeCard(_ s: BatterySnapshot) -> some View {
        Card("Carica") {
            row("Stato", s.fullyCharged ? "Carica completa" :
                s.isCharging ? "In carica" :
                s.isPluggedIn ? "Collegato" : "A batteria")
            row("Carica attuale", String(format: "%.0f %%", s.nominalChargePercent))
            row("Capacità attuale", "\(s.currentCapacity) mAh")
            row("Low Power Mode", s.lowPowerMode ? "Attivo" : "Disattivato")
            row("Optimized Charging", s.optimizedChargingEngaged ? "Sì" : "No")
            if s.isCharging, let t = s.timeToFullMin {
                row("Tempo a carica completa", formatMinutes(t))
            } else if !s.isCharging, let t = s.timeToEmptyMin {
                row("Tempo a esaurimento (IOKit)", formatMinutes(t))
            }
            if !s.isCharging, let avgW = vm.macWattageMovingAvg(window: 600), avgW < -0.1 {
                let hoursLeft = (Double(s.currentCapacity) * s.voltageV / 1000.0) / abs(avgW)
                row("Stima ETA (10 min media)", formatHoursDecimal(hoursLeft))
            }
        }
    }

    private func healthCard(_ s: BatterySnapshot) -> some View {
        Card("Salute") {
            row("Salute (raw FCC)", String(format: "%.1f %%", s.healthPercent))
            row("Capacità di design", "\(s.designCapacity) mAh")
            row("Capacità massima", "\(s.maxCapacity) mAh")
            row("Cicli di carica", "\(s.cycleCount)")
            if let d = s.manufactureDate { row("Data produzione", formatDate(d)) }
            if let d = s.firstUseDate { row("Primo utilizzo", formatDate(d)) }
            if let cal = calibrationSuggestion(lastFull: vm.lastFullDischarge) {
                Text(cal).font(.caption2).foregroundStyle(.orange).padding(.top, 4)
            }
            Text("Valore raw dal gas-gauge IC. Può differire dal numero in Impostazioni macOS che include impedenza e cronologia throttling.")
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    private func powerCard(_ s: BatterySnapshot) -> some View {
        Card("Energia") {
            row("Voltaggio", String(format: "%.3f V", s.voltageV))
            row("Corrente", String(format: "%.3f A", s.amperageA))
            row("Potenza istantanea", String(format: "%.2f W", s.wattage))
            if let avg1 = vm.macWattageMovingAvg(window: 60) {
                row("Potenza media 1 min", String(format: "%.2f W", avg1))
            }
            if let avg10 = vm.macWattageMovingAvg(window: 600) {
                row("Potenza media 10 min", String(format: "%.2f W", avg10))
            }
            row("Temperatura", String(format: "%.1f °C", s.temperatureC))
        }
    }

    private func adapterCard(_ a: AdapterInfo) -> some View {
        Card("Alimentatore") {
            row(NSLocalizedString("Nome", comment: ""), a.name)
            row(NSLocalizedString("Wattaggio", comment: ""), "\(a.watts) W")
            row(NSLocalizedString("Modello", comment: ""), a.model)
            row(NSLocalizedString("Produttore", comment: ""), a.manufacturer)
            row(NSLocalizedString("Numero di serie", comment: ""), a.serial)
            row(NSLocalizedString("Qualità alimentatore", comment: ""),
                AdapterDatabase.classifyMac(a).localized)
        }
    }

    private func infoCard(_ s: BatterySnapshot) -> some View {
        Card("Identificazione") {
            row("Produttore", s.manufacturer)
            row("Numero di serie", s.serial)
            row("Battery installed", s.batteryInstalled ? "Sì" : "No")
        }
    }

    private func calibrationSuggestion(lastFull: Date?) -> String? {
        guard let last = lastFull else {
            return "Suggerimento: non risulta una scarica completa nello storico. Una scarica fino a spegnimento + ricarica al 100 % aiuta il gas-gauge a ricalibrarsi."
        }
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        if days > 30 {
            return "Suggerimento: ultima scarica completa \(days) giorni fa — prendi in considerazione una calibrazione."
        }
        return nil
    }
}

struct IOSDetailView: View {
    let device: IOSDevice
    let snapshot: IOSBatterySnapshot?
    @State private var showDiag = false
    @State private var showRegistry = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let reason = device.unreachableReason {
                    Card("Stato connessione") {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("UDID: \(device.udid)")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
                if let s = snapshot {
                    Card("Carica") {
                        row("Carica", "\(s.chargePercent) %")
                        row("In carica", s.isCharging ? "Sì" : "No")
                        row("Collegato", s.externalConnected ? "Sì" : "No")
                        row("Charge capable", s.externalChargeCapable ? "Sì" : "No")
                        row("Carica completa", s.fullyCharged ? "Sì" : "No")
                        row("Batteria presente", s.hasBattery ? "Sì" : "No")
                    }
                    if s.cycleCount != nil || s.designCapacity != nil || s.nominalCapacity != nil
                        || s.absoluteCapacity != nil || s.healthPercent != nil {
                        Card("Salute") {
                            if let c = s.cycleCount { row("Cicli di carica", "\(c)") }
                            if let d = s.designCapacity { row("Capacità di design", "\(d) mAh") }
                            if let n = s.nominalCapacity { row("Capacità massima", "\(n) mAh") }
                            if let a = s.absoluteCapacity { row("Capacità attuale", "\(a) mAh") }
                            if let h = s.healthPercent { row("Salute (raw FCC)", String(format: "%.1f %%", h)) }
                            Text("Valore raw dal gas-gauge IC. Può differire da Impostazioni → Batteria che include cycle count e impedenza.")
                                .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                        }
                    } else {
                        Card("Salute") {
                            Text("Nessun campo capacità trovato. Vedi diagnostica grezza.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if s.temperatureC != nil || s.voltageV != nil || s.amperageA != nil {
                        Card("Energia") {
                            if let t = s.temperatureC { row("Temperatura", String(format: "%.1f °C", t)) }
                            if let v = s.voltageV { row("Voltaggio", String(format: "%.3f V", v)) }
                            if let a = s.amperageA { row("Corrente", String(format: "%.3f A", a)) }
                        }
                    }
                    if let a = s.adapter {
                        Card("Alimentatore") {
                            if let w = a.watts { row(NSLocalizedString("Wattaggio", comment: ""), "\(w) W") }
                            if let d = a.description { row(NSLocalizedString("Tipo", comment: ""), d) }
                            if let v = a.voltageV { row(NSLocalizedString("Voltaggio", comment: ""), String(format: "%.2f V", v)) }
                            if let c = a.currentA { row(NSLocalizedString("Corrente max", comment: ""), String(format: "%.2f A", c)) }
                            if let w = a.isWireless { row(NSLocalizedString("Wireless", comment: ""), w ? NSLocalizedString("Sì", comment: "") : NSLocalizedString("No", comment: "")) }
                            row(NSLocalizedString("Qualità alimentatore", comment: ""),
                                AdapterDatabase.classifyIOSAdapter(description: a.description, watts: a.watts).localized)
                        }
                    }
                    Card("Identificazione") {
                        row("UDID", device.udid)
                        row("Connessione", device.connection.rawValue)
                        row("Modello", device.productType)
                        row("Sistema", device.osVersion)
                        row("Serial dispositivo", device.serial)
                        if let s = s.serial { row("Serial batteria", s) }
                        if let m = s.manufacturer { row("Produttore batteria", m) }
                    }
                    HistoryCard(deviceId: device.udid, title: "Storico \(device.name)")
                    diagnosticSection(s.diagnostic)
                } else {
                    Text("Lettura batteria non riuscita. Verifica che il dispositivo sia sbloccato e che il trust sia attivo.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: device.connection == .usb ? "iphone.gen3" : "iphone.gen3.radiowaves.left.and.right").font(.title)
            VStack(alignment: .leading) {
                Text(device.name).font(.title2.bold())
                Text("\(device.osVersion) — via \(device.connection.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let ts = snapshot?.timestamp {
                Text(ts, style: .time).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func diagnosticSection(_ d: IOSDiagnosticInfo) -> some View {
        DisclosureGroup(isExpanded: $showDiag) {
            VStack(alignment: .leading, spacing: 10) {
                Text("com.apple.mobile.battery").font(.caption.bold())
                Text(d.batteryDomainRaw.isEmpty ? "(vuoto)" : d.batteryDomainRaw)
                    .font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(d.ioregAttempts.enumerated()), id: \.offset) { _, t in
                    Text("idevicediagnostics ioregentry \(t.className)").font(.caption.bold())
                    if !t.stderr.isEmpty {
                        Text("stderr: \(t.stderr)")
                            .font(.system(.caption2, design: .monospaced)).foregroundStyle(.red).textSelection(.enabled)
                    }
                    Text(t.stdout.isEmpty ? "(stdout vuoto)" : String(t.stdout.prefix(2000)))
                        .font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Diagnostica grezza").font(.headline)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct HistoryCard: View {
    let deviceId: String
    let title: String
    @State private var range: HistoryRange = .day
    @State private var points: [HistoryPoint] = []

    enum HistoryRange: String, CaseIterable, Identifiable {
        case hour = "1h", day = "24h", week = "7g", month = "30g", all = "Tutto"
        var id: String { rawValue }
        var seconds: TimeInterval {
            switch self {
            case .hour: 3600; case .day: 86400; case .week: 7*86400
            case .month: 30*86400; case .all: 365*86400*10
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Picker("", selection: $range) {
                    ForEach(HistoryRange.allCases) { r in Text(r.rawValue).tag(r) }
                }
                .pickerStyle(.segmented).fixedSize()
                Button {
                    if let url = HistoryStore.shared.exportCSV(deviceId: deviceId) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderless)
            }
            if points.isEmpty {
                Text("In raccolta dati… (uno snapshot ogni 5 minuti)")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(points, id: \.timestamp) { p in
                    if let h = p.healthPercent {
                        LineMark(x: .value("t", p.timestamp), y: .value("Salute %", h))
                            .foregroundStyle(by: .value("Serie", "Salute %"))
                    }
                    if let c = p.chargePercent {
                        LineMark(x: .value("t", p.timestamp), y: .value("Carica %", c))
                            .foregroundStyle(by: .value("Serie", "Carica %"))
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 160)
                if let lastCycle = points.compactMap(\.cycleCount).last,
                   let firstCycle = points.compactMap(\.cycleCount).first,
                   lastCycle > firstCycle {
                    Text("Cicli aumentati di \(lastCycle - firstCycle) nel periodo selezionato (da \(firstCycle) a \(lastCycle))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .onAppear { reload() }
        .onChange(of: range) { _ in reload() }
    }

    private func reload() {
        let since = Date().addingTimeInterval(-range.seconds)
        points = HistoryStore.shared.points(deviceId: deviceId, since: since)
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

func row(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top) {
        Text(label).foregroundStyle(.secondary)
        Spacer()
        Text(value).font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.trailing).textSelection(.enabled)
    }
}

func formatMinutes(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}

func formatHoursDecimal(_ h: Double) -> String {
    let total = max(0, Int(h * 60))
    return formatMinutes(total)
}

func formatDate(_ d: Date) -> String {
    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
    return f.string(from: d)
}
