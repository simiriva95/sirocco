import XCTest
@testable import Sirocco

final class ThroughputTests: XCTestCase {
    func testRatesAreDeltasOverElapsed() {
        XCTAssertEqual(CounterRate.perSecond(now: 3_000, previous: 1_000, elapsed: 2), 1_000)
        XCTAssertEqual(CounterRate.perSecond(now: 5, previous: 5, elapsed: 2), 0)
        XCTAssertEqual(CounterRate.perSecond(now: 10, previous: 5, elapsed: 0), 0, "no time elapsed → no rate")
    }

    func testThirtyTwoBitWraparoundIsNotANegativeBurst() {
        let nearTop = UInt64(UInt32.max) - 99
        XCTAssertEqual(CounterRate.perSecond(now: 100, previous: nearTop, elapsed: 1, bits: 32), 200)
        XCTAssertEqual(CounterRate.perSecond(now: 100, previous: nearTop, elapsed: 1, bits: 64), 0, "64-bit counter going backwards = reset, skip")
    }

    func testTrackerNeedsTwoSamplesAndSurvivesInterfaceChurn() {
        var tracker = ThroughputTracker()
        let first = tracker.update(disk: DiskCounters(bytesRead: 100, bytesWritten: 0),
                                   interfaces: [InterfaceCounters(name: "en0", received: 1_000, sent: 0)], elapsed: 0)
        XCTAssertNil(first.disk)
        XCTAssertTrue(first.network.isEmpty)

        let second = tracker.update(disk: DiskCounters(bytesRead: 2_148, bytesWritten: 1_024),
                                    interfaces: [InterfaceCounters(name: "en0", received: 3_048, sent: 512),
                                                 InterfaceCounters(name: "utun4", received: 10, sent: 10)], elapsed: 2)
        XCTAssertEqual(second.disk, DiskThroughput(readBytesPerSecond: 1_024, writeBytesPerSecond: 512))
        XCTAssertEqual(second.network.map(\.name), ["en0"], "new interface has no previous sample yet")
        XCTAssertEqual(second.network[0].receivedBytesPerSecond, 1_024)
        XCTAssertEqual(second.network[0].sentBytesPerSecond, 256)
    }
}
