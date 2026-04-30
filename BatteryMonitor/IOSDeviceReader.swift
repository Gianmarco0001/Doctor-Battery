import Foundation

struct IOSDevice: Identifiable, Hashable, Sendable {
    enum Connection: String, Sendable { case usb = "USB", network = "Wi-Fi" }
    var id: String { udid }
    let udid: String
    let connection: Connection
    let name: String
    let model: String
    let productType: String
    let osVersion: String
    let serial: String
    let unreachableReason: String?
}

struct IOSAdapterInfo: Sendable, Equatable {
    let watts: Int?
    let description: String?
    let voltageV: Double?
    let currentA: Double?
    let isWireless: Bool?
}

struct IOSBatterySnapshot: Sendable, Equatable {
    let timestamp: Date
    let chargePercent: Int
    let isCharging: Bool
    let externalConnected: Bool
    let externalChargeCapable: Bool
    let fullyCharged: Bool
    let hasBattery: Bool
    let cycleCount: Int?
    let designCapacity: Int?
    let nominalCapacity: Int?
    let absoluteCapacity: Int?
    let healthPercent: Double?
    let temperatureC: Double?
    let voltageV: Double?
    let amperageA: Double?
    let serial: String?
    let manufacturer: String?
    let adapter: IOSAdapterInfo?
    let diagnostic: IOSDiagnosticInfo
}

struct IOSDiagnosticInfo: Sendable, Equatable {
    let batteryDomainRaw: String
    let ioregAttempts: [IORegAttempt]
}

struct IORegAttempt: Sendable, Identifiable, Equatable {
    var id: String { className }
    let className: String
    let stdout: String
    let stderr: String
}

enum LibIMobileStatus {
    case ok(binDir: String)
    case missing
}

