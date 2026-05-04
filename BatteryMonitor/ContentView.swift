import SwiftUI
import Charts
import AppKit

enum Selection: Hashable {
    case mac
    case ios(String)
    case compare
}

enum DBFormat {
    static func percent(_ v: Double, fraction: Int = 0) -> String {
        v.formatted(.number.precision(.fractionLength(fraction))) + " %"
    }
    static func watt(_ v: Double, fraction: Int = 2) -> String {
        v.formatted(.number.precision(.fractionLength(fraction))) + " W"
    }
    static func celsius(_ v: Double, fraction: Int = 1) -> String {
        v.formatted(.number.precision(.fractionLength(fraction))) + " °C"
    }
    static func volt(_ v: Double, fraction: Int = 2) -> String {
        v.formatted(.number.precision(.fractionLength(fraction))) + " V"
    }
    static func ampere(_ v: Double, fraction: Int = 2) -> String {
        v.formatted(.number.precision(.fractionLength(fraction))) + " A"
    }
    static func decimal(_ v: Double, fraction: Int) -> String {
        v.formatted(.number.precision(.fractionLength(fraction)))
    }
}

@MainActor
final class MenuBarModel: ObservableObject {
    @Published var percent: Int = 0
    @Published var isCharging: Bool = false
    @Published var hasSnapshot: Bool = false

    func update(snapshot: BatterySnapshot?) {
        guard let s = snapshot else {
            if hasSnapshot { hasSnapshot = false }
            return
        }
        let p = Int(s.nominalChargePercent.rounded())
        if p != percent { percent = p }
        if s.isCharging != isCharging { isCharging = s.isCharging }
        if !hasSnapshot { hasSnapshot = true }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selection: Selection = .mac
    @Published var macSnapshot: BatterySnapshot?
    @Published var iosDevices: [IOSDevice] = []
    @Published var iosSnapshots: [String: IOSBatterySnapshot] = [:]
    @Published var libimobileMissing: Bool = false

    private var macWattageHistory: [(Date, Double)] = []
    @Published var macWattageAvg1: Double?
    @Published var macWattageAvg10: Double?
    @Published var lastFullDischarge: Date?
    @Published var systemTemps: SystemTemperatureSummary = SystemTemperatureSummary(all: [], cpuAvg: nil, cpuMax: nil, gpuAvg: nil, gpuMax: nil, socMax: nil, nandMax: nil)
    private var tempReadingSamples: [[SystemTemperatureReading]] = []
    private let tempWindowSize = 5

    @Published var macForecast: HealthForecast?
    @Published var iosForecasts: [String: HealthForecast] = [:]
    let menuBar = MenuBarModel()
    private var lastForecastRefresh: Date = .distantPast
    private let forecastRefreshInterval: TimeInterval = 5 * 60

    private var fastTimer: Timer?
    private var slowTimer: Timer?
    private var loggingTimer: Timer?
    private var anomalyTimer: Timer?
    private var lastLoggedMac: Date = .distantPast
    private var lastLoggedIOS: [String: Date] = [:]
    private var logInterval: TimeInterval {
        let m = SettingsModel.shared.logIntervalMin
        let clamped = min(1440, max(1, m))
        return TimeInterval(clamped) * 60
    }
    private var iosRefreshTask: Task<Void, Never>?
    private var deviceScanTask: Task<Void, Never>?
    private var lastAnomalyCheck: Date = .distantPast
    private let fastIntervalActive: TimeInterval = 5.0
    private let fastIntervalBackground: TimeInterval = 30.0
    private var occlusionObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var deactivationObserver: NSObjectProtocol?
    private var rebuildPending = false
    private var lastFastInterval: TimeInterval = 0
    private var lastSlowEnabled: Bool = false

    init() {
        refreshAll()
        rescanDevices()
        refreshForecastsIfNeeded()
        let log = Timer(timeInterval: 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.maybeLog() }
        }
        let anomaly = Timer(timeInterval: 600.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAnomalies() }
        }
        RunLoop.main.add(log, forMode: .common)
        RunLoop.main.add(anomaly, forMode: .common)
        loggingTimer = log; anomalyTimer = anomaly
        rebuildLiveTimers(active: NSApp?.isActive ?? true)

        let nc = NotificationCenter.default
        activationObserver = nc.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
        deactivationObserver = nc.addObserver(forName: NSApplication.didResignActiveNotification,
                                              object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
        occlusionObserver = nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
    }

