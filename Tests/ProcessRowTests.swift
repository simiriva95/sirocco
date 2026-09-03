import XCTest
@testable import Sirocco

final class ProcessRowBuilderTests: XCTestCase {
    private let groups: [ProcessGroup] = {
        let chrome = Fixtures.sample(pid: 100, command: "Google Chrome", cpu: 0.1)
        let helper = Fixtures.sample(pid: 101, command: "Google Chrome He", cpu: 0.3)
        let terminal = Fixtures.sample(pid: 200, command: "Terminal", cpu: 0.05)
        return AppAggregation.group([chrome, helper, terminal]) { [101: 100][$0] }
    }()

    private func build(_ query: String) -> [ProcessRow] {
        ProcessRowBuilder.rows(groups: groups, query: query, name: { $0.pid == 101 ? "Chrome Helper (GPU)" : $0.command }, user: { _ in "me" })
    }

    func testGroupsBecomeExpandableRowsWithTotals() {
        let rows = build("")
        XCTAssertEqual(rows.map(\.pid), [100, 200])
        XCTAssertTrue(rows[0].isGroup)
        XCTAssertEqual(rows[0].children?.map(\.pid), [101, 100])
        XCTAssertEqual(rows[0].cpuFraction, 0.4, accuracy: 1e-9)
        XCTAssertEqual(rows[0].memberPIDs.sorted(), [100, 101])
        XCTAssertFalse(rows[1].isGroup)
    }

    func testQueryFiltersMembersAndKeepsGroupTotals() {
        let rows = build("gpu")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].children?.map(\.pid), [101])
        XCTAssertEqual(rows[0].cpuFraction, 0.4, accuracy: 1e-9, "totals stay whole-group")
        XCTAssertEqual(build("200").map(\.pid), [200], "pid search")
        XCTAssertTrue(build("nothing").isEmpty)
    }

    func testEnergyDescendingIsTheDefaultOrder() {
        let rows = build("").sorted(using: ProcessRow.comparators(key: "energy", ascending: false))
        XCTAssertEqual(rows.map(\.pid), [100, 200], "Chrome group (40) before Terminal (5)")
        let rowsAsc = build("").sorted(using: ProcessRow.comparators(key: "energy", ascending: true))
        XCTAssertEqual(rowsAsc.map(\.pid), [200, 100])
    }

    func testTiesBreakByPid() {
        let a = Fixtures.sample(pid: 30, command: "a", cpu: 0.0001)
        let b = Fixtures.sample(pid: 10, command: "b", cpu: 0.0002)
        let c = Fixtures.sample(pid: 20, command: "c", cpu: 0)
        let groups = AppAggregation.group([a, b, c]) { _ in nil }
        let rows = ProcessRowBuilder.rows(groups: groups, query: "", name: { $0.command }, user: { _ in "" })
            .sorted(using: ProcessRow.comparators(key: "energy", ascending: false))
        XCTAssertEqual(rows.map(\.pid), [10, 20, 30], "all round to 0 → ascending pid, regardless of input order")
    }

    func testSortingByKeyPath() {
        let rows = build("").sorted(using: [KeyPathComparator(\ProcessRow.name, order: .forward)])
        XCTAssertEqual(rows.map(\.name), ["Google Chrome", "Terminal"])
    }
}
