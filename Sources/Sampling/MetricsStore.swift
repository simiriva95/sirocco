import Foundation
import Observation
import os

/// Main-actor view model shared by every surface. Fixed-size histories; no persistence.
@MainActor @Observable
final class MetricsStore {
    static let historyCapacity = 900   // 15 min at 1 s

    private(set) var latest: SystemSnapshot?
    private(set) var cpuHistory = RingBuffer<Double>(capacity: historyCapacity)
    private(set) var memoryHistory = RingBuffer<Double>(capacity: historyCapacity)
    private(set) var thermalHistory = RingBuffer<ThermalEvent>(capacity: historyCapacity)
    /// Everything the Performance tab plots, one aligned sample per tick (skips the first tick).
    private(set) var performance = RingBuffer<PerformanceSample>(capacity: historyCapacity)
    private(set) var sensors: SensorSnapshot?
    private(set) var sensorHistory = RingBuffer<SensorSnapshot>(capacity: historyCapacity)
    private(set) var groups: [ProcessGroup] = []
    private(set) var diagnosis: Diagnosis = .nominal
    /// Our own footprint, shown in the popover footer and used for the README numbers.
    private(set) var selfSample: ProcessSample?
    /// Debug: print our own sample on every tick (SIROCCO_LOG_SELF).
    @ObservationIgnored var logSelf = false

    let topology = Sysctl.coreTopology()
    let identities = ProcessIdentityCache()
    private let engine = DiagnosisEngine()
    private let ownPID = getpid()
    private let selfLog = Logger(subsystem: "it.simoneriva.sirocco", category: "self")

    var thermalState: ProcessInfo.ThermalState { latest?.thermalState ?? .nominal }

    func ingest(_ snapshot: SystemSnapshot) {
        latest = snapshot
        if let cpu = snapshot.cpu {
            cpuHistory.append(cpu.total)
            performance.append(PerformanceSample(timestamp: snapshot.timestamp, cpu: cpu, memory: snapshot.memory,
                                                 disk: snapshot.disk ?? .zero, network: snapshot.network,
                                                 thermalLevel: snapshot.thermalState.level))
        }
        memoryHistory.append(snapshot.memory.usedFraction)
        thermalHistory.append(ThermalEvent(timestamp: snapshot.timestamp, state: snapshot.thermalState))

        if let sensorSnapshot = snapshot.sensors {
            sensors = sensorSnapshot
            sensorHistory.append(sensorSnapshot)
        }
        if let processes = snapshot.processes {
            groups = AppAggregation.group(processes) { snapshot.responsiblePIDs[$0] }
            selfSample = processes.first { $0.pid == ownPID }
            if logSelf, let me = selfSample {
                selfLog.notice("self cpu=\(me.cpuFraction * 100, format: .fixed(precision: 2), privacy: .public)% footprint=\(me.physFootprintBytes / 1_048_576, privacy: .public)MB wakeups=\(Int(me.packageIdleWakeupsPerSecond), privacy: .public)/s processes=\(processes.count, privacy: .public)")
            }
            identities.prune(alive: Set(processes.map(\.id)))
        }
        diagnosis = engine.diagnose(DiagnosisInput(
            now: snapshot.timestamp, thermalHistory: thermalHistory.elements,
            cpuHistory: cpuHistory.elements, processes: snapshot.processes ?? []))
    }

    func isAlive(pid: Int32) -> Bool {
        latest?.processes?.contains { $0.pid == pid } ?? ProcessEnumerator.isAlive(pid: pid)
    }
}