    private func scheduleRebuild() {
        guard !rebuildPending else { return }
        rebuildPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self = self else { return }
            self.rebuildPending = false
            self.rebuildLiveTimers(active: NSApp?.isActive ?? true)
        }
    }

    deinit {
        fastTimer?.invalidate(); slowTimer?.invalidate()
        loggingTimer?.invalidate(); anomalyTimer?.invalidate()
        let nc = NotificationCenter.default
        [activationObserver, deactivationObserver, occlusionObserver]
            .compactMap { $0 }
            .forEach(nc.removeObserver)
    }

    private func anyWindowVisible() -> Bool {
        guard let app = NSApp else { return true }
        for w in app.windows where w.isVisible {
            if w.occlusionState.contains(.visible) { return true }
        }
        return false
    }

    private func rebuildLiveTimers(active: Bool) {
        let visible = anyWindowVisible()
        let fastInterval = (active && visible) ? fastIntervalActive : fastIntervalBackground
        let slowEnabled = !libimobileMissing

        if fastInterval == lastFastInterval && slowEnabled == lastSlowEnabled
            && fastTimer != nil && (slowTimer != nil) == slowEnabled {
            return
        }

        fastTimer?.invalidate(); slowTimer?.invalidate()

        let fast = Timer(timeInterval: fastInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAll() }
        }
        RunLoop.main.add(fast, forMode: .common)
        fastTimer = fast

        if slowEnabled {
            let slow = Timer(timeInterval: 10.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.rescanDevices() }
            }
            RunLoop.main.add(slow, forMode: .common)
            slowTimer = slow
        } else {
            slowTimer = nil
        }

        lastFastInterval = fastInterval
        lastSlowEnabled = slowEnabled
    }

    func checkAnomalies() {
        let threshold = SettingsModel.shared.healthAnomalyThreshold
        let calibrationOn = SettingsModel.shared.calibrationNotify
        let devicesSnapshot: [(udid: String, name: String)] = iosDevices.map { ($0.udid, $0.name) }
        let lastDischargeSnapshot = lastFullDischarge
        HistoryStore.shared.prune()
        DispatchQueue.global(qos: .utility).async {
            let macPts = HistoryStore.shared.points(deviceId: "mac",
                since: Date.now.addingTimeInterval(-30 * 86400))
            if let a = HealthAnalytics.anomaly(points: macPts, windowDays: 7,
                                               deltaThreshold: threshold) {
                DispatchQueue.main.async { Notifier.shared.anomalyAlert(deviceName: "Mac", anomaly: a) }
            }
            for d in devicesSnapshot {
                let pts = HistoryStore.shared.points(deviceId: d.udid,
                    since: Date.now.addingTimeInterval(-30 * 86400))
                if let a = HealthAnalytics.anomaly(points: pts, windowDays: 7,
                                                   deltaThreshold: threshold) {
                    DispatchQueue.main.async { Notifier.shared.anomalyAlert(deviceName: d.name, anomaly: a) }
                }
            }

            if calibrationOn, let last = lastDischargeSnapshot {
                let days = Date.now.timeIntervalSince(last) / 86400
                if days > 30 {
                    DispatchQueue.main.async { Notifier.shared.calibrationReminder(days: Int(days)) }
                }
            } else if calibrationOn, lastDischargeSnapshot == nil {
                let pts = HistoryStore.shared.points(deviceId: "mac",
                    since: Date.now.addingTimeInterval(-90 * 86400))
                if pts.count > 50 {
                    DispatchQueue.main.async { Notifier.shared.calibrationReminder(days: 30) }
                }
            }
        }
    }

    func refreshAll() {
        let mac = BatteryReader.read()
        let raw = SystemTemperatures.read()
        tempReadingSamples.append(raw)
        if tempReadingSamples.count > tempWindowSize { tempReadingSamples.removeFirst() }
        self.macSnapshot = mac
        menuBar.update(snapshot: mac)
        let newTemps = smoothedTemps()
        if !temperatureSummariesApproxEqual(systemTemps, newTemps) {
            self.systemTemps = newTemps
        }
        if let m = mac {
            Notifier.shared.evaluateMac(m)
            self.appendWattage(m)
            if !m.isCharging && m.nominalChargePercent < 5 { self.lastFullDischarge = .now }
        }

        guard iosRefreshTask == nil else { return }
        let devices = iosDevices
        iosRefreshTask = Task { @MainActor [weak self] in
            defer { Task { @MainActor [weak self] in self?.iosRefreshTask = nil } }
            let snaps = await Self.readIOSSnapshots(devices: devices)
            guard let self else { return }
            if Task.isCancelled { return }
            if self.iosSnapshots != snaps { self.iosSnapshots = snaps }
            for d in devices {
                if let s = snaps[d.udid] {
                    Notifier.shared.evaluateIOS(udid: d.udid, name: d.name, snapshot: s)
                }
            }
        }
    }

    nonisolated private static func readIOSSnapshots(devices: [IOSDevice]) async -> [String: IOSBatterySnapshot] {
        await withTaskGroup(of: (String, IOSBatterySnapshot?).self) { group in
            for d in devices {
                group.addTask { (d.udid, IOSDeviceReader.battery(for: d)) }
            }
            var out: [String: IOSBatterySnapshot] = [:]
            for await (udid, snap) in group {
                if let snap { out[udid] = snap }
            }
            return out
        }
    }

    private func smoothedTemps() -> SystemTemperatureSummary {
        return SystemTemperatures.summarize(samples: tempReadingSamples)
    }

    private func temperatureSummariesApproxEqual(_ a: SystemTemperatureSummary, _ b: SystemTemperatureSummary) -> Bool {
        func close(_ x: Double?, _ y: Double?) -> Bool {
            switch (x, y) {
            case (nil, nil): return true
            case let (l?, r?): return abs(l - r) < 0.5
            default: return false
            }
        }
        return a.all.count == b.all.count
            && close(a.cpuAvg, b.cpuAvg) && close(a.cpuMax, b.cpuMax)
            && close(a.gpuAvg, b.gpuAvg) && close(a.gpuMax, b.gpuMax)
            && close(a.socMax, b.socMax) && close(a.nandMax, b.nandMax)
    }

    private func appendWattage(_ s: BatterySnapshot) {
        macWattageHistory.append((s.timestamp, s.wattage))
        let cutoff = Date.now.addingTimeInterval(-30 * 60)
        macWattageHistory.removeAll { $0.0 < cutoff }
        let new1 = computeWattageAvg(window: 60)
        let new10 = computeWattageAvg(window: 600)
        if new1 != macWattageAvg1 { macWattageAvg1 = new1 }
        if new10 != macWattageAvg10 { macWattageAvg10 = new10 }
    }

    private func computeWattageAvg(window: TimeInterval) -> Double? {
        let cutoff = Date.now.addingTimeInterval(-window)
        var sum = 0.0
        var count = 0
        for (ts, w) in macWattageHistory where ts >= cutoff {
            sum += w
            count += 1
        }
        return count == 0 ? nil : sum / Double(count)
    }

    func macWattageMovingAvg(window: TimeInterval) -> Double? {
        computeWattageAvg(window: window)
    }

    private func maybeLog() {
        let now = Date.now
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
        refreshForecastsIfNeeded()
    }

    private func refreshForecastsIfNeeded() {
        let now = Date.now
        guard now.timeIntervalSince(lastForecastRefresh) >= forecastRefreshInterval else { return }
        lastForecastRefresh = now
        let udids = iosDevices.map(\.udid)
        Task { @MainActor [weak self] in
            let since = Date.now.addingTimeInterval(-365 * 86400)
            let macPts = await HistoryStore.shared.pointsAsync(deviceId: "mac", since: since)
            let newMacForecast = HealthAnalytics.forecast(points: macPts)
            var iosForecastsMut: [String: HealthForecast] = [:]
            for udid in udids {
                let pts = await HistoryStore.shared.pointsAsync(deviceId: udid, since: since)
                if let f = HealthAnalytics.forecast(points: pts) {
                    iosForecastsMut[udid] = f
                }
            }
            guard let self else { return }
            self.macForecast = newMacForecast
            self.iosForecasts = iosForecastsMut
        }
    }

    func rescanDevices() {
        guard deviceScanTask == nil else { return }
        deviceScanTask = Task { @MainActor [weak self] in
            defer { Task { @MainActor [weak self] in self?.deviceScanTask = nil } }
            let result = await Self.scanDevices()
            guard let self else { return }
            if Task.isCancelled { return }
            let missingChanged = self.libimobileMissing != result.missing
            self.libimobileMissing = result.missing
            if self.iosDevices != result.devs { self.iosDevices = result.devs }
            let liveUDIDs = Set(result.devs.map(\.udid))
            self.lastLoggedIOS = self.lastLoggedIOS.filter { liveUDIDs.contains($0.key) }
            self.iosSnapshots = self.iosSnapshots.filter { liveUDIDs.contains($0.key) }
            if missingChanged {
                self.rebuildLiveTimers(active: NSApp?.isActive ?? true)
            }
        }
    }

    nonisolated private static func scanDevices() async -> (missing: Bool, devs: [IOSDevice]) {
        await withCheckedContinuation { (cont: CheckedContinuation<(missing: Bool, devs: [IOSDevice]), Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let status = IOSDeviceReader.toolchain()
                switch status {
                case .ok: cont.resume(returning: (false, IOSDeviceReader.listDevices()))
                case .missing: cont.resume(returning: (true, []))
                }
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var vm: AppViewModel
    @State private var sidebarSelection: Selection? = .mac

    var body: some View {
        NavigationSplitView {
            DBSidebar(vm: vm, selection: Binding(
                get: { vm.selection },
                set: { vm.selection = $0 }
            ))
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            ZStack {
                Color.dbBg2.ignoresSafeArea()
                DBAurora().equatable()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
        }
        .background(Color.dbBg2)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var detail: some View {
        switch vm.selection {
        case .mac:
            MacDetailView(vm: vm)
        case .ios(let udid):
            if let dev = vm.iosDevices.first(where: { $0.udid == udid }) {
                IOSDetailView(device: dev,
                              snapshot: vm.iosSnapshots[udid],
                              forecast: vm.iosForecasts[udid],
                              onRefresh: { vm.refreshAll() })
            } else {
                emptyState("Device unavailable")
            }
        case .compare:
            CompareView(vm: vm)
        }
    }

    private func emptyState(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).foregroundStyle(Color.dbText3)
            Spacer()
        }
    }
}

struct DBSidebar: View {
    @ObservedObject var vm: AppViewModel
    @Binding var selection: Selection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(Color.dbAccent)
                    .font(.system(size: 16, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text("DOCTOR")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Color.dbText)
                    Text("BATTERY")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Color.dbAccent)
                }
                Spacer()
            }
            .padding(.leading, 22)
            .padding(.trailing, 16)
            .padding(.vertical, 18)

            Divider().background(Color.dbBorder)

            List(selection: $selection) {
                Section(LocalizedStringKey("DISPOSITIVI")) {
                    macRowContent(vm.macSnapshot, selected: selection == .mac)
                        .tag(Selection.mac)
                    if !vm.libimobileMissing {
                        ForEach(vm.iosDevices) { dev in
                            iosRowContent(dev: dev,
                                          snap: vm.iosSnapshots[dev.udid],
                                          selected: selection == .ios(dev.udid))
                                .tag(Selection.ios(dev.udid))
                        }
                    }
                }
                if vm.libimobileMissing {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("libimobiledevice non installato", comment: ""))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.dbWarn)
                        Text("brew install libimobiledevice")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.dbText3)
                    }
                    .listRowSeparator(.hidden)
                } else if vm.iosDevices.isEmpty {
                    Text(NSLocalizedString("Nessun dispositivo", comment: ""))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.dbText3)
                        .listRowSeparator(.hidden)
                }
                Section(LocalizedStringKey("Confronto")) {
                    compareRowContent(selected: selection == .compare)
                        .tag(Selection.compare)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .tint(Color.dbAccent)

            Divider().background(Color.dbBorder)
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color.dbText3)
                    .font(.system(size: 11))
                Text("100% local · no telemetry")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.dbText3)
                Spacer()
            }
            .padding(.leading, 22)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
        .background(Color.dbBg2)
    }

    private func macRowContent(_ snap: BatterySnapshot?, selected: Bool) -> some View {
        HStack(spacing: 10) {
            DBSquareIcon(symbol: "laptopcomputer", color: selected ? .dbAccent : .dbText2, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey("Questo Mac"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dbText)
                    .lineLimit(1)
                Text(macSubtitle(snap))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.dbText3)
                    .lineLimit(1)
            }
            Spacer()
            if let s = snap {
                Text(DBFormat.percent(s.nominalChargePercent, fraction: 0))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(selected ? Color.dbAccent : Color.dbText2)
            }
        }
        .padding(.vertical, 4)
    }

    private func compareRowContent(selected: Bool) -> some View {
        HStack(spacing: 10) {
            DBSquareIcon(symbol: "chart.line.uptrend.xyaxis", color: selected ? .dbAccent : .dbText2, size: 30)
            Text(LocalizedStringKey("Tutti i dispositivi"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dbText)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func iosRowContent(dev: IOSDevice, snap: IOSBatterySnapshot?, selected: Bool) -> some View {
        HStack(spacing: 10) {
            DBSquareIcon(symbol: dev.productType.contains("iPad") ? "ipad" : "iphone",
                         color: selected ? .dbAccent : .dbText2, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(dev.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dbText)
                    .lineLimit(1)
                Text(iosSubtitle(dev: dev, snap: snap))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(dev.unreachableReason != nil ? Color.dbWarn : Color.dbText3)
                    .lineLimit(1)
            }
            Spacer()
            if let s = snap {
                Text("\(s.chargePercent)%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(selected ? Color.dbAccent : Color.dbText2)
            }
        }
        .padding(.vertical, 4)
    }

    private func macSubtitle(_ s: BatterySnapshot?) -> String {
        if let s = s, s.cycleCount > 0 {
            return "\(SystemInfo.macChip) · \(s.cycleCount) cicli"
        }
        return SystemInfo.macChip
    }

    private func iosSubtitle(dev: IOSDevice, snap: IOSBatterySnapshot?) -> String {
        if let reason = dev.unreachableReason { return "⚠ \(reason.prefix(36))" }
        let chip = SystemInfo.iosChip(productType: dev.productType)
        let cycles = snap?.cycleCount
        switch (chip, cycles) {
        case (let c?, let n?): return "\(c) · \(n) cicli"
        case (let c?, nil): return "\(c) · \(dev.connection.rawValue)"
        case (nil, let n?): return "\(dev.productType) · \(n) cicli"
        case (nil, nil): return "\(dev.productType) · \(dev.connection.rawValue)"
        }
    }
}

struct DBHeader: View {
    let title: String
    let subtitle: String?
    let timestamp: Date?
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.dbText)
                if let s = subtitle {
                    Text(s)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dbText2)
                }
            }
            Spacer()
            if let ts = timestamp {
                HStack(spacing: 6) {
                    Circle().fill(Color.dbAccent).frame(width: 6, height: 6)
                    Text(ts, style: .time)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.dbText2)
                }
            }
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.dbText)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.dbSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.dbBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LocalizedStringKey("Aggiorna")))
        }
    }
}

