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

struct SystemTemperatureReading {
    let name: String
    let value: Double
}

struct SystemTemperatureSummary {
    let all: [SystemTemperatureReading]
    let cpuAvg: Double?
    let cpuMax: Double?
    let gpuAvg: Double?
    let gpuMax: Double?
    let socMax: Double?
    let nandMax: Double?
}

enum SystemTemperatures {
    static func read() -> SystemTemperatureSummary {
        guard let clientRef = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
            return SystemTemperatureSummary(all: [], cpuAvg: nil, cpuMax: nil, gpuAvg: nil, gpuMax: nil, socMax: nil, nandMax: nil)
        }
        let client = clientRef.takeRetainedValue()
        let matching: CFDictionary = [
            "PrimaryUsagePage": kHIDPage_AppleVendor,
            "PrimaryUsage": kHIDUsage_AppleVendor_TemperatureSensor
        ] as CFDictionary
        _ = IOHIDEventSystemClientSetMatching(client, matching)
        guard let servicesRef = IOHIDEventSystemClientCopyServices(client) else {
            return SystemTemperatureSummary(all: [], cpuAvg: nil, cpuMax: nil, gpuAvg: nil, gpuMax: nil, socMax: nil, nandMax: nil)
        }
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

        let cpuVals = readings.filter { isCPU($0.name) }.map(\.value)
        let gpuVals = readings.filter { isGPU($0.name) }.map(\.value)
        let socVals = readings.filter { isSoC($0.name) }.map(\.value)
        let nandVals = readings.filter { isNAND($0.name) }.map(\.value)
        return SystemTemperatureSummary(
            all: readings,
            cpuAvg: cpuVals.isEmpty ? nil : cpuVals.reduce(0, +) / Double(cpuVals.count),
            cpuMax: cpuVals.max(),
            gpuAvg: gpuVals.isEmpty ? nil : gpuVals.reduce(0, +) / Double(gpuVals.count),
            gpuMax: gpuVals.max(),
            socMax: socVals.max(),
            nandMax: nandVals.max())
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
