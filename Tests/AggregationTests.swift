import XCTest
@testable import Sirocco

final class AppAggregationTests: XCTestCase {
    func testHelpersCollapseUnderResponsibleProcess() {
        let chrome = Fixtures.sample(pid: 100, command: "Google Chrome", cpu: 0.1)
        let gpu = Fixtures.sample(pid: 101, command: "Google Chrome He", cpu: 0.3)
        let renderer = Fixtures.sample(pid: 102, command: "Google Chrome He", cpu: 0.2)
        let terminal = Fixtures.sample(pid: 200, command: "Terminal", cpu: 0.05)
        let responsible: [Int32: Int32] = [101: 100, 102: 100]

        let groups = AppAggregation.group([terminal, renderer, chrome, gpu]) { responsible[$0] }

        XCTAssertEqual(groups.map(\.leader.pid), [100, 200], "sorted by total impact")
        XCTAssertEqual(groups[0].count, 3)
        XCTAssertEqual(groups[0].energyImpact, 60, accuracy: 1e-9)
        XCTAssertEqual(groups[0].members.map(\.pid), [101, 102, 100], "members sorted by impact")
        XCTAssertEqual(Set(groups[0].pids), [100, 101, 102])
    }

    func testMissingLeaderFallsBackToHeaviestMember() {
        let helper = Fixtures.sample(pid: 101, command: "helper", cpu: 0.3)
        let groups = AppAggregation.group([helper]) { _ in 100 }   // pid 100 not readable
        XCTAssertEqual(groups[0].leader.pid, 101)
        XCTAssertEqual(groups[0].count, 1)
    }
}