struct DBHeroStat: View {
    let value: String
    let unit: String
    let label: String
    var color: Color = .dbAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.dbText3)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.dbText2)
            }
        }
    }
}

struct MacDetailView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let s = vm.macSnapshot {
                    DBHeader(title: "Questo Mac",
                             subtitle: s.deviceName,
                             timestamp: s.timestamp,
                             onRefresh: { vm.refreshAll() })
                    heroSection(s)
                    forecastSection(deviceId: "mac", label: "Mac", forecast: vm.macForecast)
                    temperaturesCard(s)
                    chargeCard(s)
                    healthCard(s)
                    powerCard(s)
                    if let a = s.adapter { adapterCard(a) }
                    infoCard(s)
                    HistoryCard(deviceId: "mac", title: "Storico Mac")
                } else {
                    Text(NSLocalizedString("Nessuna batteria rilevata", comment: ""))
                        .foregroundStyle(Color.dbText3)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func heroSection(_ s: BatterySnapshot) -> some View {
        HStack(spacing: 14) {
            DBStatCard(label: NSLocalizedString("Salute", comment: "")) {
                HStack(alignment: .center, spacing: 14) {
                    DBMiniRing(percent: s.healthPercent, size: 44, color: .dbAccent)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(DBFormat.decimal(s.healthPercent, fraction: 0))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.dbText)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("%")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.dbText2)
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.dbAccent)
                    Text("FCC \(s.maxCapacity) mAh")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.dbAccent)
                }
            }
            DBStatCard(label: NSLocalizedString("Cicli", comment: "")) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(s.cycleCount)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.dbText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Text(MacDetailView.cyclesSubtitle(forecast: vm.macForecast))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.dbAccent)
            }
            let displayTemp = vm.systemTemps.cpuAvg ?? vm.systemTemps.socMax ?? s.temperatureC
            let label = vm.systemTemps.cpuAvg != nil ? "CPU" : (vm.systemTemps.socMax != nil ? "SoC" : NSLocalizedString("Batteria", comment: ""))
            DBStatCard(label: NSLocalizedString("Temperatura", comment: "")) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(DBFormat.decimal(displayTemp, fraction: 1))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.dbText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("°C")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.dbText2)
                }
                Text("\(label) · \(displayTemp < 50 ? NSLocalizedString("Range ottimale", comment: "") : displayTemp < 70 ? NSLocalizedString("Tiepida", comment: "") : NSLocalizedString("Calda", comment: ""))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(displayTemp < 50 ? Color.dbAccent :
                                     displayTemp < 70 ? Color.dbWarn : Color.dbBad)
            }
        }
    }

    @ViewBuilder
    private func temperaturesCard(_ s: BatterySnapshot) -> some View {
        let t = vm.systemTemps
        if t.cpuMax != nil || t.gpuMax != nil || t.socMax != nil || t.nandMax != nil || !t.all.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                DBSectionHeader(title: NSLocalizedString("Temperature sistema", comment: ""), icon: "thermometer.medium")
                if let avg = t.cpuAvg, let mx = t.cpuMax {
                    DBKVRow(label: "CPU",
                            value: "avg \(DBFormat.decimal(avg, fraction: 1)) · max \(DBFormat.celsius(mx, fraction: 1))",
                            valueColor: mx < 60 ? .dbAccent : mx < 80 ? .dbWarn : .dbBad)
                }
                if let avg = t.gpuAvg, let mx = t.gpuMax {
                    DBKVRow(label: "GPU",
                            value: "avg \(DBFormat.decimal(avg, fraction: 1)) · max \(DBFormat.celsius(mx, fraction: 1))",
                            valueColor: mx < 60 ? .dbAccent : mx < 80 ? .dbWarn : .dbBad)
                }
                if let soc = t.socMax {
                    DBKVRow(label: "SoC die", value: DBFormat.celsius(soc, fraction: 1),
                            valueColor: soc < 60 ? .dbAccent : soc < 80 ? .dbWarn : .dbBad)
                }
                if let nand = t.nandMax {
                    DBKVRow(label: "NAND / SSD", value: DBFormat.celsius(nand, fraction: 1),
                            valueColor: nand < 50 ? .dbAccent : nand < 70 ? .dbWarn : .dbBad)
                }
                DBKVRow(label: NSLocalizedString("Batteria", comment: ""),
                        value: DBFormat.celsius(s.temperatureC, fraction: 1),
                        valueColor: s.temperatureC < 35 ? .dbAccent : s.temperatureC < 40 ? .dbWarn : .dbBad)
                Text(NSLocalizedString("Letture dirette dai sensori termici via IOHIDEventSystem.", comment: ""))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.dbText3)
                    .padding(.top, 4)
            }
            .dbCard()
        }
    }

    @ViewBuilder
    private func forecastSection(deviceId: String, label: String, forecast: HealthForecast?) -> some View {
        if let f = forecast {
            ForecastCard(label: label, forecast: f, deviceId: deviceId)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(NSLocalizedString("Previsione salute", comment: ""))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.dbText)
                    Spacer()
                    Text("12 mesi · regressione lineare")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.dbText3)
                }
                Text(NSLocalizedString("In raccolta dati… (uno snapshot ogni 5 minuti)", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dbText3)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            }
            .dbCard()
        }
    }

    fileprivate static func cyclesSubtitle(forecast: HealthForecast?) -> String {
        if let f = forecast, let left = f.cyclesUntilThreshold {
            if let date = f.dateAtThreshold {
                let years = date.timeIntervalSinceNow / (365.25 * 86400)
                return String(format: NSLocalizedString("%d rimasti · ~%.1f anni", comment: ""), left, years)
            }
            return "\(left) rimasti"
        }
        return NSLocalizedString("in raccolta dati…", comment: "")
    }

    private func chargeCard(_ s: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DBSectionHeader(title: NSLocalizedString("Carica", comment: ""), icon: "bolt.fill")
            DBKVRow(label: NSLocalizedString("Stato", comment: ""),
                    value: s.fullyCharged ? "Full" : s.isCharging ? "Charging" : s.isPluggedIn ? "Plugged" : "Battery",
                    valueColor: s.isCharging ? .dbAccent : .dbText)
            DBKVRow(label: NSLocalizedString("Capacità attuale", comment: ""), value: "\(s.currentCapacity) mAh")
            DBKVRow(label: NSLocalizedString("Low Power Mode", comment: ""),
                    value: s.lowPowerMode ? NSLocalizedString("Attivo", comment: "") : NSLocalizedString("Disattivato", comment: ""),
                    valueColor: s.lowPowerMode ? .dbWarn : .dbText)
            DBKVRow(label: NSLocalizedString("Optimized Charging", comment: ""),
                    value: s.optimizedChargingEngaged ? NSLocalizedString("Sì", comment: "") : NSLocalizedString("No", comment: ""))
            if s.isCharging, let t = s.timeToFullMin {
                DBKVRow(label: NSLocalizedString("Tempo a carica completa", comment: ""), value: formatMinutes(t))
            } else if !s.isCharging, let t = s.timeToEmptyMin {
                DBKVRow(label: NSLocalizedString("Tempo a esaurimento (IOKit)", comment: ""), value: formatMinutes(t))
            }
            if !s.isCharging, let avgW = vm.macWattageMovingAvg(window: 600), avgW < -1.0 {
                let hoursLeft = (Double(s.currentCapacity) * s.voltageV / 1000.0) / abs(avgW)
                if hoursLeft < 48 {
                    DBKVRow(label: NSLocalizedString("Stima ETA (10 min media)", comment: ""),
                            value: formatHoursDecimal(hoursLeft),
                            valueColor: .dbAccent2)
                }
            }
        }
        .dbCard()
    }

    private func healthCard(_ s: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DBSectionHeader(title: NSLocalizedString("Salute", comment: ""), icon: "heart.fill")
            DBKVRow(label: NSLocalizedString("Salute (raw FCC)", comment: ""),
                    value: DBFormat.percent(s.healthPercent, fraction: 1),
                    valueColor: .dbAccent)
            DBKVRow(label: NSLocalizedString("Capacità di design", comment: ""), value: "\(s.designCapacity) mAh")
            DBKVRow(label: NSLocalizedString("Capacità massima", comment: ""), value: "\(s.maxCapacity) mAh")
            DBKVRow(label: NSLocalizedString("Cicli di carica", comment: ""), value: "\(s.cycleCount)")
            if let d = s.manufactureDate { DBKVRow(label: NSLocalizedString("Data produzione", comment: ""), value: formatDate(d)) }
            if let d = s.firstUseDate { DBKVRow(label: NSLocalizedString("Primo utilizzo", comment: ""), value: formatDate(d)) }
            Text(NSLocalizedString("Valore raw dal gas-gauge IC. Può differire dal numero in Impostazioni macOS che include impedenza e cronologia throttling.", comment: ""))
                .font(.system(size: 10))
                .foregroundStyle(Color.dbText3)
                .padding(.top, 4)
        }
        .dbCard()
    }

    private func powerCard(_ s: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DBSectionHeader(title: NSLocalizedString("Energia", comment: ""), icon: "bolt.circle.fill")
            DBKVRow(label: NSLocalizedString("Voltaggio", comment: ""), value: DBFormat.volt(s.voltageV, fraction: 3), valueColor: .dbAccent2)
            DBKVRow(label: NSLocalizedString("Corrente", comment: ""), value: DBFormat.ampere(s.amperageA, fraction: 3), valueColor: .dbAccent2)
            DBKVRow(label: NSLocalizedString("Potenza istantanea", comment: ""), value: DBFormat.watt(s.wattage, fraction: 2),
                    valueColor: s.wattage > 0 ? .dbAccent : .dbText)
            if let avg1 = vm.macWattageMovingAvg(window: 60) {
                DBKVRow(label: NSLocalizedString("Potenza media 1 min", comment: ""), value: DBFormat.watt(avg1, fraction: 2))
            }
            if let avg10 = vm.macWattageMovingAvg(window: 600) {
                DBKVRow(label: NSLocalizedString("Potenza media 10 min", comment: ""), value: DBFormat.watt(avg10, fraction: 2))
            }
            DBKVRow(label: NSLocalizedString("Temperatura", comment: ""),
                    value: DBFormat.celsius(s.temperatureC, fraction: 1),
                    valueColor: s.temperatureC > 40 ? .dbWarn : .dbText)
        }
        .dbCard()
    }

    private func adapterCard(_ a: AdapterInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DBSectionHeader(title: NSLocalizedString("Alimentatore", comment: ""), icon: "powerplug.fill")
            DBKVRow(label: NSLocalizedString("Nome", comment: ""), value: a.name)
            DBKVRow(label: NSLocalizedString("Wattaggio", comment: ""), value: "\(a.watts) W", valueColor: .dbAccent2)
            DBKVRow(label: NSLocalizedString("Modello", comment: ""), value: a.model)
            DBKVRow(label: NSLocalizedString("Produttore", comment: ""), value: a.manufacturer)
            DBKVRow(label: NSLocalizedString("Numero di serie", comment: ""), value: a.serial)
            let q = AdapterDatabase.classifyMac(a)
            DBKVRow(label: NSLocalizedString("Qualità alimentatore", comment: ""),
                    value: q.localized,
                    valueColor: q == .appleOriginal ? .dbAccent : q == .mfiCertified ? .dbAccent2 : .dbWarn)
        }
        .dbCard()
    }

    private func infoCard(_ s: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DBSectionHeader(title: NSLocalizedString("Identificazione", comment: ""), icon: "info.circle.fill")
            DBKVRow(label: NSLocalizedString("Produttore", comment: ""), value: s.manufacturer)
            DBKVRow(label: NSLocalizedString("Numero di serie", comment: ""), value: s.serial)
            DBKVRow(label: NSLocalizedString("Battery installed", comment: ""),
                    value: s.batteryInstalled ? NSLocalizedString("Sì", comment: "") : NSLocalizedString("No", comment: ""))
        }
        .dbCard()
    }
}

