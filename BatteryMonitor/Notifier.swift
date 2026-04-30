import Foundation
@preconcurrency import UserNotifications

@MainActor
final class Notifier {
    static let shared = Notifier()
    private var lastFiredKey: [String: Date] = [:]
    private let cooldown: TimeInterval = 30 * 60

    nonisolated func requestAuthIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { s in
            if s.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }

    func evaluateMac(_ s: BatterySnapshot) {
        let settings = SettingsModel.shared
        let lowT = Double(settings.lowBatteryThreshold)
        let tempT = settings.temperatureThreshold
        if !s.isCharging && s.nominalChargePercent < lowT {
            fire(key: "mac.low",
                 title: NSLocalizedString("Battery low", comment: ""),
                 body: "Mac " + DBFormat.percent(s.nominalChargePercent, fraction: 0))
        }
        if s.isPluggedIn && s.nominalChargePercent >= 95 && !s.fullyCharged {
            fire(key: "mac.high",
                 title: NSLocalizedString("Charging almost complete", comment: ""),
                 body: NSLocalizedString("Consider unplugging to preserve battery health.", comment: ""))
        }
        if s.temperatureC > tempT {
            fire(key: "mac.hot",
                 title: NSLocalizedString("Battery hot", comment: ""),
                 body: DBFormat.celsius(s.temperatureC, fraction: 1))
        }
        if s.cycleCount > 0 && s.cycleCount % 50 == 0 {
            fire(key: "mac.cycles.\(s.cycleCount)",
                 title: NSLocalizedString("Cycle count milestone", comment: ""),
                 body: "\(s.cycleCount)", noCooldown: true)
        }
    }

    func evaluateIOS(udid: String, name: String, snapshot s: IOSBatterySnapshot) {
        let settings = SettingsModel.shared
        let lowT = settings.lowBatteryThreshold
        let tempT = settings.temperatureThreshold
        if !s.isCharging && s.chargePercent < lowT {
            fire(key: "ios.\(udid).low",
                 title: "\(name)",
                 body: NSLocalizedString("Battery low", comment: "") + ": \(s.chargePercent) %")
        }
        if let t = s.temperatureC, t > tempT {
            fire(key: "ios.\(udid).hot",
                 title: "\(name)",
                 body: NSLocalizedString("Battery hot", comment: "") + " " + DBFormat.celsius(t, fraction: 1))
        }
    }

    func anomalyAlert(deviceName: String, anomaly: HealthAnomaly) {
        fire(key: "anomaly.\(deviceName)",
             title: NSLocalizedString("Anomalia rilevata", comment: ""),
             body: "\(deviceName): -\(DBFormat.decimal(anomaly.deltaPercent, fraction: 1)) % / \(anomaly.windowDays)d")
    }

    func calibrationReminder(days: Int) {
        fire(key: "mac.calibration",
             title: NSLocalizedString("Calibrazione consigliata", comment: ""),
             body: NSLocalizedString("Una scarica completa + ricarica al 100% aiuta il gas-gauge a ricalibrarsi.", comment: ""))
    }

    private func fire(key: String, title: String, body: String, noCooldown: Bool = false) {
        if !noCooldown, let last = lastFiredKey[key], Date.now.timeIntervalSince(last) < cooldown { return }
        lastFiredKey[key] = .now
        if lastFiredKey.count > 200 {
            let cutoff = Date.now.addingTimeInterval(-7 * 24 * 3600)
            lastFiredKey = lastFiredKey.filter { $0.value > cutoff }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: key + "-\(Int(Date.now.timeIntervalSince1970))",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
