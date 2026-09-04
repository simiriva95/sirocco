import Foundation

/// Per-interface byte counters from `getifaddrs` (`AF_LINK` entries carry `if_data`).
/// Per-process network is not available through public API; see README.
enum NetworkCounters {
    static func read() -> [InterfaceCounters] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result: [InterfaceCounters] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard Int32(entry.pointee.ifa_addr.pointee.sa_family) == AF_LINK, let raw = entry.pointee.ifa_data else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            result.append(InterfaceCounters(name: name, received: UInt64(data.ifi_ibytes), sent: UInt64(data.ifi_obytes)))
        }
        return result
    }
}
