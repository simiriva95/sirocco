import XCTest
@testable import Sirocco

final class DiagnosisEngineTests: XCTestCase {
    let engine = DiagnosisEngine()
    let now = Date(timeIntervalSinceReferenceDate: 10_000)

    private func history(_ states: [(ProcessInfo.ThermalState, Int)]) -> [ThermalEvent] {
        var events: [ThermalEvent] = []
        var t = now.addingTimeInterval(-Double(states.reduce(0) { $0 + $1.1 }))
        for (state, seconds) in states {
            for _ in 0..<seconds { events.append(ThermalEvent(timestamp: t, state: state)); t += 1 }
        }
        return events
    }

    func testHotWithCulpritsCoveringSixtyPercent() {
        let processes = [
            Fixtures.sample(pid: 1, command: "Chrome", cpu: 0.6),
            Fixtures.sample(pid: 2, command: "WindowServer", cpu: 0.3),
            Fixtures.sample(pid: 3, command: "Finder", cpu: 0.1),
        ]
        let input = DiagnosisInput(now: now, thermalHistory: history([(.nominal, 20), (.serious, 240)]),
                                   cpuHistory: [], processes: processes)
        guard case .hot(let seconds, let culprits) = engine.diagnose(input) else { return XCTFail("expected .hot") }
        XCTAssertEqual(seconds, 240, accuracy: 1)
        XCTAssertEqual(culprits.map(\.pid), [1], "Chrome alone covers 60 %")
    }

    func testWindowServerIsFlaggedAsGraphicsProxy() {
        let processes = [
            Fixtures.sample(pid: 1, command: "WindowServer", cpu: 0.5),
            Fixtures.sample(pid: 2, command: "Chrome", cpu: 0.4),
        ]
        let culprits = engine.topCulprits(processes)
        XCTAssertEqual(culprits.map(\.pid), [1, 2])
        XCTAssertTrue(culprits[0].isGraphicsProxy)
        XCTAssertFalse(culprits[1].isGraphicsProxy)
    }

    func testShortHotSpikeIsNotHotYet() {
        let input = DiagnosisInput(now: now, thermalHistory: history([(.nominal, 50), (.serious, 5)]), cpuHistory: [], processes: [])
        XCTAssertEqual(engine.diagnose(input), .nominal)
    }

    func testFairIsWarming() {
        let input = DiagnosisInput(now: now, thermalHistory: history([(.fair, 10)]), cpuHistory: [], processes: [])
        XCTAssertEqual(engine.diagnose(input), .warming(culprits: []))
    }

    func testSustainedCPUWithoutHeatIsBusy() {
        let processes = [Fixtures.sample(pid: 9, command: "ffmpeg", cpu: 6)]
        let input = DiagnosisInput(now: now, thermalHistory: history([(.nominal, 60)]),
                                   cpuHistory: Array(repeating: 0.9, count: 10), processes: processes)
        XCTAssertEqual(engine.diagnose(input), .cpuBusy(culprits: engine.topCulprits(processes)))
    }

    func testNoiseIsNotACulprit() {
        let processes = [Fixtures.sample(pid: 1, command: "idle", cpu: 0.01)]
        XCTAssertTrue(engine.topCulprits(processes).isEmpty)
    }
}