struct IOSDetailView: View {
    let device: IOSDevice
    let snapshot: IOSBatterySnapshot?
    let forecast: HealthForecast?
    var onRefresh: () -> Void = {}
    @State private var showDiag = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                DBHeader(title: device.name,
                         subtitle: "\(device.osVersion) · \(device.connection.rawValue)",
                         timestamp: snapshot?.timestamp,
                         onRefresh: onRefresh)
                if let reason = device.unreachableReason {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.dbWarn)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Stato connessione", comment: ""))
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(Color.dbText3)
                                .textCase(.uppercase)
                            Text(reason).foregroundStyle(Color.dbText)
                            Text("UDID: \(device.udid)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.dbText3)
                        }
                        Spacer()
                    }
                    .dbCard()
                }
                if let s = snapshot {
                    iosHero(s)
                    chargeCard(s)
                    healthCard(s)
                    if s.temperatureC != nil || s.voltageV != nil || s.amperageA != nil {
                        powerCard(s)
                    }
                    if let a = s.adapter { adapterCard(a) }
                    infoCard(s)
                    HistoryCard(deviceId: device.udid, title: "Storico \(device.name)")
                    diagnosticSection(s.diagnostic)
                } else if device.unreachableReason == nil {
                    Text(NSLocalizedString("Lettura batteria non riuscita. Verifica che il dispositivo sia sbloccato e che il trust sia attivo.", comment: ""))
                        .foregroundStyle(Color.dbText3)
                        .padding(.top, 8)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func iosHero(_ s: IOSBatterySnapshot) -> some View {
        HStack(spacing: 14) {
            DBStatCard(label: NSLocalizedString("Salute", comment: "")) {
                if let h = s.healthPercent {
                    HStack(alignment: .center, spacing: 14) {
                        DBMiniRing(percent: h, size: 44, color: .dbAccent)
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(DBFormat.decimal(h, fraction: 0))
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.dbText)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text("%")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.dbText2)
                        }
                    }
                    if let m = s.nominalCapacity {
                        HStack(spacing: 5) {
                            Image(systemName: "triangle.fill").font(.system(size: 8)).foregroundStyle(Color.dbAccent)
                            Text("FCC \(m) mAh").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.dbAccent)
                        }
                    }
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("—").font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.dbText3)
                    }
                    Text("non disponibile")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.dbText3)
                }
            }
            DBStatCard(label: NSLocalizedString("Cicli", comment: "")) {
                Text(s.cycleCount.map { "\($0)" } ?? "—")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.dbText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(IOSDetailView.cyclesSubtitleIOS(forecast: forecast, currentCycles: s.cycleCount))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.dbAccent)
            }
            DBStatCard(label: NSLocalizedString("Temperatura", comment: "")) {
                if let t = s.temperatureC {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(DBFormat.decimal(t, fraction: 1))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.dbText)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("°C").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.dbText2)
                    }
                    Text(t < 35 ? NSLocalizedString("Range ottimale", comment: "") :
                         t < 40 ? NSLocalizedString("Tiepida", comment: "") : NSLocalizedString("Calda", comment: ""))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(t < 35 ? Color.dbAccent : t < 40 ? Color.dbWarn : Color.dbBad)
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(s.chargePercent)")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.dbText)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("%").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.dbText2)
                    }
                    Text(s.isCharging ? NSLocalizedString("In carica", comment: "") : NSLocalizedString("Carica", comment: ""))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.dbAccent)
                }
            }
        }
    }

    fileprivate static func cyclesSubtitleIOS(forecast: HealthForecast?, currentCycles: Int?) -> String {
        if let f = forecast, let left = f.cyclesUntilThreshold {
            if let date = f.dateAtThreshold {
                let years = date.timeIntervalSinceNow / (365.25 * 86400)
                return String(format: NSLocalizedString("%d rimasti · ~%.1f anni", comment: ""), left, years)
            }
            return "\(left) rimasti"
        }
        return currentCycles == nil
            ? NSLocalizedString("non disponibile", comment: "")
            : NSLocalizedString("in raccolta dati…", comment: "")
    }

    private func chargeCard(_ s: IOSBatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DBSectionHeader(title: NSLocalizedString("Carica", comment: ""), icon: "bolt.fill")
            DBKVRow(label: NSLocalizedString("In carica", comment: ""), value: yn(s.isCharging),
                    valueColor: s.isCharging ? .dbAccent : .dbText)
            DBKVRow(label: NSLocalizedString("Collegato", comment: ""), value: yn(s.externalConnected))
            DBKVRow(label: NSLocalizedString("Charge capable", comment: ""), value: yn(s.externalChargeCapable))
            DBKVRow(label: NSLocalizedString("Carica completa", comment: ""), value: yn(s.fullyCharged))
            DBKVRow(label: NSLocalizedString("Batteria presente", comment: ""), value: yn(s.hasBattery))
        }
        .dbCard()
    }

    @ViewBuilder
    private func healthCard(_ s: IOSBatterySnapshot) -> some View {
        if s.cycleCount != nil || s.designCapacity != nil || s.nominalCapacity != nil
            || s.absoluteCapacity != nil || s.healthPercent != nil {
            VStack(alignment: .leading, spacing: 10) {
                DBSectionHeader(title: NSLocalizedString("Salute", comment: ""), icon: "heart.fill")
                if let c = s.cycleCount { DBKVRow(label: NSLocalizedString("Cicli di carica", comment: ""), value: "\(c)") }
                if let d = s.designCapacity { DBKVRow(label: NSLocalizedString("Capacità di design", comment: ""), value: "\(d) mAh") }
                if let n = s.nominalCapacity { DBKVRow(label: NSLocalizedString("Capacità massima", comment: ""), value: "\(n) mAh") }
                if let a = s.absoluteCapacity { DBKVRow(label: NSLocalizedString("Capacità attuale", comment: ""), value: "\(a) mAh") }
                if let h = s.healthPercent { DBKVRow(label: NSLocalizedString("Salute (raw FCC)", comment: ""), value: DBFormat.percent(h, fraction: 1), valueColor: .dbAccent) }
                Text(NSLocalizedString("Valore raw dal gas-gauge IC. Può differire da Impostazioni → Batteria che include cycle count e impedenza.", comment: ""))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.dbText3)
                    .padding(.top, 4)
            }
            .dbCard()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                DBSectionHeader(title: NSLocalizedString("Salute", comment: ""), icon: "heart.fill")
                Text(NSLocalizedString("Nessun campo capacità trovato. Vedi diagnostica grezza.", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dbText3)
            }
            .dbCard()
        }
    }

    private func powerCard(_ s: IOSBatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DBSectionHeader(title: NSLocalizedString("Energia", comment: ""), icon: "bolt.circle.fill")
            if let t = s.temperatureC { DBKVRow(label: NSLocalizedString("Temperatura", comment: ""), value: DBFormat.celsius(t, fraction: 1), valueColor: t > 40 ? .dbWarn : .dbText) }
            if let v = s.voltageV { DBKVRow(label: NSLocalizedString("Voltaggio", comment: ""), value: DBFormat.volt(v, fraction: 3), valueColor: .dbAccent2) }
            if let a = s.amperageA { DBKVRow(label: NSLocalizedString("Corrente", comment: ""), value: DBFormat.ampere(a, fraction: 3), valueColor: .dbAccent2) }
        }
        .dbCard()
    }

    private func adapterCard(_ a: IOSAdapterInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DBSectionHeader(title: NSLocalizedString("Alimentatore", comment: ""), icon: "powerplug.fill")
            if let w = a.watts { DBKVRow(label: NSLocalizedString("Wattaggio", comment: ""), value: "\(w) W", valueColor: .dbAccent2) }
            if let d = a.description { DBKVRow(label: NSLocalizedString("Tipo", comment: ""), value: d) }
            if let v = a.voltageV { DBKVRow(label: NSLocalizedString("Voltaggio", comment: ""), value: DBFormat.volt(v, fraction: 2)) }
            if let c = a.currentA { DBKVRow(label: NSLocalizedString("Corrente max", comment: ""), value: DBFormat.ampere(c, fraction: 2)) }
            if let w = a.isWireless { DBKVRow(label: NSLocalizedString("Wireless", comment: ""), value: yn(w)) }
            let q = AdapterDatabase.classifyIOSAdapter(description: a.description, watts: a.watts)
            DBKVRow(label: NSLocalizedString("Qualità alimentatore", comment: ""),
                    value: q.localized,
                    valueColor: q == .appleOriginal ? .dbAccent : q == .mfiCertified ? .dbAccent2 : .dbWarn)
        }
        .dbCard()
    }

    private func infoCard(_ s: IOSBatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DBSectionHeader(title: NSLocalizedString("Identificazione", comment: ""), icon: "info.circle.fill")
            DBKVRow(label: "UDID", value: device.udid)
            DBKVRow(label: NSLocalizedString("Connessione", comment: ""), value: device.connection.rawValue)
            DBKVRow(label: NSLocalizedString("Modello", comment: ""), value: device.productType)
            DBKVRow(label: NSLocalizedString("Sistema", comment: ""), value: device.osVersion)
            DBKVRow(label: NSLocalizedString("Serial dispositivo", comment: ""), value: device.serial)
            if let s = s.serial { DBKVRow(label: NSLocalizedString("Serial batteria", comment: ""), value: s) }
            if let m = s.manufacturer { DBKVRow(label: NSLocalizedString("Produttore batteria", comment: ""), value: m) }
        }
        .dbCard()
    }

    private func diagnosticSection(_ d: IOSDiagnosticInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $showDiag) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("com.apple.mobile.battery").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.dbText2)
                    Text(d.batteryDomainRaw.isEmpty ? "(empty)" : d.batteryDomainRaw)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.dbText3)
                        .textSelection(.enabled)
                    ForEach(d.ioregAttempts) { t in
                        Text("idevicediagnostics ioregentry \(t.className)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.dbText2)
                        if !t.stderr.isEmpty {
                            Text("stderr: \(t.stderr)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.dbBad).textSelection(.enabled)
                        }
                        Text(t.stdout.isEmpty ? "(empty)" : String(t.stdout.prefix(2000)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.dbText3).textSelection(.enabled)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(NSLocalizedString("Diagnostica grezza", comment: ""))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.dbText2)
                    .textCase(.uppercase)
            }
        }
        .dbCard()
    }

    private func yn(_ b: Bool) -> String {
        b ? NSLocalizedString("Sì", comment: "") : NSLocalizedString("No", comment: "")
    }
}

