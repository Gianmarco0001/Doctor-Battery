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
    private var anomalyTimer: Timer?
    private var lastLoggedMac: Date = .distantPast
    private var lastLoggedIOS: [String: Date] = [:]
    private let logInterval: TimeInterval = 5 * 60
    private let iosQueue = DispatchQueue(label: "doctorbattery.ios", qos: .userInitiated)
    private var iosRefreshInFlight = false
    private var deviceScanInFlight = false
    private var lastAnomalyCheck: Date = .distantPast

    init() {
        refreshAll()
        rescanDevices()
        let fast = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
        let slow = Timer(timeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.rescanDevices()
        }
        let log = Timer(timeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.maybeLog()
        }
        let anomaly = Timer(timeInterval: 600.0, repeats: true) { [weak self] _ in
            self?.checkAnomalies()
        }
        RunLoop.main.add(fast, forMode: .common)
        RunLoop.main.add(slow, forMode: .common)
        RunLoop.main.add(log, forMode: .common)
        RunLoop.main.add(anomaly, forMode: .common)
        fastTimer = fast; slowTimer = slow; loggingTimer = log; anomalyTimer = anomaly
    }

    deinit {
        fastTimer?.invalidate(); slowTimer?.invalidate()
        loggingTimer?.invalidate(); anomalyTimer?.invalidate()
    }

    func checkAnomalies() {
        let threshold = SettingsModel.shared.healthAnomalyThreshold
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let macPts = HistoryStore.shared.points(deviceId: "mac",
                since: Date().addingTimeInterval(-30 * 86400))
            if let a = HealthAnalytics.anomaly(points: macPts, windowDays: 7,
                                               deltaThreshold: threshold) {
                DispatchQueue.main.async { Notifier.shared.anomalyAlert(deviceName: "Mac", anomaly: a) }
            }
            for d in self.iosDevices {
                let pts = HistoryStore.shared.points(deviceId: d.udid,
                    since: Date().addingTimeInterval(-30 * 86400))
                if let a = HealthAnalytics.anomaly(points: pts, windowDays: 7,
                                                   deltaThreshold: threshold) {
                    DispatchQueue.main.async { Notifier.shared.anomalyAlert(deviceName: d.name, anomaly: a) }
                }
            }

            if SettingsModel.shared.calibrationNotify, let last = self.lastFullDischarge {
                let days = Date().timeIntervalSince(last) / 86400
                if days > 30 {
                    DispatchQueue.main.async { Notifier.shared.calibrationReminder(days: Int(days)) }
                }
            } else if SettingsModel.shared.calibrationNotify, self.lastFullDischarge == nil {
                let macPts = HistoryStore.shared.points(deviceId: "mac",
                    since: Date().addingTimeInterval(-90 * 86400))
                if macPts.count > 50 {
                    DispatchQueue.main.async { Notifier.shared.calibrationReminder(days: 30) }
                }
            }
        }
    }

    func refreshAll() {
        let mac = BatteryReader.read()
        self.macSnapshot = mac
        if let m = mac {
            Notifier.shared.evaluateMac(m)
            self.appendWattage(m)
            if !m.isCharging && m.nominalChargePercent < 5 { self.lastFullDischarge = Date() }
        }

        guard !iosRefreshInFlight else { return }
        iosRefreshInFlight = true
        let devices = iosDevices
        iosQueue.async { [weak self] in
            var iosSnaps: [String: IOSBatterySnapshot] = [:]
            for d in devices {
                if let s = IOSDeviceReader.battery(for: d) { iosSnaps[d.udid] = s }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.iosSnapshots = iosSnaps
                for d in devices {
                    if let s = iosSnaps[d.udid] {
                        Notifier.shared.evaluateIOS(udid: d.udid, name: d.name, snapshot: s)
                    }
                }
                self.iosRefreshInFlight = false
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
        guard !deviceScanInFlight else { return }
        deviceScanInFlight = true
        iosQueue.async { [weak self] in
            let status = IOSDeviceReader.toolchain()
            let missing: Bool
            let devs: [IOSDevice]
            switch status {
            case .ok: missing = false; devs = IOSDeviceReader.listDevices()
            case .missing: missing = true; devs = []
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.libimobileMissing = missing
                if self.iosDevices != devs { self.iosDevices = devs }
                self.deviceScanInFlight = false
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        HStack(spacing: 0) {
            DBSidebar(vm: vm)
                .frame(width: 240)
            Divider().background(Color.dbBorder)
            ZStack {
                Color.dbBg
                DBAurora()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
        }
        .background(Color.dbBg)
        .preferredColorScheme(.dark)
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    sectionHeader("DISPOSITIVI")
                    macRow(vm.macSnapshot, selected: vm.selection == .mac) {
                        vm.selection = .mac
                    }
                    if !vm.libimobileMissing {
                        ForEach(vm.iosDevices) { dev in
                            iosItem(dev: dev,
                                    snap: vm.iosSnapshots[dev.udid],
                                    selected: vm.selection == .ios(dev.udid)) {
                                vm.selection = .ios(dev.udid)
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
                        .padding(.horizontal, 24)
                    } else if vm.iosDevices.isEmpty {
                        Text(NSLocalizedString("Nessun dispositivo", comment: ""))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.dbText3)
                            .padding(.horizontal, 24)
                    }

                    sectionHeader(NSLocalizedString("Confronto", comment: "").uppercased())
                    compareRow(selected: vm.selection == .compare) {
                        vm.selection = .compare
                    }
                }
                .padding(.vertical, 14)
            }

            Spacer(minLength: 0)
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Color.dbText3)
            .padding(.leading, 24)
            .padding(.trailing, 16)
    }

    private func macRow(_ snap: BatterySnapshot?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                DBSquareIcon(symbol: "laptopcomputer", color: selected ? .dbAccent : .dbText2, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("Questo Mac", comment: ""))
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
                    Text(String(format: "%.0f%%", s.nominalChargePercent))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(selected ? Color.dbAccent : Color.dbText2)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.dbAccent.opacity(0.10) : Color.clear)
        )
        .padding(.leading, 14)
        .padding(.trailing, 12)
    }

    private func compareRow(selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                DBSquareIcon(symbol: "chart.line.uptrend.xyaxis", color: selected ? .dbAccent : .dbText2, size: 30)
                Text(NSLocalizedString("Tutti i dispositivi", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dbText)
                    .lineLimit(1)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.dbAccent.opacity(0.10) : Color.clear)
        )
        .padding(.leading, 14)
        .padding(.trailing, 12)
    }

    private func iosItem(dev: IOSDevice, snap: IOSBatterySnapshot?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.dbAccent.opacity(0.10) : Color.clear)
        )
        .padding(.leading, 14)
        .padding(.trailing, 12)
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
                        Text(String(format: "%.0f", s.healthPercent))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.dbText)
                            .monospacedDigit()
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
                }
                Text(cyclesSubtitle(deviceId: "mac", currentCycles: s.cycleCount))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.dbAccent)
            }
            DBStatCard(label: NSLocalizedString("Temperatura", comment: "")) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", s.temperatureC))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.dbText)
                        .monospacedDigit()
                    Text("°C")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.dbText2)
                }
                Text(s.temperatureC < 35 ? NSLocalizedString("Range ottimale", comment: "") :
                     s.temperatureC < 40 ? "Tiepida" : "Calda")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(s.temperatureC < 35 ? Color.dbAccent :
                                     s.temperatureC < 40 ? Color.dbWarn : Color.dbBad)
            }
        }
    }

    private func cyclesSubtitle(deviceId: String, currentCycles: Int) -> String {
        let pts = HistoryStore.shared.points(deviceId: deviceId,
                                             since: Date().addingTimeInterval(-365 * 86400))
        if let f = HealthAnalytics.forecast(points: pts), let left = f.cyclesUntilThreshold {
            if let date = f.dateAtThreshold {
                let years = date.timeIntervalSinceNow / (365.25 * 86400)
                return String(format: "%d rimasti · ~%.1f anni", left, years)
            }
            return "\(left) rimasti"
        }
        return "in raccolta dati…"
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
            if !s.isCharging, let avgW = vm.macWattageMovingAvg(window: 600), avgW < -0.1 {
                let hoursLeft = (Double(s.currentCapacity) * s.voltageV / 1000.0) / abs(avgW)
                DBKVRow(label: NSLocalizedString("Stima ETA (10 min media)", comment: ""), value: formatHoursDecimal(hoursLeft), valueColor: .dbAccent2)
            }
        }
        .dbCard()
    }

    private func healthCard(_ s: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DBSectionHeader(title: NSLocalizedString("Salute", comment: ""), icon: "heart.fill")
            DBKVRow(label: NSLocalizedString("Salute (raw FCC)", comment: ""),
                    value: String(format: "%.1f %%", s.healthPercent),
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
            DBKVRow(label: NSLocalizedString("Voltaggio", comment: ""), value: String(format: "%.3f V", s.voltageV), valueColor: .dbAccent2)
            DBKVRow(label: NSLocalizedString("Corrente", comment: ""), value: String(format: "%.3f A", s.amperageA), valueColor: .dbAccent2)
            DBKVRow(label: NSLocalizedString("Potenza istantanea", comment: ""), value: String(format: "%.2f W", s.wattage),
                    valueColor: s.wattage > 0 ? .dbAccent : .dbText)
            if let avg1 = vm.macWattageMovingAvg(window: 60) {
                DBKVRow(label: NSLocalizedString("Potenza media 1 min", comment: ""), value: String(format: "%.2f W", avg1))
            }
            if let avg10 = vm.macWattageMovingAvg(window: 600) {
                DBKVRow(label: NSLocalizedString("Potenza media 10 min", comment: ""), value: String(format: "%.2f W", avg10))
            }
            DBKVRow(label: NSLocalizedString("Temperatura", comment: ""),
                    value: String(format: "%.1f °C", s.temperatureC),
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
    @State private var showDiag = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                DBHeader(title: device.name,
                         subtitle: "\(device.osVersion) · \(device.connection.rawValue)",
                         timestamp: snapshot?.timestamp,
                         onRefresh: { })
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
                            Text(String(format: "%.0f", h))
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.dbText)
                                .monospacedDigit()
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
                Text(cyclesSubtitleIOS(udid: device.udid, currentCycles: s.cycleCount))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.dbAccent)
            }
            DBStatCard(label: NSLocalizedString("Temperatura", comment: "")) {
                if let t = s.temperatureC {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", t))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.dbText)
                            .monospacedDigit()
                        Text("°C").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.dbText2)
                    }
                    Text(t < 35 ? NSLocalizedString("Range ottimale", comment: "") :
                         t < 40 ? "Tiepida" : "Calda")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(t < 35 ? Color.dbAccent : t < 40 ? Color.dbWarn : Color.dbBad)
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(s.chargePercent)")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.dbText)
                            .monospacedDigit()
                        Text("%").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.dbText2)
                    }
                    Text(s.isCharging ? NSLocalizedString("In carica", comment: "") : NSLocalizedString("Carica", comment: ""))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.dbAccent)
                }
            }
        }
    }

    private func cyclesSubtitleIOS(udid: String, currentCycles: Int?) -> String {
        let pts = HistoryStore.shared.points(deviceId: udid, since: Date().addingTimeInterval(-365 * 86400))
        if let f = HealthAnalytics.forecast(points: pts), let left = f.cyclesUntilThreshold {
            if let date = f.dateAtThreshold {
                let years = date.timeIntervalSinceNow / (365.25 * 86400)
                return String(format: "%d rimasti · ~%.1f anni", left, years)
            }
            return "\(left) rimasti"
        }
        return currentCycles == nil ? "non disponibile" : "in raccolta dati…"
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
                if let h = s.healthPercent { DBKVRow(label: NSLocalizedString("Salute (raw FCC)", comment: ""), value: String(format: "%.1f %%", h), valueColor: .dbAccent) }
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
            if let t = s.temperatureC { DBKVRow(label: NSLocalizedString("Temperatura", comment: ""), value: String(format: "%.1f °C", t), valueColor: t > 40 ? .dbWarn : .dbText) }
            if let v = s.voltageV { DBKVRow(label: NSLocalizedString("Voltaggio", comment: ""), value: String(format: "%.3f V", v), valueColor: .dbAccent2) }
            if let a = s.amperageA { DBKVRow(label: NSLocalizedString("Corrente", comment: ""), value: String(format: "%.3f A", a), valueColor: .dbAccent2) }
        }
        .dbCard()
    }

    private func adapterCard(_ a: IOSAdapterInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DBSectionHeader(title: NSLocalizedString("Alimentatore", comment: ""), icon: "powerplug.fill")
            if let w = a.watts { DBKVRow(label: NSLocalizedString("Wattaggio", comment: ""), value: "\(w) W", valueColor: .dbAccent2) }
            if let d = a.description { DBKVRow(label: NSLocalizedString("Tipo", comment: ""), value: d) }
            if let v = a.voltageV { DBKVRow(label: NSLocalizedString("Voltaggio", comment: ""), value: String(format: "%.2f V", v)) }
            if let c = a.currentA { DBKVRow(label: NSLocalizedString("Corrente max", comment: ""), value: String(format: "%.2f A", c)) }
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
                    ForEach(Array(d.ioregAttempts.enumerated()), id: \.offset) { _, t in
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

struct CompareView: View {
    @ObservedObject var vm: AppViewModel
    @State private var range: HistoryCard.HistoryRange = .month
    @State private var data: [(deviceId: String, label: String, points: [HistoryPoint])] = []
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack {
                    DBHeader(title: NSLocalizedString("Tutti i dispositivi", comment: ""),
                             subtitle: NSLocalizedString("Confronto", comment: ""),
                             timestamp: nil,
                             onRefresh: { vm.refreshAll(); reload() })
                }
                rangePicker
                healthChartCard
                chargeChartCard
                ForEach(data, id: \.deviceId) { series in
                    if let f = HealthAnalytics.forecast(points: series.points) {
                        ForecastCard(label: series.label, forecast: f, points: series.points)
                    }
                }
            }
            .padding(28)
        }
        .onAppear { reload() }
        .onChange(of: range) { _ in reload() }
        .onChange(of: vm.iosDevices) { _ in reload() }
        .onReceive(tick) { _ in reload() }
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
            chartView(plotChargeNotHealth: false, height: 220, yDomain: 60...100)
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
            Chart {
                ForEach(data, id: \.deviceId) { series in
                    ForEach(series.points, id: \.timestamp) { p in
                        if plotChargeNotHealth, let c = p.chargePercent {
                            LineMark(x: .value("t", p.timestamp), y: .value("%", c))
                                .foregroundStyle(by: .value("Device", series.label))
                                .interpolationMethod(.linear)
                        } else if !plotChargeNotHealth, let h = p.healthPercent {
                            LineMark(x: .value("t", p.timestamp), y: .value("%", h))
                                .foregroundStyle(by: .value("Device", series.label))
                                .interpolationMethod(.linear)
                        }
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .frame(height: height)
        }
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
    let points: [HistoryPoint]

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
                             value: String(format: "%.1f %%", forecast.currentHealth),
                             color: .dbAccent)
                forecastStat(label: NSLocalizedString("Trend salute", comment: ""),
                             value: String(format: "%.3f %%/d", forecast.slopePerDay),
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
                Text("R² \(String(format: "%.2f", forecast.confidence))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.dbText3)
                ProgressView(value: forecast.confidence)
                    .tint(Color.dbAccent)
            }
        }
        .dbCard()
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
        let series = points.compactMap { p -> (Date, Double)? in
            guard let h = p.healthPercent else { return nil }
            return (p.timestamp, h)
        }
        if series.count >= 2 {
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
            .chartYScale(domain: max(60, forecast.currentHealth - 10)...100)
            .frame(height: 180)
        } else {
            Text(NSLocalizedString("Dati insufficienti per la previsione", comment: ""))
                .font(.system(size: 11))
                .foregroundStyle(Color.dbText3)
                .frame(maxWidth: .infinity, minHeight: 100)
        }
    }
}

