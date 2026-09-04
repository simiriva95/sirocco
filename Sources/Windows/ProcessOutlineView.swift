import AppKit
import SwiftUI

/// The Processes table is an `NSOutlineView`, not a SwiftUI `Table`: with ~800 live rows the
/// SwiftUI table re-inserts rows with automatic heights on every tick (8–9 % CPU in Release).
/// Here rows are fixed-height, items are reused across ticks (expansion survives), and when
/// the order has not changed only the visible cells' text is touched.
struct ProcessOutlineView: NSViewRepresentable {
    var rows: [ProcessRow]
    var selection: Set<Int32>
    var sortKey: String
    var sortAscending: Bool
    var icon: (ProcessRow) -> NSImage?
    var onSelection: (Set<Int32>) -> Void
    var onSort: (String, Bool) -> Void
    var onActivate: () -> Void
    var onTerminate: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let outline = KeyOutlineView()
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.rowHeight = 22
        outline.usesAutomaticRowHeights = false
        outline.usesAlternatingRowBackgroundColors = true
        outline.allowsMultipleSelection = true
        outline.allowsColumnReordering = true
        outline.autosaveName = "ProcessColumns"
        outline.autosaveTableColumns = true
        outline.autoresizesOutlineColumn = false
        outline.style = .plain
        outline.intercellSpacing = NSSize(width: 8, height: 0)
        outline.target = coordinator
        outline.doubleAction = #selector(Coordinator.doubleClicked)
        outline.onReturn = { [weak coordinator] in coordinator?.onActivate?() }
        outline.setAccessibilityLabel(String(localized: "Processes"))

        for spec in ColumnSpec.all {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            column.width = spec.width
            column.minWidth = spec.min
            column.sortDescriptorPrototype = NSSortDescriptor(key: spec.id, ascending: spec.id == "name" || spec.id == "user")
            outline.addTableColumn(column)
        }
        outline.outlineTableColumn = outline.tableColumns[0]

