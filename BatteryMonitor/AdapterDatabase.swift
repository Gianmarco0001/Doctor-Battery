import Foundation

enum AdapterQuality: String {
    case appleOriginal
    case mfiCertified
    case generic
    case unknown
}

enum AdapterDatabase {
    private static let appleFamilyCodes: Set<Int> = [
        0xE000_4203, 0xE000_4204, 0xE000_4205, 0xE000_4206,
        0xE000_4207, 0xE000_4208, 0xE000_4209, 0xE000_420A,
        0xE000_4101, 0xE000_4102, 0xE000_4103,
        Int(Int32(bitPattern: 0xE000_4100)),
        Int(Int32(bitPattern: 0xE000_4200)),
        Int(Int32(bitPattern: 0xE000_4300))
    ]

    private static let mfiFamilyCodes: Set<Int> = [
        0xE000_0080, 0xE000_0081, 0xE000_0082
    ]

    private static let knownAppleManufacturers: Set<String> = [
        "Apple Inc.", "Apple", "APPLE COMPUTER, INC."
    ]

    static func classifyMac(_ a: AdapterInfo) -> AdapterQuality {
        if knownAppleManufacturers.contains(a.manufacturer) { return .appleOriginal }
        if appleFamilyCodes.contains(a.familyCode) { return .appleOriginal }
        if mfiFamilyCodes.contains(a.familyCode) { return .mfiCertified }
        if a.manufacturer == "—" && a.name.isEmpty { return .unknown }
        return .generic
    }

    static func classifyIOSAdapter(description: String?, watts: Int?) -> AdapterQuality {
        guard let d = description?.lowercased() else { return .unknown }
        if d.contains("apple") { return .appleOriginal }
        if d.contains("magsafe") { return .appleOriginal }
        if d.contains("usb-pd") || d.contains("pd charger") {
            return watts != nil ? .mfiCertified : .generic
        }
        if d.contains("usb host") { return .generic }
        return .generic
    }
}

extension AdapterQuality {
    var localized: String {
        switch self {
        case .appleOriginal: return NSLocalizedString("Apple originale", comment: "")
        case .mfiCertified: return NSLocalizedString("MFi certificato", comment: "")
        case .generic: return NSLocalizedString("Generico", comment: "")
        case .unknown: return "—"
        }
    }
}
