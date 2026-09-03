import Foundation

/// What some visible surface currently needs. The sampler only does work somebody is looking at.
enum SamplingInterest: Hashable, Sendable {
    case systemOverview     // CPU total, memory, thermal — the menu bar icon
    case processes          // process enumeration + per-process rusage
    case perCore            // per-core breakdown (Performance tab, M3)
}

/// Where the interests come from and how urgently they need data.
struct SamplingDemand: Equatable, Sendable {
    var interests: Set<SamplingInterest>
    var popoverVisible: Bool
    var screenAsleep: Bool
    var thermalState: ProcessInfo.ThermalState

    static let idle = SamplingDemand(interests: [.systemOverview], popoverVisible: false,
                                     screenAsleep: false, thermalState: .nominal)
}

/// Pure interval policy:
///   1s with the popover open · 2s at rest · 5s when nothing is visible ·
///   ×2 under `.critical` thermal state (a monitor must consume less when the machine is hot).
enum SamplingPolicy {
    static let popoverInterval: Duration = .seconds(1)
    static let restInterval: Duration = .seconds(2)
    static let hiddenInterval: Duration = .seconds(5)

    static func interval(for demand: SamplingDemand) -> Duration? {
        if demand.screenAsleep { return nil }                    // suspended
        var base: Duration
        if demand.popoverVisible { base = popoverInterval }
        else if demand.interests.isEmpty { base = hiddenInterval }
        else { base = restInterval }
        if demand.thermalState == .critical { base *= 2 }
        return base
    }
}
