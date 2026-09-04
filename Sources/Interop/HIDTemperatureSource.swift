import CShims
import Foundation

/// Apple Silicon temperature sensors via the private IOHID event system
/// (usage page 0xff00 / usage 5 = AppleVendor temperature). Private API: probe, never assume.
final class HIDTemperatureSource: SensorSource {
    let sourceName = "IOHID"
    private var client: IOHIDEventSystemClient?
    private static let eventTypeTemperature: Int64 = 15
    private static let fieldTemperatureLevel: Int32 = 15 << 16

    func probe() -> Bool {
        let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault).takeRetainedValue()
        let matching: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
        IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
        self.client = client
        return !read().isEmpty
    }

    func read() -> [SensorReading] {
        guard let client, let services = IOHIDEventSystemClientCopyServices(client) else { return [] }
        var result: [SensorReading] = []
        for index in 0..<CFArrayGetCount(services) {
            let service = unsafeBitCast(CFArrayGetValueAtIndex(services, index), to: IOHIDServiceClient.self)
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String,
                  let event = IOHIDServiceClientCopyEvent(service, Self.eventTypeTemperature, 0, 0) else { continue }
            result.append(SensorReading(id: "hid:\(name)", name: name, kind: .temperature,
                                        value: IOHIDEventGetFloatValue(event, Self.fieldTemperatureLevel)))
        }
        return result
    }
}
