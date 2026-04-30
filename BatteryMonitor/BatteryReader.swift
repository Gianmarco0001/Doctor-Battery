import Foundation
import IOKit
import IOKit.ps

struct AdapterInfo {
    let watts: Int
    let name: String
    let manufacturer: String
    let serial: String
    let model: String
    let familyCode: Int
}

struct BatterySnapshot {
    let timestamp: Date
    let cycleCount: Int
    let designCapacity: Int
    let maxCapacity: Int
    let currentCapacity: Int
    let nominalChargePercent: Double
    let healthPercent: Double
    let temperatureC: Double
    let voltageV: Double
    let amperageA: Double
    let wattage: Double
    let isCharging: Bool
    let isPluggedIn: Bool
    let fullyCharged: Bool
    let batteryInstalled: Bool
    let optimizedChargingEngaged: Bool
    let lowPowerMode: Bool
    let timeToFullMin: Int?
    let timeToEmptyMin: Int?
    let serial: String
    let deviceName: String
    let manufacturer: String
    let manufactureDate: Date?
    let firstUseDate: Date?
    let adapter: AdapterInfo?
}

enum BatteryReader {
    static func read() -> BatterySnapshot? {
        guard let service = batteryService() else { return nil }
        defer { IOObjectRelease(service) }

        let props = properties(of: service)

        let design = props["DesignCapacity"] as? Int ?? 0
        let maxCap = (props["AppleRawMaxCapacity"] as? Int)
            ?? (props["MaxCapacity"] as? Int) ?? 0
        let curCap = (props["AppleRawCurrentCapacity"] as? Int)
            ?? (props["CurrentCapacity"] as? Int) ?? 0
        let userCharge = props["CurrentCapacity"] as? Int ?? 0
        let cycles = props["CycleCount"] as? Int ?? 0
        let tempRaw = props["Temperature"] as? Int ?? 0
        let voltageRaw = props["Voltage"] as? Int ?? 0
        let amperageRaw = props["Amperage"] as? Int ?? 0
        let charging = props["IsCharging"] as? Bool ?? false
        let plugged = props["ExternalConnected"] as? Bool ?? false
        let fullyCharged = props["FullyCharged"] as? Bool ?? false
        let installed = props["BatteryInstalled"] as? Bool ?? true
        let optimized = (props["AppleRawAdapterDetails"] as? [String: Any])?["OptimizedBatteryChargingEngaged"] as? Bool
            ?? props["OptimizedBatteryChargingEngaged"] as? Bool
            ?? false
        let timeToFull = props["AvgTimeToFull"] as? Int
        let timeToEmpty = props["AvgTimeToEmpty"] as? Int
        let serial = props["Serial"] as? String
            ?? props["BatterySerialNumber"] as? String ?? "—"
        let deviceName = props["DeviceName"] as? String ?? "—"
        let manufacturer = props["Manufacturer"] as? String ?? "—"

        let voltageV = Double(voltageRaw) / 1000.0
        let amperageA = Double(Int32(truncatingIfNeeded: amperageRaw)) / 1000.0
        let wattage = voltageV * amperageA

        let nominal: Double = {
            if (1...100).contains(userCharge) { return Double(userCharge) }
            guard design > 0 else { return 0 }
            return min(100.0, Double(curCap) / Double(maxCap == 0 ? design : maxCap) * 100.0)
        }()
        let health = design > 0 ? min(100.0, Double(maxCap) / Double(design) * 100.0) : 0

        let mfgDate = decodeManufactureDate(props["ManufactureDate"] as? Int)
        let firstUse = decodeFirstUseDate(props)
        let adapter = decodeAdapter(props["AdapterDetails"] as? [String: Any])

        return BatterySnapshot(
            timestamp: Date(),
            cycleCount: cycles,
            designCapacity: design,
            maxCapacity: maxCap,
            currentCapacity: curCap,
            nominalChargePercent: nominal,
            healthPercent: health,
            temperatureC: Double(tempRaw) / 100.0,
            voltageV: voltageV,
            amperageA: amperageA,
            wattage: wattage,
            isCharging: charging,
            isPluggedIn: plugged,
            fullyCharged: fullyCharged,
            batteryInstalled: installed,
            optimizedChargingEngaged: optimized,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            timeToFullMin: sanitizeTime(timeToFull),
            timeToEmptyMin: sanitizeTime(timeToEmpty),
            serial: serial,
            deviceName: deviceName,
            manufacturer: manufacturer,
            manufactureDate: mfgDate,
            firstUseDate: firstUse,
            adapter: adapter
        )
    }

    private static func decodeManufactureDate(_ packed: Int?) -> Date? {
        guard let p = packed, p > 0 else { return nil }
        let day = p & 0x1F
        let month = (p >> 5) & 0x0F
        let year = ((p >> 9) & 0x7F) + 1980
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return Calendar(identifier: .gregorian).date(from: c)
    }

    private static func decodeFirstUseDate(_ props: [String: Any]) -> Date? {
        if let secs = props["BatteryData"] as? [String: Any],
           let lifetime = secs["LifetimeData"] as? [String: Any],
           let firstUse = lifetime["FirstUseTime"] as? Int, firstUse > 0 {
            return Date(timeIntervalSince1970: TimeInterval(firstUse))
        }
        return nil
    }

    private static func decodeAdapter(_ dict: [String: Any]?) -> AdapterInfo? {
        guard let d = dict, !d.isEmpty else { return nil }
        let watts = d["Watts"] as? Int ?? 0
        guard watts > 0 || (d["Name"] as? String)?.isEmpty == false else { return nil }
        return AdapterInfo(
            watts: watts,
            name: d["Name"] as? String ?? "—",
            manufacturer: d["Manufacturer"] as? String ?? "—",
            serial: d["SerialString"] as? String ?? "—",
            model: d["Model"] as? String ?? "—",
            familyCode: d["FamilyCode"] as? Int ?? 0
        )
    }

    private static func sanitizeTime(_ value: Int?) -> Int? {
        guard let v = value, v > 0, v < 60 * 24 else { return nil }
        return v
    }

    private static func batteryService() -> io_service_t? {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        return service == 0 ? nil : service
    }

    private static func properties(of service: io_service_t) -> [String: Any] {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return [:] }
        return dict
    }
}