        let menu = NSMenu()
        menu.delegate = coordinator
        menu.addItem(withTitle: String(localized: "Show Details"), action: #selector(Coordinator.showDetails), keyEquivalent: "").target = coordinator
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Terminate"), action: #selector(Coordinator.terminate), keyEquivalent: "").target = coordinator
        menu.addItem(withTitle: String(localized: "Force Quit"), action: #selector(Coordinator.forceQuit), keyEquivalent: "").target = coordinator
        outline.menu = menu

        let headerMenu = NSMenu()
        for spec in ColumnSpec.all where spec.id != "name" {
            let item = headerMenu.addItem(withTitle: spec.title, action: #selector(Coordinator.toggleColumn(_:)), keyEquivalent: "")
            item.representedObject = spec.id
            item.target = coordinator
        }
        headerMenu.delegate = coordinator
        outline.headerView?.menu = headerMenu

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        coordinator.outline = outline
        coordinator.isInteracting = { [weak outline] in
            guard let outline, let window = outline.window else { return false }
            if NSEvent.pressedMouseButtons != 0 { return true }
            let point = outline.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            return outline.visibleRect.contains(point) && window.isKeyWindow
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.icon = icon
        coordinator.onSelection = onSelection
        coordinator.onSort = onSort
        coordinator.onActivate = onActivate
        coordinator.onTerminate = onTerminate
        coordinator.apply(rows: rows, selection: selection, sortKey: sortKey, ascending: sortAscending)
    }

    // MARK: - Columns

    struct ColumnSpec {
        let id: String, title: String, width: CGFloat, min: CGFloat, numeric: Bool
        static let all: [ColumnSpec] = [
            .init(id: "name", title: String(localized: "Name"), width: 260, min: 160, numeric: false),
            .init(id: "pid", title: String(localized: "PID"), width: 64, min: 50, numeric: true),
            .init(id: "energy", title: String(localized: "Energy"), width: 70, min: 50, numeric: true),
            .init(id: "cpu", title: String(localized: "% CPU"), width: 70, min: 50, numeric: true),
            .init(id: "memory", title: String(localized: "Memory"), width: 90, min: 60, numeric: true),
            .init(id: "threads", title: String(localized: "Threads"), width: 64, min: 50, numeric: true),
            .init(id: "wakeups", title: String(localized: "Wakeups/s"), width: 80, min: 60, numeric: true),
            .init(id: "read", title: String(localized: "Read/s"), width: 84, min: 60, numeric: true),
            .init(id: "write", title: String(localized: "Write/s"), width: 84, min: 60, numeric: true),
            .init(id: "user", title: String(localized: "User"), width: 90, min: 50, numeric: false),
        ]

        @MainActor static func text(_ id: String, _ row: ProcessRow) -> String {
            switch id {
            case "name": row.name
            case "pid": String(row.pid)
            case "energy": row.energyImpact.formatted(.number.precision(.fractionLength(0)))
            case "cpu": (row.cpuFraction * 100).formatted(.number.precision(.fractionLength(1)))
            case "memory":Format.bytes(row.footprintBytes)
            case "threads": row.threads < 0 ? "—" : String(row.threads)
            case "wakeups": row.wakeupsPerSecond.formatted(.number.precision(.fractionLength(0)))
            case "read": rate(row.diskReadPerSecond)
            case "write": rate(row.diskWritePerSecond)
            case "user": row.user
            default: ""
            }
        }

        @MainActor private static func rate(_ bytesPerSecond: Double) -> String {
            bytesPerSecond < 1024 ? "—" :Format.bytes(UInt64(bytesPerSecond)) + "/s"
        }
    }

    // MARK: - Coordinator

    /// Item objects are reused across ticks so NSOutlineView keeps expansion state. A group's
    /// leader also appears as one of its children, so children are keyed by -pid: the same
    /// object must never sit in two places of the outline.
    final class RowItem: NSObject {
        let key: Int32
        var row: ProcessRow
        var children: [RowItem]
        var pid: Int32 { row.pid }
        init(key: Int32, row: ProcessRow) { self.key = key; self.row = row; children = [] }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        weak var outline: NSOutlineView?
        var icon: ((ProcessRow) -> NSImage?)?
        var onSelection: ((Set<Int32>) -> Void)?
        var onSort: ((String, Bool) -> Void)?
        var onActivate: (() -> Void)?
        var onTerminate: ((Bool) -> Void)?

        private var items: [RowItem] = []
        private var pool: [Int32: RowItem] = [:]
        private var topOrder: [Int32] = []
        private var childOrder: [Int32: [Int32]] = [:]
        private var suppressSelectionCallback = false
        /// While the pointer is over the table (or a button is down) rows keep their positions:
        /// values still refresh, dead rows leave, new rows append at the bottom. Re-sorting
        /// resumes when the pointer leaves. Overridable for tests.
        var isInteracting: () -> Bool = { false }
        private let nameFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

        func apply(rows: [ProcessRow], selection: Set<Int32>, sortKey: String, ascending: Bool) {
            guard let outline else { return }
            var newPool: [Int32: RowItem] = [:]
            func item(for row: ProcessRow, key: Int32) -> RowItem {
                let entry = pool[key] ?? RowItem(key: key, row: row)
                entry.row = row
                entry.children = (row.children ?? []).map { item(for: $0, key: -$0.pid) }
                newPool[key] = entry
                return entry
            }
            let oldGroups = Set(childOrder.keys)
            var ordered = rows
            if isInteracting(), !topOrder.isEmpty {
                let byPID = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
                let kept = topOrder.compactMap { byPID[$0] }
                let keptSet = Set(kept.map(\.pid))
                ordered = kept + rows.filter { !keptSet.contains($0.pid) }
                ordered = ordered.map { row in
                    guard let children = row.children, let old = childOrder[row.pid] else { return row }
                    let byChild = Dictionary(uniqueKeysWithValues: children.map { ($0.pid, $0) })
                    let keptChildren = old.compactMap { byChild[$0] }
                    var copy = row
                    copy.children = keptChildren + children.filter { child in !old.contains(child.pid) }
                    return copy
                }
            }
            items = ordered.map { item(for: $0, key: $0.pid) }
            pool = newPool
            let newTop = items.map(\.pid)
            let newChildren = Dictionary(uniqueKeysWithValues: items.filter { !$0.children.isEmpty }.map { ($0.pid, $0.children.map(\.pid)) })

            if let current = outline.sortDescriptors.first, current.key != sortKey || current.ascending != ascending {
                outline.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: ascending)]
            }

            // Until the view is in a window the outline has not loaded anything, so there is no
            // baseline to diff against: reload and keep the bookkeeping empty.
            guard outline.window != nil else {
                outline.reloadData()
                topOrder = []
                childOrder = [:]
                return
            }
            if topOrder.isEmpty {
                outline.reloadData()
            } else if newTop != topOrder || newChildren != childOrder {
                // Structural change: describe it as removals + insertions so surviving rows keep
                // their views (and the user's selection). Only expanded groups need child diffs.
                outline.beginUpdates()
                applyDiff(old: topOrder, new: newTop, parent: nil)
                for item in items where outline.isItemExpanded(item) {
                    applyDiff(old: childOrder[item.pid] ?? [], new: item.children.map(\.pid), parent: item)
                }
                outline.endUpdates()
                for item in items where oldGroups.contains(item.pid) != !item.children.isEmpty {
                    outline.reloadItem(item, reloadChildren: false)   // disclosure triangle appeared/disappeared
                }
                // Safety net: if AppKit and our bookkeeping ever disagree, resync instead of drifting.
                let expected = newTop.count + items.filter { outline.isItemExpanded($0) }.reduce(0) { $0 + $1.children.count }
                if outline.numberOfRows != expected { outline.reloadData() }
            }
            topOrder = newTop
            childOrder = newChildren
            refreshVisibleCells()
            syncSelection(selection)
        }

        /// NSTableView batch semantics are sequential: each call sees the state left by the
        /// previous one. Descending removals then ascending insertions keep every index valid.
        /// A reordered row is remove+insert on purpose: `moveItem` measured ~2× more expensive.
        private func applyDiff(old: [Int32], new: [Int32], parent: RowItem?) {
            guard old != new, let outline else { return }
            let diff = new.difference(from: old)
            let removals = IndexSet(diff.removals.compactMap { if case .remove(let offset, _, _) = $0 { offset } else { nil } })
            let insertions = IndexSet(diff.insertions.compactMap { if case .insert(let offset, _, _) = $0 { offset } else { nil } })
            if !removals.isEmpty { outline.removeItems(at: removals, inParent: parent, withAnimation: []) }
            if !insertions.isEmpty { outline.insertItems(at: insertions, inParent: parent, withAnimation: []) }
        }

        private func refreshVisibleCells() {
            guard let outline else { return }
            let visible = outline.rows(in: outline.visibleRect)
            guard visible.length > 0 else { return }
            for row in visible.location..<(visible.location + visible.length) {
                guard let item = outline.item(atRow: row) as? RowItem else { continue }
                for (columnIndex, column) in outline.tableColumns.enumerated() where !column.isHidden {
                    guard let cell = outline.view(atColumn: columnIndex, row: row, makeIfNecessary: false) as? NSTableCellView else { continue }
                    let id = column.identifier.rawValue
                    let text = ColumnSpec.text(id, item.row)
                    // Setting an unchanged string still invalidates layout and redraws the cell:
                    // with ~25 visible rows × 10 columns at 1 Hz that alone was ~4 % CPU.
                    if let field = cell.textField, field.stringValue != text {
                        field.stringValue = text
                        if id == "name" { cell.needsLayout = true }
                    }
                    if id == "name" { (cell as? NameCellView)?.setBadge(item.children.isEmpty ? nil : item.children.count) }
                }
            }
        }

        private func syncSelection(_ selection: Set<Int32>) {
            guard let outline else { return }
            let current = Set(outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? RowItem)?.pid })
            guard current != selection else { return }
            var indexes = IndexSet()
            for row in 0..<outline.numberOfRows {
                if let item = outline.item(atRow: row) as? RowItem, selection.contains(item.pid) { indexes.insert(row) }
            }
            suppressSelectionCallback = true
            outline.selectRowIndexes(indexes, byExtendingSelection: false)
            suppressSelectionCallback = false
        }

