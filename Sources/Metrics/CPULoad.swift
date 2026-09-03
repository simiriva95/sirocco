/// Raw per-core tick counters as returned by `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`.
/// Absolute values are meaningless; only the delta between two samples is.
struct CPUTicks: Equatable, Sendable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    var total: UInt64 { user &+ system &+ idle &+ nice }
    var busy: UInt64 { user &+ system &+ nice }
}

/// How logical CPUs map onto Apple Silicon performance levels.
/// On every Apple Silicon Mac so far, Efficiency cores come first in the logical CPU
/// numbering (cpu0…cpuN-1 are E, the rest are P), while `hw.perflevel0` is the *Performance*
/// level. `efficiencyCoreCount` is therefore `hw.perflevel1.logicalcpu`.
struct CoreTopology: Equatable, Sendable {
    var logicalCount: Int
    var efficiencyCoreCount: Int

    var performanceCoreCount: Int { logicalCount - efficiencyCoreCount }

    func kind(ofCore index: Int) -> CoreKind {
        index < efficiencyCoreCount ? .efficiency : .performance
    }

    static let unknown = CoreTopology(logicalCount: 0, efficiencyCoreCount: 0)
}

enum CoreKind: Sendable, Hashable { case performance, efficiency }

/// One core's usage over a sampling interval, 0…1.
struct CoreLoad: Equatable, Sendable {
    var index: Int
    var kind: CoreKind
    var usage: Double
}

struct CPULoad: Equatable, Sendable {
    var cores: [CoreLoad]
    /// Average across all cores, 0…1.
    var total: Double
    /// Average across Performance cores, 0…1 (0 when none).
    var performance: Double
    /// Average across Efficiency cores, 0…1 (0 when none).
    var efficiency: Double

    static let zero = CPULoad(cores: [], total: 0, performance: 0, efficiency: 0)

    /// Pure delta computation. Returns nil when the two samples are not comparable
    /// (core count changed, or no time elapsed).
    static func delta(previous: [CPUTicks], current: [CPUTicks], topology: CoreTopology) -> CPULoad? {
        guard previous.count == current.count, !current.isEmpty else { return nil }
        var cores: [CoreLoad] = []
        cores.reserveCapacity(current.count)
        for i in current.indices {
            let dTotal = current[i].total &- previous[i].total
            let dBusy = current[i].busy &- previous[i].busy
            guard dTotal > 0, dBusy <= dTotal else { return nil }
            cores.append(CoreLoad(index: i, kind: topology.kind(ofCore: i), usage: Double(dBusy) / Double(dTotal)))
        }
        func mean(_ kind: CoreKind?) -> Double {
            let subset = kind.map { k in cores.filter { $0.kind == k } } ?? cores
            guard !subset.isEmpty else { return 0 }
            return subset.reduce(0) { $0 + $1.usage } / Double(subset.count)
        }
        return CPULoad(cores: cores, total: mean(nil), performance: mean(.performance), efficiency: mean(.efficiency))
    }
}
