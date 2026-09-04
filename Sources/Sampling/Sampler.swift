import Foundation

/// The only thing in the app that touches the interop layer periodically. One loop, one
/// owner of the C buffers; publishes immutable snapshots to the main-actor store.
actor Sampler {
    private let store: MetricsStore
    private let enumerator = ProcessEnumerator()
    private let topology: CoreTopology
    private let totalMemory: UInt64

    private var demand = SamplingDemand.idle
    private var loop: Task<Void, Never>?
    private var previousTicks: [CPUTicks]?
    private var lastTick: ContinuousClock.Instant?
    private var deltaTracker = ProcessDeltaTracker()
    private var throughput = ThroughputTracker()
    private var responsibleCache: [Int32: Int32?] = [:]

    init(store: MetricsStore) {
        self.store = store
        topology = Sysctl.coreTopology()
        totalMemory = Sysctl.physicalMemory()
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { await run() }
    }

    /// Restarts the loop only when the cadence actually changes, so an idle demand update
    /// does not force an extra tick.
    func setDemand(_ new: SamplingDemand) {
        let wantsProcessesNow = new.interests.contains(.processes) && !demand.interests.contains(.processes)
        let cadenceChanged = SamplingPolicy.interval(for: new) != SamplingPolicy.interval(for: demand)
        demand = new
        if wantsProcessesNow || cadenceChanged {
            loop?.cancel()
            loop = Task { await run() }
        }
    }

    private func run() async {
        while !Task.isCancelled {
            let warmup = demand.interests.contains(.processes) && deltaTracker.previous.isEmpty
            sample()
            demand.thermalState = ProcessInfo.processInfo.thermalState
            guard let interval = SamplingPolicy.interval(for: demand) else { return }   // suspended
            try? await Task.sleep(for: warmup ? .milliseconds(500) : interval)
        }
    }

    private func sample() {
        let now = ContinuousClock.now
        let elapsed = lastTick.map { now - $0 } ?? .zero
        lastTick = now
        let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

        let ticks = MachHost.cpuTicks()
        var cpu: CPULoad?
        if let ticks, let previousTicks {
            cpu = CPULoad.delta(previous: previousTicks, current: ticks, topology: topology)
        }
        previousTicks = ticks

        let rates = throughput.update(disk: DiskStatistics.read(), interfaces: NetworkCounters.read(), elapsed: elapsedSeconds)

        var processes: [ProcessSample]?
        var responsible: [Int32: Int32] = [:]
        if demand.interests.contains(.processes) {
            let counters = enumerator.snapshot(includeThreads: demand.interests.contains(.processDetails))
            processes = deltaTracker.update(with: counters, elapsedSeconds: elapsedSeconds)
            let alive = Set(counters.map(\.id.pid))
            responsibleCache = responsibleCache.filter { alive.contains($0.key) }
            for pid in alive {
                if responsibleCache[pid] == nil { responsibleCache[pid] = .some(ProcessEnumerator.responsiblePID(for: pid)) }
                if let leader = responsibleCache[pid] ?? nil { responsible[pid] = leader }
            }
        } else {
            deltaTracker = ProcessDeltaTracker()   // stale deltas are worse than a warm-up
        }

        let snapshot = SystemSnapshot(
            timestamp: Date(), cpu: cpu,
            memory: MachHost.memoryLoad(totalBytes: totalMemory) ?? .zero,
            thermalState: ProcessInfo.processInfo.thermalState,
            disk: rates.disk, network: rates.network,
            processes: processes, responsiblePIDs: responsible)
        Task { @MainActor [store] in store.ingest(snapshot) }
    }
}
