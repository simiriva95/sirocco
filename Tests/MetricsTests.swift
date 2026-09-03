import XCTest
@testable import Sirocco

final class RingBufferTests: XCTestCase {
    func testWrapsAndKeepsOrder() {
        var buffer = RingBuffer<Int>(capacity: 3)
        (1...5).forEach { buffer.append($0) }
        XCTAssertEqual(buffer.elements, [3, 4, 5])
        XCTAssertEqual(buffer.last, 5)
        XCTAssertEqual(buffer.count, 3)
        XCTAssertTrue(buffer.isFull)
    }

    func testEmpty() {
        let buffer = RingBuffer<Int>(capacity: 3)
        XCTAssertEqual(buffer.elements, [])
        XCTAssertNil(buffer.last)
    }
}

final class CPULoadTests: XCTestCase {
    let topology = CoreTopology(logicalCount: 4, efficiencyCoreCount: 2)

    func testDeltaAndPerformanceEfficiencySplit() {
        let previous = Array(repeating: CPUTicks(user: 100, system: 100, idle: 800, nice: 0), count: 4)
        let current = [
            CPUTicks(user: 110, system: 100, idle: 890, nice: 0),   // E: 10 %
            CPUTicks(user: 100, system: 130, idle: 870, nice: 0),   // E: 30 %
            CPUTicks(user: 190, system: 110, idle: 800, nice: 0),   // P: 100 %
            CPUTicks(user: 150, system: 100, idle: 850, nice: 0),   // P: 50 %
        ]
        let load = CPULoad.delta(previous: previous, current: current, topology: topology)!
        XCTAssertEqual(load.cores.map(\.kind), [.efficiency, .efficiency, .performance, .performance])
        XCTAssertEqual(load.efficiency, 0.2, accuracy: 1e-9)
        XCTAssertEqual(load.performance, 0.75, accuracy: 1e-9)
        XCTAssertEqual(load.total, 0.475, accuracy: 1e-9)
    }

    func testRejectsMismatchedOrStaleSamples() {
        let ticks = [CPUTicks(user: 1, system: 1, idle: 1, nice: 0)]
        XCTAssertNil(CPULoad.delta(previous: ticks, current: ticks, topology: topology), "no elapsed ticks")
        XCTAssertNil(CPULoad.delta(previous: ticks, current: ticks + ticks, topology: topology), "core count changed")
    }
}

final class ProcessDeltaTests: XCTestCase {
    private func counters(pid: Int32, start: UInt64 = 1, user: UInt64, system: UInt64 = 0,
                          wakeups: UInt64 = 0, read: UInt64 = 0) -> ProcessCounters {
        ProcessCounters(id: ProcessID(pid: pid, startTime: start), parentPID: 1, uid: 501, command: "p\(pid)",
                        userTimeNs: user, systemTimeNs: system, packageIdleWakeups: wakeups, interruptWakeups: 0,
                        diskBytesRead: read, diskBytesWritten: 0, physFootprintBytes: 1, residentBytes: 1, threadCount: nil)
    }

    func testRatesAreDeltasOverElapsedTime() {
        var tracker = ProcessDeltaTracker(model: .v1)
        XCTAssertTrue(tracker.update(with: [counters(pid: 7, user: 0)], elapsedSeconds: 0).isEmpty, "first sample has no delta")
        let samples = tracker.update(with: [counters(pid: 7, user: 500_000_000, system: 500_000_000, wakeups: 200, read: 4_194_304)],
                                     elapsedSeconds: 2)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].cpuFraction, 0.5, accuracy: 1e-9)          // 1 s of CPU over 2 s
        XCTAssertEqual(samples[0].packageIdleWakeupsPerSecond, 100)
        XCTAssertEqual(samples[0].diskReadBytesPerSecond, 2_097_152)
        XCTAssertEqual(samples[0].energyImpact, 50 + 100 * 0.5 + 2 * 0.5, accuracy: 1e-9)
    }

    func testRecycledPIDStartsFresh() {
        var tracker = ProcessDeltaTracker()
        _ = tracker.update(with: [counters(pid: 7, start: 1, user: 9_000_000_000)], elapsedSeconds: 0)
        let samples = tracker.update(with: [counters(pid: 7, start: 2, user: 1_000)], elapsedSeconds: 1)
        XCTAssertTrue(samples.isEmpty, "same pid, new start time → no bogus negative/huge delta")
    }

    func testDisappearedProcessesAreDropped() {
        var tracker = ProcessDeltaTracker()
        _ = tracker.update(with: [counters(pid: 1, user: 0), counters(pid: 2, user: 0)], elapsedSeconds: 0)
        let samples = tracker.update(with: [counters(pid: 2, user: 1)], elapsedSeconds: 1)
        XCTAssertEqual(samples.map(\.pid), [2])
    }
}

final class EnergyImpactModelTests: XCTestCase {
    func testOneSaturatedCoreIsOneHundred() {
        var sample = Fixtures.sample(pid: 1, command: "x", cpu: 1.0)
        sample.energyImpact = EnergyImpactModel.v1.score(sample)
        XCTAssertEqual(sample.energyImpact, 100)
    }

    func testIdleProcessIsZero() {
        XCTAssertEqual(EnergyImpactModel.v1.score(Fixtures.sample(pid: 1, command: "x", cpu: 0)), 0)
    }

    func testFormulaIsVersioned() {
        XCTAssertEqual(EnergyImpactModel.current.version, 1)
    }
}

enum Fixtures {
    static func sample(pid: Int32, command: String, cpu: Double, wakeups: Double = 0, uid: UInt32 = 501) -> ProcessSample {
        var s = ProcessSample(id: ProcessID(pid: pid, startTime: 1), parentPID: 1, uid: uid, command: command,
                              cpuFraction: cpu, packageIdleWakeupsPerSecond: wakeups, interruptWakeupsPerSecond: 0,
                              diskReadBytesPerSecond: 0, diskWriteBytesPerSecond: 0, physFootprintBytes: 100, residentBytes: 100,
                              threadCount: nil, energyImpact: 0)
        s.energyImpact = EnergyImpactModel.current.score(s)
        return s
    }
}
