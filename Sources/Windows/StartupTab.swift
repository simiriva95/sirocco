import SwiftUI

struct StartupTab: View {
    @Environment(MainWindowModel.self) private var model

    var body: some View {
        let startup = model.startup
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                HStack {
                    Text("Login items are managed by macOS and cannot be listed without administrator rights.")
                        .font(DS.Typography.secondary).foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "Open Login Items settings")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                    Button(String(localized: "Reload")) { startup.reload() }.disabled(startup.isLoading)
                }
                section(String(localized: "User LaunchAgents"), startup.items.filter { $0.source == .userAgent }, startup: startup, editable: true)
                section(String(localized: "System LaunchAgents"), startup.items.filter { $0.source == .systemAgent }, startup: startup, editable: false)
                section(String(localized: "System LaunchDaemons"), startup.items.filter { $0.source == .systemDaemon }, startup: startup, editable: false)
            }
            .padding(DS.Spacing.l)
        }
        .onAppear { if startup.items.isEmpty { startup.reload() } }
        .alert(String(localized: "Couldn't change startup item"),
               isPresented: Binding(get: { startup.errorMessage != nil }, set: { if !$0 { startup.errorMessage = nil } })) {
            Button(String(localized: "OK")) { startup.errorMessage = nil }
        } message: { Text(startup.errorMessage ?? "") }
    }

    private func section(_ title: String, _ items: [LaunchItem], startup: StartupStore, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(DS.Typography.title)
                Text("\(items.count)").font(DS.Typography.secondary).foregroundStyle(.secondary)
                Spacer()
                if !editable {
                    Text("Read-only: changing system jobs needs administrator rights.").font(DS.Typography.secondary).foregroundStyle(.secondary)
                }
            }
            if items.isEmpty {
                Text(startup.isLoading ? String(localized: "Scanning…") : String(localized: "No items"))
                    .font(DS.Typography.secondary).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack(spacing: DS.Spacing.m) {
                            Toggle("", isOn: Binding(get: { item.enabled }, set: { startup.setEnabled($0, item: item) }))
                                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                                .disabled(!editable)
                                .accessibilityLabel(String(localized: "Enabled") + ": " + item.label)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.label).font(DS.Typography.label).lineLimit(1)
                                if let program = item.program {
                                    Text(program).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            Spacer()
                            if item.runAtLoad {
                                Text("Run at load").font(DS.Typography.secondary).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, DS.Spacing.xs)
                        .opacity(item.enabled ? 1 : 0.6)
                        .accessibilityElement(children: .combine)
                        Divider()
                    }
                }
            }
        }
        .padding(DS.Spacing.m)
        .cardBackground()
    }
}