enum IOSDeviceReader {
    static func toolchain() -> LibIMobileStatus {
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]
        for dir in candidates {
            if FileManager.default.isExecutableFile(atPath: "\(dir)/idevice_id"),
               FileManager.default.isExecutableFile(atPath: "\(dir)/ideviceinfo") {
                return .ok(binDir: dir)
            }
        }
        return .missing
    }

    static func isValidUDID(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 64, s.first != "-" else { return false }
        for ch in s.unicodeScalars {
            let isHex = (ch.value >= 0x30 && ch.value <= 0x39)
                || (ch.value >= 0x41 && ch.value <= 0x46)
                || (ch.value >= 0x61 && ch.value <= 0x66)
            if !isHex && ch != "-" { return false }
        }
        return true
    }

    static func listDevices() -> [IOSDevice] {
        guard case .ok(let bin) = toolchain() else { return [] }
        var devices: [IOSDevice] = []
        for line in run("\(bin)/idevice_id", ["-l"]).stdout.components(separatedBy: .newlines) {
            let udid = line.trimmingCharacters(in: .whitespaces)
            if isValidUDID(udid) {
                devices.append(info(udid: udid, connection: .usb, bin: bin))
            }
        }
        for line in run("\(bin)/idevice_id", ["-n"]).stdout.components(separatedBy: .newlines) {
            let udid = line.trimmingCharacters(in: .whitespaces)
            if isValidUDID(udid), !devices.contains(where: { $0.udid == udid }) {
                devices.append(info(udid: udid, connection: .network, bin: bin))
            }
        }
        return devices
    }

    static func battery(for device: IOSDevice) -> IOSBatterySnapshot? {
        guard case .ok(let bin) = toolchain() else { return nil }
        let netFlag = device.connection == .network ? ["-n"] : []

        let domainRes = run("\(bin)/ideviceinfo",
                            ["-u", device.udid] + netFlag + ["-q", "com.apple.mobile.battery"])
        let basic = parseColonKV(domainRes.stdout)

        guard let charge = Int(basic["BatteryCurrentCapacity"] ?? "") else { return nil }
        let charging = (basic["BatteryIsCharging"] ?? "") == "true"
        let plugged = (basic["ExternalConnected"] ?? "") == "true"
        let chargeCap = (basic["ExternalChargeCapable"] ?? "") == "true"
        let full = (basic["FullyCharged"] ?? "") == "true"
        let hasBattery = (basic["HasBattery"] ?? "true") == "true"

        var cycles: Int?
        var design: Int?
        var nominal: Int?
        var absolute: Int?
        var health: Double?
        var tempC: Double?
        var voltage: Double?
        var amperage: Double?
        var serialIO: String?
        var mfg: String?
        var adapter: IOSAdapterInfo?
        var attempts: [IORegAttempt] = []

        let diagBin = "\(bin)/idevicediagnostics"
        if FileManager.default.isExecutableFile(atPath: diagBin) {
            for klass in ["AppleSmartBattery", "IOPMPowerSource", "AppleARMPMUCharger"] {
                let res = run(diagBin, ["-u", device.udid] + netFlag + ["ioregentry", klass])
                attempts.append(IORegAttempt(className: klass, stdout: res.stdout, stderr: res.stderr))
                if let dict = parsePlistXML(res.stdout) {
                    let entry = extractBatteryEntry(dict)
                    if !entry.isEmpty {
                        if let c = entry["CycleCount"] as? Int, (0...10_000).contains(c) { cycles = c }
                        if let d = (entry["DesignCapacity"] as? Int) ?? (entry["NominalChargeCapacity"] as? Int),
                           (100...50_000).contains(d) { design = d }
                        if let n = (entry["AppleRawMaxCapacity"] as? Int) ?? (entry["MaxCapacity"] as? Int),
                           (100...50_000).contains(n) { nominal = n }
                        if let a = (entry["AppleRawCurrentCapacity"] as? Int) ?? (entry["AbsoluteCapacity"] as? Int),
                           (0...50_000).contains(a) { absolute = a }
                        if let v = entry["Voltage"] as? Int, (1_000...20_000).contains(v) {
                            voltage = Double(v) / 1000.0
                        }
                        if let a = entry["Amperage"] as? Int {
                            let signed = Int(Int32(truncatingIfNeeded: a))
                            if (-30_000...30_000).contains(signed) { amperage = Double(signed) / 1000.0 }
                        }
                        if let t = entry["Temperature"] as? Int, (-5_000...12_000).contains(t) {
                            tempC = Double(t) / 100.0
                        }
                        if let s = entry["BatterySerialNumber"] as? String { serialIO = sanitizeASCII(s) }
                        if let s = entry["Serial"] as? String, serialIO == nil { serialIO = sanitizeASCII(s) }
                        if let m = entry["Manufacturer"] as? String { mfg = sanitizeASCII(m) }
                        if let ad = entry["AdapterDetails"] as? [String: Any] {
                            adapter = decodeIOSAdapter(ad)
                        }
                    }
                }
            }
            if let d = design, d > 0, let n = nominal {
                health = min(100.0, Double(n) / Double(d) * 100.0)
            }
        }

        return IOSBatterySnapshot(
            timestamp: Date(),
            chargePercent: charge,
            isCharging: charging,
            externalConnected: plugged,
            externalChargeCapable: chargeCap,
            fullyCharged: full,
            hasBattery: hasBattery,
            cycleCount: cycles,
            designCapacity: design,
            nominalCapacity: nominal,
            absoluteCapacity: absolute,
            healthPercent: health,
            temperatureC: tempC,
            voltageV: voltage,
            amperageA: amperage,
            serial: serialIO,
            manufacturer: mfg,
            adapter: adapter,
            diagnostic: IOSDiagnosticInfo(
                batteryDomainRaw: domainRes.stdout + (domainRes.stderr.isEmpty ? "" : "\n[stderr]\n\(domainRes.stderr)"),
                ioregAttempts: attempts
            )
        )
    }

    private static func decodeIOSAdapter(_ d: [String: Any]) -> IOSAdapterInfo? {
        let watts = d["Watts"] as? Int
        let desc = sanitizeASCII(d["Description"] as? String ?? "")
        let voltage = (d["AdapterVoltage"] as? Int).map { Double($0) / 1000.0 }
        let current = (d["Current"] as? Int).map { Double($0) / 1000.0 }
        let wireless = d["IsWireless"] as? Bool
        if watts == nil && (desc?.isEmpty ?? true) && voltage == nil && current == nil { return nil }
        return IOSAdapterInfo(watts: watts, description: desc, voltageV: voltage,
                              currentA: current, isWireless: wireless)
    }

    private static func sanitizeASCII(_ s: String?) -> String? {
        guard let s = s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let printable = trimmed.unicodeScalars.allSatisfy { $0.isASCII && $0.value >= 32 && $0.value < 127 }
        return printable ? trimmed : nil
    }

    private static let batterySpecificKeys: Set<String> = [
        "AppleRawMaxCapacity", "AppleRawCurrentCapacity",
        "BatterySerialNumber", "NominalChargeCapacity"
    ]
    private static let batteryGenericKeys: Set<String> = [
        "CycleCount", "DesignCapacity", "MaxCapacity",
        "AbsoluteCapacity", "Voltage", "Temperature"
    ]
    private static let maxPlistDepth = 32

    private static func extractBatteryEntry(_ dict: [String: Any], depth: Int = 0) -> [String: Any] {
        if depth > maxPlistDepth { return [:] }
        if !batterySpecificKeys.isDisjoint(with: dict.keys) { return dict }
        if let r = dict["IORegistry"] as? [String: Any] {
            let inner = extractBatteryEntry(r, depth: depth + 1)
            if !inner.isEmpty { return inner }
        }
        if let children = dict["IORegistryEntryChildren"] as? [[String: Any]] {
            for c in children {
                let r = extractBatteryEntry(c, depth: depth + 1)
                if !r.isEmpty { return r }
            }
        }
        if let arr = dict["children"] as? [[String: Any]] {
            for c in arr {
                let r = extractBatteryEntry(c, depth: depth + 1)
                if !r.isEmpty { return r }
            }
        }
        if !batteryGenericKeys.isDisjoint(with: dict.keys) { return dict }
        return [:]
    }

    private static func info(udid: String, connection: IOSDevice.Connection, bin: String) -> IOSDevice {
        let netFlag = connection == .network ? ["-n"] : []
        let res = run("\(bin)/ideviceinfo", ["-u", udid] + netFlag)
        if res.stdout.isEmpty {
            let reason = decodeError(res.stderr)
            return IOSDevice(udid: udid, connection: connection,
                             name: shortUDID(udid), model: "—", productType: "—",
                             osVersion: "—", serial: "—", unreachableReason: reason)
        }
        let kv = parseColonKV(res.stdout)
        return IOSDevice(
            udid: udid,
            connection: connection,
            name: kv["DeviceName"] ?? "iOS Device",
            model: kv["ProductType"] ?? "—",
            productType: kv["ProductType"] ?? "—",
            osVersion: "\(kv["ProductName"] ?? "iOS") \(kv["ProductVersion"] ?? "")",
            serial: kv["SerialNumber"] ?? "—",
            unreachableReason: nil
        )
    }

    private static func shortUDID(_ s: String) -> String {
        s.count > 12 ? "Device \(s.prefix(8))…" : "Device \(s)"
    }

    private static func decodeError(_ stderr: String) -> String {
        let s = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("Password protected") || s.contains("-17") {
            return NSLocalizedString("Bloccato — sblocca il dispositivo per autorizzare lockdownd", comment: "")
        }
        if s.contains("not found") {
            return NSLocalizedString("Non raggiungibile in rete (schermo spento o usbmuxd offline)", comment: "")
        }
        if s.contains("PairingDialogResponsePending") || s.contains("not paired") || s.contains("pair") {
            return NSLocalizedString("Trust non autorizzato — accetta il prompt sul dispositivo", comment: "")
        }
        return s.isEmpty ? NSLocalizedString("Lettura non riuscita", comment: "") : s
    }

    private static let minimalEnv: [String: String] = {
        let parent = ProcessInfo.processInfo.environment
        return [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
            "HOME": parent["HOME"] ?? "/var/empty",
            "LANG": "C"
        ]
    }()

    private static func run(_ path: String, _ args: [String], timeout: TimeInterval = 5.0) -> (stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.environment = minimalEnv
        let outPipe = Pipe(); let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        do { try p.run() } catch {
            return ("", "spawn error: \(error)")
        }

        let timeoutItem = DispatchWorkItem {
            if p.isRunning { p.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        timeoutItem.cancel()

        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return (out, err)
    }

    private static func parseColonKV(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in s.components(separatedBy: .newlines) {
            if let i = line.firstIndex(of: ":") {
                let k = String(line[..<i]).trimmingCharacters(in: .whitespaces)
                let v = String(line[line.index(after: i)...]).trimmingCharacters(in: .whitespaces)
                if !k.isEmpty { out[k] = v }
            }
        }
        return out
    }

    private static let maxPlistBytes = 8 * 1024 * 1024

    private static func parsePlistXML(_ s: String) -> [String: Any]? {
        guard let data = s.data(using: .utf8), !data.isEmpty else { return nil }
        guard data.count <= maxPlistBytes else { return nil }
        let obj = try? PropertyListSerialization.propertyList(from: data, format: nil)
        return obj as? [String: Any]
    }
}
