import Foundation

struct IOSDevice: Identifiable, Hashable {
    enum Connection: String { case usb = "USB", network = "Wi-Fi" }
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

struct IOSAdapterInfo {
    let watts: Int?
    let description: String?
    let voltageV: Double?
    let currentA: Double?
    let isWireless: Bool?
}

struct IOSBatterySnapshot {
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

struct IOSDiagnosticInfo {
    let batteryDomainRaw: String
    let ioregAttempts: [(className: String, stdout: String, stderr: String)]
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

    static func listDevices() -> [IOSDevice] {
        guard case .ok(let bin) = toolchain() else { return [] }
        var devices: [IOSDevice] = []
        for line in run("\(bin)/idevice_id", ["-l"]).stdout.components(separatedBy: .newlines) {
            let udid = line.trimmingCharacters(in: .whitespaces)
            if !udid.isEmpty {
                devices.append(info(udid: udid, connection: .usb, bin: bin))
            }
        }
        for line in run("\(bin)/idevice_id", ["-n"]).stdout.components(separatedBy: .newlines) {
            let udid = line.trimmingCharacters(in: .whitespaces)
            if !udid.isEmpty, !devices.contains(where: { $0.udid == udid }) {
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
        var attempts: [(String, String, String)] = []

        let diagBin = "\(bin)/idevicediagnostics"
        if FileManager.default.isExecutableFile(atPath: diagBin) {
            for klass in ["AppleSmartBattery", "IOPMPowerSource", "AppleARMPMUCharger"] {
                let res = run(diagBin, ["-u", device.udid] + netFlag + ["ioregentry", klass])
                attempts.append((klass, res.stdout, res.stderr))
                if let dict = parsePlistXML(res.stdout) {
                    let entry = extractBatteryEntry(dict)
                    if !entry.isEmpty {
                        cycles = (entry["CycleCount"] as? Int) ?? cycles
                        design = (entry["DesignCapacity"] as? Int)
                            ?? (entry["NominalChargeCapacity"] as? Int) ?? design
                        nominal = (entry["AppleRawMaxCapacity"] as? Int)
                            ?? (entry["MaxCapacity"] as? Int) ?? nominal
                        absolute = (entry["AppleRawCurrentCapacity"] as? Int)
                            ?? (entry["AbsoluteCapacity"] as? Int) ?? absolute
                        if let v = entry["Voltage"] as? Int { voltage = Double(v) / 1000.0 }
                        if let a = entry["Amperage"] as? Int {
                            amperage = Double(Int32(truncatingIfNeeded: a)) / 1000.0
                        }
                        if let t = entry["Temperature"] as? Int { tempC = Double(t) / 100.0 }
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
                health = Double(n) / Double(d) * 100.0
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

    private static func extractBatteryEntry(_ dict: [String: Any]) -> [String: Any] {
        let interesting = ["CycleCount", "DesignCapacity", "NominalChargeCapacity",
                           "AppleRawMaxCapacity", "MaxCapacity",
                           "AppleRawCurrentCapacity", "AbsoluteCapacity",
                           "Voltage", "Temperature", "BatterySerialNumber"]
        if interesting.contains(where: { dict[$0] != nil }) { return dict }
        if let r = dict["IORegistry"] as? [String: Any] {
            let inner = extractBatteryEntry(r)
            if !inner.isEmpty { return inner }
        }
        if let children = dict["IORegistryEntryChildren"] as? [[String: Any]] {
            for c in children {
                let r = extractBatteryEntry(c)
                if !r.isEmpty { return r }
            }
        }
        if let arr = dict["children"] as? [[String: Any]] {
            for c in arr {
                let r = extractBatteryEntry(c)
                if !r.isEmpty { return r }
            }
        }
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
            return "Bloccato — sblocca il dispositivo per autorizzare lockdownd"
        }
        if s.contains("not found") {
            return "Non raggiungibile in rete (schermo spento o usbmuxd offline)"
        }
        if s.contains("PairingDialogResponsePending") || s.contains("not paired") || s.contains("pair") {
            return "Trust non autorizzato — accetta il prompt sul dispositivo"
        }
        return s.isEmpty ? "Lettura non riuscita" : s
    }

    private static func run(_ path: String, _ args: [String], timeout: TimeInterval = 5.0) -> (stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let outPipe = Pipe(); let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        var outData = Data()
        var errData = Data()
        let outQueue = DispatchQueue(label: "proc.out")
        let errQueue = DispatchQueue(label: "proc.err")
        outPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if !d.isEmpty { outQueue.sync { outData.append(d) } }
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if !d.isEmpty { errQueue.sync { errData.append(d) } }
        }

        do { try p.run() } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return ("", "spawn error: \(error)")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate() }
        p.waitUntilExit()

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        let out = outQueue.sync { String(data: outData, encoding: .utf8) ?? "" }
        let err = errQueue.sync { String(data: errData, encoding: .utf8) ?? "" }
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

    private static func parsePlistXML(_ s: String) -> [String: Any]? {
        guard let data = s.data(using: .utf8), !data.isEmpty else { return nil }
        let obj = try? PropertyListSerialization.propertyList(from: data, format: nil)
        return obj as? [String: Any]
    }
}
