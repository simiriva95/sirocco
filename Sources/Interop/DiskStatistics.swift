import IOKit

/// Whole-system disk bytes from every `IOBlockStorageDriver` (physical drives, not volumes).
enum DiskStatistics {
    static func read() -> DiskCounters? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var total = DiskCounters(bytesRead: 0, bytesWritten: 0)
        var found = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let statistics = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            found = true
            total.bytesRead &+= (statistics["Bytes (Read)"] as? UInt64) ?? 0
            total.bytesWritten &+= (statistics["Bytes (Write)"] as? UInt64) ?? 0
        }
        return found ? total : nil
    }
}
