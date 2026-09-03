import Foundation

/// Flat, Comparable-only row for the Processes table. Groups carry their members as children.
struct ProcessRow: Identifiable, Hashable, Sendable {
    var id: Int32                 // pid (leader pid for groups)
    var name: String
    var pid: Int32
    var energyImpact: Double
    var cpuFraction: Double
    var footprintBytes: UInt64
    var threads: Int              // -1 when unknown
    var wakeupsPerSecond: Double
    var diskReadPerSecond: Double
    var diskWritePerSecond: Double
    var user: String
    var memberPIDs: [Int32]
    var children: [ProcessRow]?

    var isGroup: Bool { children != nil }

    // Sort keys quantized to what the column displays: a row only changes position when its
    // visible number changes, so live sorting stops reshuffling rows over invisible jitter.
    var sortEnergy: Double { energyImpact.rounded() }
    var sortCPU: Double { (cpuFraction * 1000).rounded() }
    var sortMemory: UInt64 { footprintBytes / 102_400 }          // 0.1 MB steps
    var sortWakeups: Double { wakeupsPerSecond.rounded() }
    var sortRead: Double { (diskReadPerSecond / 1024).rounded() }
    var sortWrite: Double { (diskWritePerSecond / 1024).rounded() }
}

extension ProcessRow {
    /// Column identifier → comparators. Names sort naturally (Finder-like), numbers by their
    /// quantized value, and everything is tie-broken by pid so ties never reshuffle.
    static func comparators(key: String, ascending: Bool) -> [KeyPathComparator<ProcessRow>] {
        let order: SortOrder = ascending ? .forward : .reverse
        let primary: KeyPathComparator<ProcessRow> = switch key {
        case "name": KeyPathComparator(\.name, comparator: .localizedStandard, order: order)
        case "pid": KeyPathComparator(\.pid, order: order)
        case "cpu": KeyPathComparator(\.sortCPU, order: order)
        case "memory": KeyPathComparator(\.sortMemory, order: order)
        case "threads": KeyPathComparator(\.threads, order: order)
        case "wakeups": KeyPathComparator(\.sortWakeups, order: order)
        case "read": KeyPathComparator(\.sortRead, order: order)
        case "write": KeyPathComparator(\.sortWrite, order: order)
        case "user": KeyPathComparator(\.user, comparator: .localizedStandard, order: order)
        default: KeyPathComparator(\.sortEnergy, order: order)
        }
        return [primary, KeyPathComparator(\.pid, order: .forward)]
    }
}

enum ProcessRowBuilder {
    /// Pure. `query` matches name or pid; a group is kept when any member matches, and shows
    /// only the matching members. Sorting is the caller's job (`sorted(using:)`).
    static func rows(groups: [ProcessGroup], query: String,
                     name: (ProcessSample) -> String, user: (UInt32) -> String) -> [ProcessRow] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        func matches(_ sample: ProcessSample) -> Bool {
            needle.isEmpty || name(sample).localizedCaseInsensitiveContains(needle)
                || sample.command.localizedCaseInsensitiveContains(needle) || String(sample.pid) == needle
        }
        func row(_ s: ProcessSample) -> ProcessRow {
            ProcessRow(id: s.pid, name: name(s), pid: s.pid, energyImpact: s.energyImpact, cpuFraction: s.cpuFraction,
                       footprintBytes: s.physFootprintBytes, threads: s.threadCount ?? -1,
                       wakeupsPerSecond: s.packageIdleWakeupsPerSecond, diskReadPerSecond: s.diskReadBytesPerSecond,
                       diskWritePerSecond: s.diskWriteBytesPerSecond, user: user(s.uid), memberPIDs: [s.pid], children: nil)
        }
        return groups.compactMap { group in
            let visible = group.members.filter(matches)
            guard !visible.isEmpty else { return nil }
            if group.count == 1 { return row(group.members[0]) }
            let children = visible.map(row)
            return ProcessRow(
                id: group.leader.pid, name: name(group.leader), pid: group.leader.pid,
                energyImpact: group.energyImpact, cpuFraction: group.cpuFraction, footprintBytes: group.physFootprintBytes,
                threads: group.members.allSatisfy { $0.threadCount != nil } ? group.members.reduce(0) { $0 + ($1.threadCount ?? 0) } : -1,
                wakeupsPerSecond: group.members.reduce(0) { $0 + $1.packageIdleWakeupsPerSecond },
                diskReadPerSecond: group.members.reduce(0) { $0 + $1.diskReadBytesPerSecond },
                diskWritePerSecond: group.members.reduce(0) { $0 + $1.diskWriteBytesPerSecond },
                user: user(group.leader.uid), memberPIDs: group.pids, children: children)
        }
    }
}
