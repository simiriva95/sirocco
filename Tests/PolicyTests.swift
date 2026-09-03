import XCTest
@testable import Sirocco

final class TerminationPolicyTests: XCTestCase {
    let policy = TerminationPolicy(ownPID: 4242, currentUID: 501)

    func testBlocklist() {
        XCTAssertEqual(policy.denial(pid: 0, command: "kernel_task", uid: 0), .systemCritical)
        XCTAssertEqual(policy.denial(pid: 1, command: "launchd", uid: 0), .systemCritical)
        XCTAssertEqual(policy.denial(pid: 300, command: "WindowServer", uid: 88), .systemCritical)
        XCTAssertEqual(policy.denial(pid: 301, command: "mds_stores", uid: 0), .systemCritical)
        XCTAssertEqual(policy.denial(pid: 302, command: "mdworker_shared", uid: 501), .systemCritical)
        XCTAssertEqual(policy.denial(pid: 303, command: "coreaudiod", uid: 202), .systemCritical)
    }

    func testOwnProcessAndOtherUsers() {
        XCTAssertEqual(policy.denial(pid: 4242, command: "Sirocco", uid: 501), .ownProcess)
        XCTAssertEqual(policy.denial(pid: 500, command: "nsurlsessiond", uid: 24), .otherUser)
        XCTAssertNil(policy.denial(pid: 501, command: "Google Chrome", uid: 501))
    }

    func testRootMayTerminateAnyUser() {
        let root = TerminationPolicy(ownPID: 1, currentUID: 0)
        XCTAssertNil(root.denial(pid: 500, command: "foo", uid: 24))
    }
}

final class SamplingPolicyTests: XCTestCase {
    func testCadence() {
        var demand = SamplingDemand.idle
        XCTAssertEqual(SamplingPolicy.interval(for: demand), .seconds(2))
        demand.popoverVisible = true
        demand.interests.insert(.processes)
        XCTAssertEqual(SamplingPolicy.interval(for: demand), .seconds(1))
        demand.thermalState = .critical
        XCTAssertEqual(SamplingPolicy.interval(for: demand), .seconds(2), "slows down under thermal pressure")
        demand.screenAsleep = true
        XCTAssertNil(SamplingPolicy.interval(for: demand), "suspended")
    }

    func testNothingVisible() {
        let demand = SamplingDemand(interests: [], popoverVisible: false, screenAsleep: false, thermalState: .nominal)
        XCTAssertEqual(SamplingPolicy.interval(for: demand), .seconds(5))
    }
}
