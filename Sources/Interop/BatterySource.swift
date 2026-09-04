import Foundation
import IOKit

/// `AppleSmartBattery` IORegistry properties. Public registry, stable for a decade.
enum BatterySource {
    static func read() -> BatteryStatus? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        func int(_ key: String) -> Int? { dictionary[key] as? Int }
        func bool(_ key: String) -> Bool { dictionary[key] as? Bool ?? false }
        return BatteryStatus.derive(
            currentRaw: int("AppleRawCurrentCapacity"), maxRaw: int("AppleRawMaxCapacity"), designCapacity: int("DesignCapacity"),
            currentPercent: int("CurrentCapacity"), cycleCount: int("CycleCount") ?? 0,
            isCharging: bool("IsCharging"), externalConnected: bool("ExternalConnected"),
            voltageMillivolts: int("Voltage") ?? 0, amperageMilliamps: int("InstantAmperage") ?? int("Amperage") ?? 0,
            timeRemaining: int("TimeRemaining"), temperatureRaw: int("Temperature"))
    }
}