struct HistoryCard: View {
    let deviceId: String
    let title: String
    @State private var range: HistoryRange = .day
    @State private var points: [HistoryPoint] = []
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

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
                        Button(action: { range = r; reload() }) {
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
                    if let url = HistoryStore.shared.exportCSV(deviceId: deviceId) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dbText2)
                }.buttonStyle(.plain)
            }
            if points.isEmpty {
                Text(NSLocalizedString("In raccolta dati… (uno snapshot ogni 5 minuti)", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dbText3)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart {
                    ForEach(points.filter { $0.chargePercent != nil }, id: \.timestamp) { p in
                        LineMark(x: .value("t", p.timestamp),
                                 y: .value("%", p.chargePercent ?? 0),
                                 series: .value("s", "charge"))
                            .foregroundStyle(by: .value("Serie", "Carica %"))
                            .interpolationMethod(.linear)
                    }
                    ForEach(points.filter { $0.healthPercent != nil }, id: \.timestamp) { p in
                        LineMark(x: .value("t", p.timestamp),
                                 y: .value("%", p.healthPercent ?? 0),
                                 series: .value("s", "health"))
                            .foregroundStyle(by: .value("Serie", "Salute %"))
                            .interpolationMethod(.linear)
                    }
                }
                .chartForegroundStyleScale([
                    "Carica %": Color.dbAccent2,
                    "Salute %": Color.dbAccent
                ])
                .chartYScale(domain: 0...100)
                .frame(height: 160)
            }
        }
        .dbCard()
        .onAppear { reload() }
        .onReceive(tick) { _ in reload() }
    }

    private func reload() {
        let since = Date().addingTimeInterval(-range.seconds)
        let pts = HistoryStore.shared.points(deviceId: deviceId, since: since)
        if pts.count != points.count { points = pts }
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
