import XCTest
import AppKit
@testable import Sirocco

/// The batch-update arithmetic is the one place where the outline view can silently diverge
/// from the model. Drive a real offscreen NSOutlineView and compare the row order.
@MainActor
final class ProcessOutlineViewTests: XCTestCase {
    private func row(_ pid: Int32, energy: Double, children: [Int32]? = nil) -> ProcessRow {
        ProcessRow(id: pid, name: "p\(pid)", pid: pid, energyImpact: energy, cpuFraction: 0, footprintBytes: 0, threads: 0,
                   wakeupsPerSecond: 0, diskReadPerSecond: 0, diskWritePerSecond: 0, user: "u", memberPIDs: [pid],
                   children: children?.map { row($0, energy: 0) })
    }

    private var window: NSWindow?

    /// Real window + scroll view so row views are actually created, like in the app.
    private func makeOutline() -> (ProcessOutlineView.Coordinator, NSOutlineView) {
        let coordinator = ProcessOutlineView.Coordinator()
        let outline = KeyOutlineView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.width = 300
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = coordinator
        outline.delegate = coordinator
        coordinator.outline = outline
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        scroll.documentView = outline
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        window.orderFront(nil)
        self.window = window
        return (coordinator, outline)
    }

    private func settle(_ outline: NSOutlineView) {
        outline.layoutSubtreeIfNeeded()
        outline.displayIfNeeded()
    }

    private func visibleOrder(_ outline: NSOutlineView) -> [Int32] {
        (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? ProcessOutlineView.RowItem)?.pid }
    }

    func testReorderInsertAndRemoveKeepOutlineInSyncWithModel() {
        let (coordinator, outline) = makeOutline()
        coordinator.apply(rows: [row(1, energy: 9), row(2, energy: 5), row(3, energy: 1)], selection: [], sortKey: "energy", ascending: false)
        settle(outline)
        XCTAssertEqual(visibleOrder(outline), [1, 2, 3])
        XCTAssertEqual((outline.view(atColumn: 0, row: 0, makeIfNecessary: false) as? NSTableCellView)?.textField?.stringValue, "p1")

        // 3 overtakes everyone, 2 exits, 4 appears at the bottom.
        coordinator.apply(rows: [row(3, energy: 20), row(1, energy: 9), row(4, energy: 0)], selection: [], sortKey: "energy", ascending: false)
        settle(outline)
        XCTAssertEqual(visibleOrder(outline), [3, 1, 4])
        XCTAssertEqual((0..<3).map { (outline.view(atColumn: 0, row: $0, makeIfNecessary: false) as? NSTableCellView)?.textField?.stringValue },
                       ["p3", "p1", "p4"], "cell views must show the row they now sit on")

        // Full shuffle.
        coordinator.apply(rows: [row(4, energy: 30), row(3, energy: 20), row(1, energy: 9)], selection: [], sortKey: "energy", ascending: false)
        settle(outline)
        XCTAssertEqual(visibleOrder(outline), [4, 3, 1])
        XCTAssertEqual((0..<3).map { (outline.view(atColumn: 0, row: $0, makeIfNecessary: false) as? NSTableCellView)?.textField?.stringValue },
                       ["p4", "p3", "p1"])
    }

    func testRowsHoldPositionWhileThePointerIsOverTheTable() {
        let (coordinator, outline) = makeOutline()
        coordinator.apply(rows: [row(1, energy: 9), row(2, energy: 5), row(3, energy: 1)], selection: [], sortKey: "energy", ascending: false)
        settle(outline)
        coordinator.isInteracting = { true }
        // Model says 3 is now on top and 2 is gone, 4 is new: order must not change under the pointer.
        coordinator.apply(rows: [row(3, energy: 20), row(1, energy: 9), row(4, energy: 0)], selection: [], sortKey: "energy", ascending: false)
        settle(outline)
        XCTAssertEqual(visibleOrder(outline), [1, 3, 4])
        XCTAssertEqual((outline.item(atRow: 1) as? ProcessOutlineView.RowItem)?.row.energyImpact, 20, "values still refresh")
        coordinator.isInteracting = { false }
        coordinator.apply(rows: [row(3, energy: 20), row(1, energy: 9), row(4, energy: 0)], selection: [], sortKey: "energy", ascending: false)
        settle(outline)
        XCTAssertEqual(visibleOrder(outline), [3, 1, 4], "re-sorts once the pointer leaves")
    }

    func testExpandedGroupChildrenFollowTheModel() {
        let (coordinator, outline) = makeOutline()
        coordinator.apply(rows: [row(10, energy: 5, children: [11, 12]), row(20, energy: 1)], selection: [], sortKey: "energy", ascending: false)
        settle(outline)
        outline.expandItem(outline.item(atRow: 0))
        settle(outline)
        XCTAssertEqual(visibleOrder(outline), [10, 11, 12, 20])

        coordinator.apply(rows: [row(10, energy: 5, children: [12, 13]), row(20, energy: 1)], selection: [], sortKey: "energy", ascending: false)
        settle(outline)
        XCTAssertEqual(visibleOrder(outline), [10, 12, 13, 20])
        XCTAssertEqual((0..<4).map { (outline.view(atColumn: 0, row: $0, makeIfNecessary: false) as? NSTableCellView)?.textField?.stringValue },
                       ["p10", "p12", "p13", "p20"])
        XCTAssertTrue(outline.isItemExpanded(outline.item(atRow: 0)), "expansion survives updates")
    }
}