        // MARK: NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? RowItem)?.children.count ?? items.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            (item as? RowItem)?.children[index] ?? items[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            !((item as? RowItem)?.children.isEmpty ?? true)
        }

        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = outlineView.sortDescriptors.first, let key = descriptor.key else { return }
            onSort?(key, descriptor.ascending)
        }

        // MARK: NSOutlineViewDelegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let tableColumn, let item = item as? RowItem else { return nil }
            let id = tableColumn.identifier.rawValue
            let spec = ColumnSpec.all.first { $0.id == id }
            if id == "name" {
                let cell = outlineView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? NameCellView
                    ?? NameCellView(identifier: tableColumn.identifier, font: nameFont)
                cell.textField?.stringValue = item.row.name
                cell.imageView?.image = icon?(item.row)
                cell.setBadge(item.children.isEmpty ? nil : item.children.count)
                cell.needsLayout = true
                return cell
            }
            let cell = outlineView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? NSTableCellView
                ?? makeTextCell(identifier: tableColumn.identifier, numeric: spec?.numeric ?? false)
            cell.textField?.stringValue = ColumnSpec.text(id, item.row)
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !suppressSelectionCallback, let outline else { return }
            onSelection?(Set(outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? RowItem)?.pid }))
        }

        private func makeTextCell(identifier: NSUserInterfaceItemIdentifier, numeric: Bool) -> NSTableCellView {
            TextCellView(identifier: identifier, font: numeric ? numberFont : nameFont, alignment: numeric ? .right : .left)
        }

        // MARK: Actions

        @objc func doubleClicked() { onActivate?() }
        @objc func showDetails() { onActivate?() }
        @objc func terminate() { onTerminate?(false) }
        @objc func forceQuit() { onTerminate?(true) }

        @objc func toggleColumn(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String,
                  let column = outline?.tableColumns.first(where: { $0.identifier.rawValue == id }) else { return }
            column.isHidden.toggle()
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let outline else { return }
            if menu === outline.headerView?.menu {
                for item in menu.items {
                    let hidden = outline.tableColumns.first { $0.identifier.rawValue == (item.representedObject as? String) }?.isHidden ?? false
                    item.state = hidden ? .off : .on
                }
                return
            }
            // Right-click on an unselected row acts on that row, like Finder.
            let clicked = outline.clickedRow
            if clicked >= 0, !outline.selectedRowIndexes.contains(clicked) {
                outline.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
            }
        }
    }
}

