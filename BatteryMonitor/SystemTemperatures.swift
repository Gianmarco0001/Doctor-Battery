import Foundation

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: AnyObject, _ type: Int32, _ options: Int32, _ extra: Int64) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: AnyObject, _ field: Int32) -> Double

private let kHIDPage_AppleVendor: Int = 0xff00
private let kHIDUsage_AppleVendor_TemperatureSensor: Int = 0x0005
private let kIOHIDEventTypeTemperature: Int32 = 15
private let kIOHIDEventFieldTemperatureLevel: Int32 = (kIOHIDEventTypeTemperature << 16)

struct SystemTemperatureReading: Sendable {
    let name: String
    let value: Double
}

struct SystemTemperatureSummary: Sendable, Equatable {
    let all: [SystemTemperatureReading]
    let cpuAvg: Double?
    let cpuMax: Double?
    let gpuAvg: Double?
    let gpuMax: Double?
    let socMax: Double?
    let nandMax: Double?
}

extension SystemTemperatureReading: Equatable {}

enum SystemTemperatures {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedClient: AnyObject?

    private static func sharedClient() -> AnyObject? {
        lock.lock()
        defer { lock.unlock() }
        if let c = cachedClient { return c }
        guard let ref = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return nil }
        let client = ref.takeRetainedValue()
        let matching: CFDictionary = [
            "PrimaryUsagePage": kHIDPage_AppleVendor,
            "PrimaryUsage": kHIDUsage_AppleVendor_TemperatureSensor
        ] as CFDictionary
        _ = IOHIDEventSystemClientSetMatching(client, matching)
        cachedClient = client
        return client
    }

    static func summarize(samples: [[SystemTemperatureReading]]) -> SystemTemperatureSummary {
        let last = samples.last ?? []
        let flat = samples.flatMap { $0 }
        let cpu = flat.filter { isCPU($0.name) }.map(\.value)
        let gpu = flat.filter { isGPU($0.name) }.map(\.value)
        let soc = flat.filter { isSoC($0.name) }.map(\.value)
        let nand = flat.filter { isNAND($0.name) }.map(\.value)
        func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        return SystemTemperatureSummary(
            all: last,
            cpuAvg: avg(cpu),
            cpuMax: cpu.max(),
            gpuAvg: avg(gpu),
            gpuMax: gpu.max(),
            socMax: soc.max(),
            nandMax: nand.max()
        )
    }

    static func read() -> [SystemTemperatureReading] {
        guard let client = sharedClient() else { return [] }
        guard let servicesRef = IOHIDEventSystemClientCopyServices(client) else { return [] }
        let services = servicesRef.takeRetainedValue() as Array

        var readings: [SystemTemperatureReading] = []
        for svc in services {
            let service = svc as AnyObject
            let nameRef = IOHIDServiceClientCopyProperty(service, "Product" as CFString)
            guard let name = nameRef?.takeRetainedValue() as? String else { continue }
            guard let eventRef = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0) else { continue }
            let event = eventRef.takeRetainedValue()
            let value = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperatureLevel)
            if value.isFinite, value > -50, value < 200 {
                readings.append(SystemTemperatureReading(name: name, value: value))
            }
        }
        return readings
    }

    private static func isCPU(_ s: String) -> Bool {
        let l = s.lowercased()
        if isGPU(s) || isNAND(s) { return false }
        return l.contains("cpu") || l.contains("pcore") || l.contains("ecore")
            || l.contains("efficiency core") || l.contains("performance core")
            || l.contains("pacc mtr") || l.contains("eacc mtr")
            || l.hasPrefix("tc0") || l.hasPrefix("tcad") || l.hasPrefix("tcas")
    }

    private static func isGPU(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("gpu") || l.hasPrefix("tg0") || l.hasPrefix("tg1")
    }

    private static func isSoC(_ s: String) -> Bool {
        let l = s.lowercased()
        if isCPU(s) || isGPU(s) || isNAND(s) { return false }
        return l.contains("soc") || l.contains("die") || l.contains("ane")
    }

    private static func isNAND(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("nand") || l.contains("ssd")
            || l.hasPrefix("tn0") || l.hasPrefix("tns")
    }
}
