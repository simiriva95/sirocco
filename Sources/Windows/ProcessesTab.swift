import SwiftUI

struct ProcessesTab: View {
    @Environment(MainWindowModel.self) private var model
    @Environment(MetricsStore.self) private var store

    var body: some View {
        @Bindable var model = model
        let rows = model.rows
        ProcessOutlineView(
            rows: rows, selection: model.selection, sortKey: model.sortKey, sortAscending: model.sortAscending,
            icon: { row in
                store.groups.lazy.flatMap(\.members).first { $0.pid == row.pid }.flatMap { store.identities.identity(for: $0).icon }
            },
            onSelection: { model.selection = $0 },
            onSort: { model.setSort(key: $0, ascending: $1) },
            onActivate: { model.showInspector = true },
            onTerminate: { model.requestTerminate(force: $0) })
        .inspector(isPresented: $model.showInspector) {
            ProcessDetailView(samples: model.selectedSamples)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(store.groups.isEmpty ? String(localized: "Loading…") : String(localized: "No matching processes"),
                                       systemImage: "magnifyingglass")
            }
        }
    }
}
