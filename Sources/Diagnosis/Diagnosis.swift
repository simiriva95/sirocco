import Foundation

/// A named process contributing to the current situation.
struct Culprit: Equatable, Sendable {
    var pid: Int32
    var command: String
    var energyImpact: Double
    /// `WindowServer` being hot means *someone else* is driving heavy graphics; we cannot
    /// attribute GPU work per process through public API, so we say "graphics" instead.
    var isGraphicsProxy: Bool
}

/// Structured verdict. The view turns it into a localized sentence; this type never contains prose.
enum Diagnosis: Equatable, Sendable {
    case nominal
    case cpuBusy(culprits: [Culprit])
    case warming(culprits: [Culprit])
    case hot(forSeconds: Int, culprits: [Culprit])
}

struct ThermalEvent: Equatable, Sendable {
    var timestamp: Date
    var state: ProcessInfo.ThermalState
}

struct DiagnosisInput: Sendable {
    var now: Date
    /// Oldest → newest, at least the last minute.
    var thermalHistory: [ThermalEvent]
    /// Oldest → newest CPU total (0…1), same window.
    var cpuHistory: [Double]
    /// Current per-process samples (any order).
    var processes: [ProcessSample]
}

/// Deterministic, explainable rules. Struct in, struct out, no I/O.
struct DiagnosisEngine: Sendable {
    struct Thresholds: Sendable {
        var hotStates: Set<ProcessInfo.ThermalState> = [.serious, .critical]
        var hotMinimumSeconds: TimeInterval = 20
        var busyCPUFraction = 0.75
        var busyMinimumSamples = 10
        var culpritCoverage = 0.6        // culprits explain ≥ 60 % of total impact
        var maxCulprits = 2
        var minimumCulpritImpact = 5.0   // ignore noise
    }

    var thresholds = Thresholds()
    static let graphicsProxies: Set<String> = ["WindowServer"]

    func diagnose(_ input: DiagnosisInput) -> Diagnosis {
        let culprits = topCulprits(input.processes)
        if let since = hotSince(input) {
            return .hot(forSeconds: Int(input.now.timeIntervalSince(since).rounded()), culprits: culprits)
        }
        if input.thermalHistory.last?.state == .fair {
            return .warming(culprits: culprits)
        }
        let recent = input.cpuHistory.suffix(thresholds.busyMinimumSamples)
        if recent.count >= thresholds.busyMinimumSamples,
           recent.allSatisfy({ $0 >= thresholds.busyCPUFraction }) {
            return .cpuBusy(culprits: culprits)
        }
        return .nominal
    }

    /// Start of the current uninterrupted hot streak, if it is long enough to matter.
    private func hotSince(_ input: DiagnosisInput) -> Date? {
        guard let last = input.thermalHistory.last, thresholds.hotStates.contains(last.state) else { return nil }
        var start = last.timestamp
        for event in input.thermalHistory.reversed() {
            guard thresholds.hotStates.contains(event.state) else { break }
            start = event.timestamp
        }
        return input.now.timeIntervalSince(start) >= thresholds.hotMinimumSeconds ? start : nil
    }

    /// Smallest set of top processes (≤ maxCulprits) covering `culpritCoverage` of total impact.
    func topCulprits(_ processes: [ProcessSample]) -> [Culprit] {
        let total = processes.reduce(0) { $0 + $1.energyImpact }
        guard total > 0 else { return [] }
        var covered = 0.0
        var result: [Culprit] = []
        for p in processes.sorted(by: { $0.energyImpact > $1.energyImpact }) {
            guard result.count < thresholds.maxCulprits, p.energyImpact >= thresholds.minimumCulpritImpact else { break }
            result.append(Culprit(pid: p.pid, command: p.command, energyImpact: p.energyImpact,
                                  isGraphicsProxy: Self.graphicsProxies.contains(p.command)))
            covered += p.energyImpact
            if covered / total >= thresholds.culpritCoverage { break }
        }
        return result
    }
}