/// Return key → activate (details); everything else is stock NSOutlineView behaviour
/// (arrows move, ←/→ collapse/expand, type-to-select).
final class KeyOutlineView: NSOutlineView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?() } else { super.keyDown(with: event) }
    }
}

/// Plain text cell laid out by frame: Auto Layout per cell is measurable at 800 rows × 1 Hz.
final class TextCellView: NSTableCellView {
    init(identifier: NSUserInterfaceItemIdentifier, font: NSFont, alignment: NSTextAlignment) {
        super.init(frame: .zero)
        self.identifier = identifier
        let field = NSTextField(labelWithString: "")
        field.font = font
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        addSubview(field)
        textField = field
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() { super.layout(); relayout() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); relayout() }

    private func relayout() {
        guard let field = textField else { return }
        let height = ceil(field.attributedStringValue.size().height)
        field.frame = CGRect(x: 2, y: (bounds.height - height) / 2, width: bounds.width - 4, height: height)
    }
}

/// Icon + name + optional member-count badge.
final class NameCellView: NSTableCellView {
    private let badge = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier, font: NSFont) {
        super.init(frame: .zero)
        self.identifier = identifier
        let image = NSImageView()
        image.imageScaling = .scaleProportionallyDown
        let name = NSTextField(labelWithString: "")
        name.font = font
        name.lineBreakMode = .byTruncatingTail
        name.usesSingleLineMode = true
        badge.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        badge.textColor = .secondaryLabelColor
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 7
        badge.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        badge.alignment = .center
        for view in [image, name, badge] { addSubview(view) }
        imageView = image
        textField = name
    }

    override func layout() { super.layout(); relayout() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); relayout() }

    /// Frame-based: NSTableCellView does not re-run layout() on column resizes, so we do.
    private func relayout() {
        guard let image = imageView, let name = textField else { return }
        let h = bounds.height
        image.frame = CGRect(x: 2, y: (h - 16) / 2, width: 16, height: 16)
        // intrinsicContentSize of a truncating label reports its current width, so measure the text itself.
        let badgeWidth = badge.isHidden ? 0 : max(18, badge.attributedStringValue.size().width + 6)
        let nameSize = name.attributedStringValue.size()
        let nameHeight = ceil(nameSize.height)
        let nameWidth = min(ceil(nameSize.width) + 8, bounds.width - 24 - (badge.isHidden ? 0 : badgeWidth + 6))   // +8: NSTextFieldCell horizontal padding
        name.frame = CGRect(x: 24, y: (h - nameHeight) / 2, width: max(nameWidth, 0), height: nameHeight)
        badge.frame = CGRect(x: name.frame.maxX + 6, y: (h - 14) / 2, width: badgeWidth, height: 14)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func setBadge(_ count: Int?) {
        let text = count.map { " \($0) " } ?? ""
        guard badge.isHidden != (count == nil) || badge.stringValue != text else { return }
        badge.isHidden = count == nil
        badge.stringValue = text
        relayout()
        badge.setAccessibilityLabel(count.map { String(localized: "\($0) processes") })
    }
}
