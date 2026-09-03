import SwiftUI

struct MainWindowView: View {
    @Environment(MainWindowModel.self) private var model
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            Divider()
            switch model.tab {
            case .processes: ProcessesTab()
            default: ContentUnavailableView(model.tab.title, systemImage: "hammer",
                                            description: Text("Coming in a later milestone."))
            }
        }
        .frame(minWidth: 760, minHeight: 420)
        .onChange(of: model.searchFocusRequest) { _, _ in
            model.tab = .processes
            searchFocused = true
        }
        .alert(item: $model.pendingKill) { kill in
            Alert(title: Text(kill.force ? "Force quit \(kill.label)?" : "Terminate \(kill.label)?"),
                  message: Text(kill.force ? "SIGKILL cannot be caught: unsaved data in these processes is lost."
                                           : "The processes receive SIGTERM and may save their state before exiting."),
                  primaryButton: .destructive(Text(kill.force ? "Force Quit" : "Terminate")) { model.perform(pids: kill.pids, force: kill.force) },
                  secondaryButton: .cancel(Text("Cancel")))
        }
        .alert(String(localized: "Couldn't terminate"),
               isPresented: Binding(get: { model.failureMessage != nil }, set: { if !$0 { model.failureMessage = nil } })) {
            Button(String(localized: "OK")) { model.failureMessage = nil }
        } message: { Text(model.failureMessage ?? "") }
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: DS.Spacing.m) {
            Picker("", selection: $model.tab) {
                ForEach(MainTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(String(localized: "Section"))
            Spacer()
            TextField(String(localized: "Search processes"), text: $model.query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($searchFocused)
                .accessibilityLabel(String(localized: "Search processes"))
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.top, 30)     // room for the traffic lights (transparent titlebar, hidden title)
        .padding(.bottom, DS.Spacing.s)
    }
}