struct CompareSeries: Identifiable {
    let id: String
    let label: String
    let points: [HistoryPoint]
    let forecast: HealthForecast?
}

struct CompareView: View {
    @ObservedObject var vm: AppViewModel
    @State private var range: HistoryCard.HistoryRange = .month
    @State private var data: [CompareSeries] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack {
                    DBHeader(title: NSLocalizedString("Tutti i dispositivi", comment: ""),
                             subtitle: NSLocalizedString("Confronto", comment: ""),
                             timestamp: nil,
                             onRefresh: { vm.refreshAll(); Task { await reload(devices: vm.iosDevices) } })
                }
                rangePicker
                healthChartCard
                chargeChartCard
                ForEach(data) { series in
                    if let f = series.forecast {
                        ForecastCard(label: series.label, forecast: f, points: series.points)
                    }
                }
            }
            .padding(28)
        }
        .task(id: ReloadKey(range: range, udids: vm.iosDevices.map(\.udid))) {
            await reload(devices: vm.iosDevices)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await reload(devices: vm.iosDevices)
            }
        }
    }

    private struct ReloadKey: Hashable {
        let range: HistoryCard.HistoryRange
        let udids: [String]
    }

    private var rangePicker: some View {
        HStack(spacing: 0) {
            ForEach(HistoryCard.HistoryRange.allCases) { r in
                Button(action: { range = r }) {
                    Text(r.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(range == r ? Color.dbAccent : Color.dbText2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(range == r ? Color.dbAccent.opacity(0.14) : Color.clear)
                        )
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.dbSurface)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.dbBorder, lineWidth: 1))
        )
    }

    private var healthChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DBSectionHeader(title: NSLocalizedString("Trend salute", comment: ""), icon: "heart.text.square.fill")
            chartView(plotChargeNotHealth: false, height: 220, yDomain: 60...105)
        }
        .dbCard()
    }

    private var chargeChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DBSectionHeader(title: NSLocalizedString("Carica nel tempo", comment: ""), icon: "bolt.fill")
            chartView(plotChargeNotHealth: true, height: 180, yDomain: 0...100)
        }
        .dbCard()
    }

    @ViewBuilder
    private func chartView(plotChargeNotHealth: Bool, height: CGFloat, yDomain: ClosedRange<Double>) -> some View {
        if data.isEmpty {
            Text(NSLocalizedString("In raccolta dati… (uno snapshot ogni 5 minuti)", comment: ""))
                .font(.system(size: 11))
                .foregroundStyle(Color.dbText3)
                .frame(maxWidth: .infinity, minHeight: height / 2)
        } else {
            let showSymbols = range == .week || range == .month || range == .all
            Chart {
                ForEach(data) { series in
                    ForEach(series.points, id: \.timestamp) { p in
                        if plotChargeNotHealth, let c = p.chargePercent {
                            LineMark(x: .value("t", p.timestamp), y: .value("%", c))
                                .foregroundStyle(by: .value("Device", series.label))
                                .interpolationMethod(.linear)
                                .symbol(showSymbols ? .circle : .square)
                                .symbolSize(showSymbols ? 24 : 0)
                        } else if !plotChargeNotHealth, let h = p.healthPercent {
                            LineMark(x: .value("t", p.timestamp), y: .value("%", h))
                                .foregroundStyle(by: .value("Device", series.label))
                                .interpolationMethod(.linear)
                                .symbol(showSymbols ? .circle : .square)
                                .symbolSize(showSymbols ? 24 : 0)
                        }
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .frame(height: height)
        }
    }

    private func reload(devices: [IOSDevice]) async {
        let since = Date.now.addingTimeInterval(-range.seconds)
        var out: [CompareSeries] = []
        let macPts = await HistoryStore.shared.pointsAsync(deviceId: "mac", since: since)
        if !macPts.isEmpty {
            out.append(CompareSeries(id: "mac", label: "Mac", points: macPts,
                                     forecast: HealthAnalytics.forecast(points: macPts)))
        }
        for d in devices {
            let pts = await HistoryStore.shared.pointsAsync(deviceId: d.udid, since: since)
            if !pts.isEmpty {
                out.append(CompareSeries(id: d.udid, label: d.name, points: pts,
                                         forecast: HealthAnalytics.forecast(points: pts)))
            }
        }
        data = out
    }
}

struct ForecastCard: View {
    let label: String
    let forecast: HealthForecast
    var points: [HistoryPoint] = []
    var deviceId: String? = nil

    @State private var loadedPoints: [HistoryPoint] = []

    private var displayPoints: [HistoryPoint] {
        loadedPoints.isEmpty ? points : loadedPoints
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(NSLocalizedString("Previsione salute", comment: "")) — \(label)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.dbText)
                Spacer()
                Text("12 mesi · regressione lineare")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.dbText3)
            }
            forecastChart
            HStack(spacing: 24) {
                forecastStat(label: NSLocalizedString("Salute (raw FCC)", comment: ""),
                             value: DBFormat.percent(forecast.currentHealth, fraction: 1),
                             color: .dbAccent)
                forecastStat(label: NSLocalizedString("Trend salute", comment: ""),
                             value: DBFormat.decimal(forecast.slopePerDay, fraction: 3) + " %/d",
                             color: forecast.slopePerDay < 0 ? .dbAccent2 : .dbText)
                if let d = forecast.dateAtThreshold {
                    forecastStat(label: NSLocalizedString("Salute prevista a 80 %", comment: ""),
                                 value: formatDate(d), color: .dbText)
                }
                if let c = forecast.cyclesUntilThreshold {
                    forecastStat(label: NSLocalizedString("Cicli stimati restanti", comment: ""),
                                 value: "\(c)", color: .dbAccent)
                }
            }
            HStack(spacing: 6) {
                Text("R² \(DBFormat.decimal(forecast.confidence, fraction: 2))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.dbText3)
                ProgressView(value: forecast.confidence)
                    .tint(Color.dbAccent)
            }
        }
        .dbCard()
        .task(id: deviceId) {
            guard let id = deviceId else { return }
            let since = Date.now.addingTimeInterval(-365 * 86400)
            loadedPoints = await HistoryStore.shared.pointsAsync(deviceId: id, since: since)
        }
    }

    private func forecastStat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.dbText3)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var forecastChart: some View {
        let series = displayPoints.compactMap { p -> (Date, Double)? in
            guard let h = p.healthPercent else { return nil }
            return (p.timestamp, h)
        }
        let hasMeaningfulTrend = forecast.confidence >= 0.05 && abs(forecast.slopePerDay) > 0.001
        if series.count >= 2 && hasMeaningfulTrend {
            let minY = max(0.0, (series.map(\.1).min() ?? 80) - 5)
            Chart {
                ForEach(series, id: \.0) { p in
                    AreaMark(x: .value("t", p.0), y: .value("Salute", p.1))
                        .foregroundStyle(LinearGradient(
                            colors: [Color.dbAccent.opacity(0.45), Color.dbAccent.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("t", p.0), y: .value("Salute", p.1))
                        .foregroundStyle(Color.dbAccent)
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                }
            }
            .chartYScale(domain: minY...105)
            .frame(height: 180)
        } else if series.count >= 2 {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.dbAccent)
                    .font(.system(size: 24))
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Salute ottimale", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.dbText)
                    Text(NSLocalizedString("Nessun trend di degrado rilevato — continua a monitorare nel tempo.", comment: ""))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dbText3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 80)
        } else {
            Text(NSLocalizedString("Dati insufficienti per la previsione", comment: ""))
                .font(.system(size: 11))
                .foregroundStyle(Color.dbText3)
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }
}

