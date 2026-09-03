import SwiftUI
import Observation

enum MainTab: Int, CaseIterable, Identifiable, Sendable {
    case overview, processes, performance, sensors, startup
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .processes: String(localized: "Processes")
        case .performance: String(localized: "Performance")
        case .sensors: String(localized: "Sensors")
        case .startup: String(localized: "Startup")
        }
    }
}

/// State of the single main window. App-global on purpose: menu commands act on it directly,
/// no focused-value plumbing for a window that exists once.
@MainActor @Observable
final class MainWindowModel {
    var tab: MainTab = .processes
    var query = ""
    var selection = Set<Int32>()
    private(set) var sortKey = UserDefaults.standard.string(forKey: "processSortKey") ?? "energy"
    private(set) var sortAscending = UserDefaults.standard.object(forKey: "processSortAscending") as? Bool ?? false
    var showInspector = false
    var searchFocusRequest = 0          // bumped by ⌘F; the view observes and focuses the field
    var pendingKill: PendingKill?
    var failureMessage: String?

    struct PendingKill: Identifiable {
        var id: Int { pids.hashValue }
        var pids: [Int32]
        var label: String
        var force: Bool
    }

    private let store: MetricsStore
    private let terminator: ProcessTerminator
    private let users = UserNames()

    init(store: MetricsStore, terminator: ProcessTerminator) {
        self.store = store
        self.terminator = terminator
    }

    func setSort(key: String, ascending: Bool) {
        sortKey = key
        sortAscending = ascending
        UserDefaults.standard.set(key, forKey: "processSortKey")
        UserDefaults.standard.set(ascending, forKey: "processSortAscending")
    }

    private var sortOrder: [KeyPathComparator<ProcessRow>] { ProcessRow.comparators(key: sortKey, ascending: sortAscending) }

    var rows: [ProcessRow] {
        let built = ProcessRowBuilder.rows(groups: store.groups, query: query,
                               name: { [store] in store.identities.identity(for: $0).name },
                               user: { [users] in users.name(for: $0) })
        let comparators = sortOrder
        let sorted = built.sorted(using: comparators)
        return sorted
            .map { row in
                guard var children = row.children else { return row }
                children.sort(using: comparators)
                var copy = row; copy.children = children; return copy
            }
    }

    /// Selected row (first), resolved to its live sample(s).
    var selectedSamples: [ProcessSample] {
        let all = store.groups.flatMap(\.members)
        return selection.flatMap { pid -> [ProcessSample] in
            if let group = store.groups.first(where: { $0.leader.pid == pid && $0.count > 1 }) { return group.members }
            return all.filter { $0.pid == pid }
        }
    }

    func requestTerminate(force: Bool) {
        let samples = selectedSamples
        guard !samples.isEmpty else { return }
        let label = samples.count == 1 ? store.identities.identity(for: samples[0]).name
            : String(localized: "\(samples.count) processes")
        if samples.count > 1 || force {
            pendingKill = PendingKill(pids: samples.map(\.pid), label: label, force: force)
        } else {
            perform(pids: samples.map(\.pid), force: false)
        }
    }

    func perform(pids: [Int32], force: Bool) {
        let samples = store.groups.flatMap(\.members).filter { pids.contains($0.pid) }
        let messages = samples.compactMap { sample -> String? in
            let outcome = force ? terminator.forceKill(sample) : terminator.terminate(sample)
            return TerminationMessages.text(for: outcome, name: store.identities.identity(for: sample).name)
        }
        if !messages.isEmpty { failureMessage = messages.joined(separator: "\n") }
    }

    func canEscalateSelection() -> Bool {
        selectedSamples.contains { terminator.canEscalate(pid: $0.pid) }
    }
}

/// One place turning a termination outcome into a sentence (shared by popover and window).
enum TerminationMessages {
    static func text(for outcome: ProcessTerminator.Outcome, name: String) -> String? {
        switch outcome {
        case .signalled, .failed(.noSuchProcess): nil
        case .denied(.systemCritical): String(localized: "\(name) is protected by the system and cannot be terminated.")
        case .denied(.otherUser): String(localized: "\(name) belongs to another user. Terminating it needs administrator privileges.")
        case .denied(.ownProcess): String(localized: "Sirocco won't terminate itself. Use Quit.")
        case .failed(.notPermitted): String(localized: "Permission denied by macOS (EPERM). \(name) is protected.")
        case .failed(.other(let code)): String(localized: "Signal failed for \(name) (errno \(code)).")
        }
    }
}
