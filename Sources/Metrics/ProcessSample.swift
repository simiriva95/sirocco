import Foundation

/// Stable identity for a process: pid alone is recycled, pid + start time is not.
struct ProcessID: Hashable, Sendable {
    var pid: Int32
    var startTime: UInt64   // ri_proc_start_abstime, opaque, only compared for equality
}

/// Raw cumulative counters read from `proc_pid_rusage(RUSAGE_INFO_V4)` plus static facts.
/// Times are already converted to nanoseconds (mach absolute time → ns via timebase).
struct ProcessCounters: Equatable, Sendable {
    var id: ProcessID
    var parentPID: Int32
    var uid: UInt32
    var command: String            // p_comm, ≤16 chars, always available
    var userTimeNs: UInt64
    var systemTimeNs: UInt64
    var packageIdleWakeups: UInt64
    var interruptWakeups: UInt64
    var diskBytesRead: UInt64
    var diskBytesWritten: UInt64
    var physFootprintBytes: UInt64
    var residentBytes: UInt64
    var threadCount: Int?          // nil when not readable (other users' processes)
}

/// Rates over the last sampling interval — what the UI actually shows.
struct ProcessSample: Equatable, Sendable, Identifiable {
    var id: ProcessID
    var parentPID: Int32
    var uid: UInt32
    var command: String
    var cpuFraction: Double            // 1.0 == one core saturated
    var packageIdleWakeupsPerSecond: Double
    var interruptWakeupsPerSecond: Double
    var diskReadBytesPerSecond: Double
    var diskWriteBytesPerSecond: Double
    var physFootprintBytes: UInt64
    var residentBytes: UInt64
    var threadCount: Int?
    var energyImpact: Double

    var pid: Int32 { id.pid }
}

/// Turns two consecutive sets of cumulative counters into per-second rates.
/// Pure: the caller owns the previous state. Pids that disappeared are dropped; pids that
/// were recycled (same pid, different start time) start fresh instead of producing a
/// negative delta.
struct ProcessDeltaTracker: Sendable {
    private(set) var previous: [ProcessID: ProcessCounters] = [:]
    let model: EnergyImpactModel

    init(model: EnergyImpactModel = .current) {
        self.model = model
    }

    mutating func update(with current: [ProcessCounters], elapsedSeconds: Double) -> [ProcessSample] {
        defer { previous = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) }) }
        guard elapsedSeconds > 0 else { return [] }
        var samples: [ProcessSample] = []
        samples.reserveCapacity(current.count)
        for now in current {
            guard let before = previous[now.id] else { continue }
            func rate(_ a: UInt64, _ b: UInt64) -> Double { a >= b ? Double(a - b) / elapsedSeconds : 0 }
            let cpuNs = rate(now.userTimeNs, before.userTimeNs) + rate(now.systemTimeNs, before.systemTimeNs)
            var sample = ProcessSample(
                id: now.id, parentPID: now.parentPID, uid: now.uid, command: now.command,
                cpuFraction: cpuNs / 1_000_000_000,
                packageIdleWakeupsPerSecond: rate(now.packageIdleWakeups, before.packageIdleWakeups),
                interruptWakeupsPerSecond: rate(now.interruptWakeups, before.interruptWakeups),
                diskReadBytesPerSecond: rate(now.diskBytesRead, before.diskBytesRead),
                diskWriteBytesPerSecond: rate(now.diskBytesWritten, before.diskBytesWritten),
                physFootprintBytes: now.physFootprintBytes, residentBytes: now.residentBytes,
                threadCount: now.threadCount, energyImpact: 0)
            sample.energyImpact = model.score(sample)
            samples.append(sample)
        }
        return samples
    }
}