struct HistoryCard: View {
    let deviceId: String
    let title: String
    @State private var range: HistoryRange = .day
    @State private var chargeSeries: [HistoryPoint] = []
    @State private var healthSeries: [HistoryPoint] = []
    @State private var lastTimestamp: Date?

    enum HistoryRange: String, CaseIterable, Identifiable {
        case hour = "1h", day = "24h", week = "7g", month = "30g", all = "All"
        var id: String { rawValue }
        var seconds: TimeInterval {
            switch self {
            case .hour: 3600; case .day: 86400; case .week: 7*86400
            case .month: 30*86400; case .all: 365*86400*10
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DBSectionHeader(title: title, icon: "clock.arrow.circlepath")
                Spacer()
                HStack(spacing: 0) {
                    ForEach(HistoryRange.allCases) { r in
                        Button(action: { range = r }) {
                            Text(r.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(range == r ? Color.dbAccent : Color.dbText2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(range == r ? Color.dbAccent.opacity(0.14) : Color.clear)
                                )
                        }.buttonStyle(.plain)
                    }
                }
                Button {
                    Task {
                        if let url = await HistoryStore.shared.exportCSVAsync(deviceId: deviceId) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dbText2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocalizedStringKey("Esporta CSV")))
            }
            if chargeSeries.isEmpty && healthSeries.isEmpty {
                Text(NSLocalizedString("In raccolta dati… (uno snapshot ogni 5 minuti)", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dbText3)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                let showSymbols = range == .week || range == .month || range == .all
                HistoryChartBody(charge: chargeSeries, health: healthSeries, showSymbols: showSymbols)
                    .equatable()
                    .frame(height: 160)
            }
        }
        .dbCard()
        .task(id: range) {
            await reload()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await reload()
            }
        }
    }

