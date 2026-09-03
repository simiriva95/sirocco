/// Groups processes by responsible process (Chrome + its 40 helpers → one row).
/// Pure: the responsible-pid lookup is injected so the rule is testable without libproc.
struct ProcessGroup: Equatable, Sendable, Identifiable {
    var id: Int32 { leader.pid }
    var leader: ProcessSample
    var members: [ProcessSample]      // includes leader, sorted by energy impact desc

    var count: Int { members.count }
    var energyImpact: Double { members.reduce(0) { $0 + $1.energyImpact } }
    var cpuFraction: Double { members.reduce(0) { $0 + $1.cpuFraction } }
    var physFootprintBytes: UInt64 { members.reduce(0) { $0 &+ $1.physFootprintBytes } }
    var pids: [Int32] { members.map(\.pid) }
}

enum AppAggregation {
    /// `responsible(pid)` returns the pid responsible for `pid`, or nil/self when it is its
    /// own leader. When the leader is not in `samples` (e.g. not readable), the member with
    /// the highest impact becomes the visible leader.
    static func group(_ samples: [ProcessSample], responsible: (Int32) -> Int32?) -> [ProcessGroup] {
        var buckets: [Int32: [ProcessSample]] = [:]
        for s in samples {
            var leader = responsible(s.pid) ?? s.pid
            if leader <= 0 { leader = s.pid }
            buckets[leader, default: []].append(s)
        }
        let byPID = Dictionary(uniqueKeysWithValues: samples.map { ($0.pid, $0) })
        return buckets.map { leaderPID, members in
            let sorted = members.sorted { $0.energyImpact > $1.energyImpact }
            let leader = byPID[leaderPID] ?? sorted[0]
            return ProcessGroup(leader: leader, members: sorted)
        }
        .sorted { $0.energyImpact > $1.energyImpact }
    }
}