    private func reload() async {
        let since = Date.now.addingTimeInterval(-range.seconds)
        let pts = await HistoryStore.shared.pointsAsync(deviceId: deviceId, since: since)
        let charge = pts.filter { $0.chargePercent != nil }
        let health = pts.filter { $0.healthPercent != nil }
        let newest = pts.last?.timestamp
        if newest != lastTimestamp || charge.count != chargeSeries.count || health.count != healthSeries.count {
            chargeSeries = charge
            healthSeries = health
            lastTimestamp = newest
        }
    }
}

struct HistoryChartBody: View, Equatable {
    let charge: [HistoryPoint]
    let health: [HistoryPoint]
    let showSymbols: Bool

    static func == (lhs: HistoryChartBody, rhs: HistoryChartBody) -> Bool {
        lhs.showSymbols == rhs.showSymbols
            && lhs.charge.count == rhs.charge.count
            && lhs.health.count == rhs.health.count
            && lhs.charge.first?.timestamp == rhs.charge.first?.timestamp
            && lhs.charge.last?.timestamp == rhs.charge.last?.timestamp
            && lhs.health.first?.timestamp == rhs.health.first?.timestamp
            && lhs.health.last?.timestamp == rhs.health.last?.timestamp
    }

    var body: some View {
        Chart {
            ForEach(charge, id: \.timestamp) { p in
                LineMark(x: .value("t", p.timestamp),
                         y: .value("%", p.chargePercent ?? 0),
                         series: .value("s", "charge"))
                    .foregroundStyle(by: .value("Serie", "Carica %"))
                    .interpolationMethod(.linear)
                    .symbol(showSymbols ? .circle : .square)
                    .symbolSize(showSymbols ? 18 : 0)
            }
            ForEach(health, id: \.timestamp) { p in
                LineMark(x: .value("t", p.timestamp),
                         y: .value("%", p.healthPercent ?? 0),
                         series: .value("s", "health"))
                    .foregroundStyle(by: .value("Serie", "Salute %"))
                    .interpolationMethod(.linear)
                    .symbol(showSymbols ? .circle : .square)
                    .symbolSize(showSymbols ? 18 : 0)
            }
        }
        .chartForegroundStyleScale([
            "Carica %": Color.dbAccent2,
            "Salute %": Color.dbAccent
        ])
        .chartYScale(domain: 0...105)
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
