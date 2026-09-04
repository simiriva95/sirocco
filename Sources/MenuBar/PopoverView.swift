import SwiftUI

struct PopoverView: View {
    var close: () -> Void
    var openWindow: () -> Void

    @Environment(MetricsStore.self) private var store
    @Environment(ProcessTerminator.self) private var terminator
    @State private var query = ""
    @State private var groupToConfirm: ProcessGroup?
    @State private var failureMessage: String?
    /// Row order captured when the pointer enters the list; rows stop jumping under the cursor.
    @State private var frozenOrder: [Int32]?

    private static let maxRows = 8

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            DiagnosisRow(diagnosis: store.diagnosis)
            chartsRow
            TextField(String(localized: "Search processes"), text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(String(localized: "Search processes"))
            processList
            footer
        }
        .padding(DS.Spacing.m)
        .frame(width: DS.Chart.popoverWidth)
        .onChange(of: store.latest?.timestamp) { _, _ in
            terminator.forget { !store.isAlive(pid: $0) }
        }
        .alert(item: $groupToConfirm) { group in
            Alert(title: Text("Terminate \(store.identities.identity(for: group.leader).name) and its \(group.count) processes?"),
                  primaryButton: .destructive(Text("Terminate")) { terminate(group) },
                  secondaryButton: .cancel(Text("Cancel")))
        }
        .alert(String(localized: "Couldn't terminate"), isPresented: Binding(get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } })) {
            Button(String(localized: "OK")) { failureMessage = nil }
        } message: {
            Text(failureMessage ?? "")
        }
    }

    // MARK: Charts

    private var chartsRow: some View {
        let cpu = store.latest?.cpu
        let memory = store.latest?.memory
        return HStack(spacing: DS.Spacing.s) {
            MiniChartCard(title: String(localized: "CPU"),
                          value: cpu.map { percent($0.total) } ?? "—",
                          detail: cpu.map { "P \(percent($0.performance)) · E \(percent($0.efficiency))" } ?? "",
                          severity: cpu.map { $0.total > 0.9 ? .critical : $0.total > 0.6 ? .attention : .nominal } ?? .nominal) {
                SparklineView(values: store.cpuHistory.elements.suffix(60).map { $0 }, capacity: 60,
                              color: DS.color(cpu.map { $0.total > 0.6 ? .attention : .nominal } ?? .nominal))
            }
            MiniChartCard(title: String(localized: "Memory"),
                          value: memory.map { $0.usedBytes.formatted(.byteCount(style: .memory)) } ?? "—",
                          detail: memory.map { percent($0.usedFraction) } ?? "",
                          severity: memory?.pressure.severity ?? .nominal) {
                SparklineView(values: store.memoryHistory.elements.suffix(60).map { $0 }, capacity: 60,
                              color: DS.color(memory?.pressure.severity ?? .nominal))
            }
            MiniChartCard(title: String(localized: "Thermal"),
                          value: store.thermalState.localizedName, detail: "",
                          severity: store.thermalState.severity, symbol: store.thermalState.symbolName) {
                ThermalStripView(levels: store.thermalHistory.elements.suffix(60).map(\.state.level), capacity: 60)
            }
        }
    }

    // MARK: Processes

    private var visibleGroups: [ProcessGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let filtered = trimmed.isEmpty ? store.groups : store.groups.filter { group in
            group.members.contains { member in
                member.command.localizedCaseInsensitiveContains(trimmed)
                    || store.identities.identity(for: member).name.localizedCaseInsensitiveContains(trimmed)
            }
        }
        guard let frozenOrder else { return Array(filtered.prefix(Self.maxRows)) }
        let byID = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, $0) })
        let kept = frozenOrder.compactMap { byID[$0] }
        let keptIDs = Set(kept.map(\.id))
        return Array((kept + filtered.filter { !keptIDs.contains($0.id) }).prefix(Self.maxRows))
    }

    @ViewBuilder
    private var processList: some View {
        if store.groups.isEmpty {
            Text("Loading…").font(DS.Typography.secondary).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: 0) {
                ForEach(visibleGroups) { group in
                    ProcessGroupRow(group: group, identity: store.identities.identity(for: group.leader),
                                    canEscalate: terminator.canEscalate(pid: group.leader.pid)) {
                        if terminator.canEscalate(pid: group.leader.pid) { forceKill(group) }
                        else if group.count > 1 { groupToConfirm = group }
                        else { terminate(group) }
                    }
                    Divider()
                }
            }
            .onHover { inside in
                frozenOrder = inside ? visibleGroups.map(\.id) : nil
            }
        }
    }

    private var footer: some View {
        HStack {
            if let me = store.selfSample {
                Text("Sirocco · \(percent(me.cpuFraction)) CPU · \(me.physFootprintBytes.formatted(.byteCount(style: .memory)))")
                    .font(DS.Typography.secondary).foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "Open Sirocco")) { openWindow() }
                .buttonStyle(.link).font(DS.Typography.secondary)
            Button(String(localized: "Quit")) { NSApp.terminate(nil) }
                .buttonStyle(.link).font(DS.Typography.secondary)
        }
    }

    // MARK: Actions

    private func terminate(_ group: ProcessGroup) {
        report(group.members.map { ($0, terminator.terminate($0)) })
    }

    private func forceKill(_ group: ProcessGroup) {
        report(group.members.map { ($0, terminator.forceKill($0)) })
    }

    private func report(_ outcomes: [(ProcessSample, ProcessTerminator.Outcome)]) {
        let messages = outcomes.compactMap { sample, outcome in
            TerminationMessages.text(for: outcome, name: store.identities.identity(for: sample).name)
        }
        if !messages.isEmpty { failureMessage = messages.joined(separator: "\n") }
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

// MARK: - Components

struct DiagnosisRow: View {
    var diagnosis: Diagnosis
    @Environment(MetricsStore.self) private var store

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
            Image(systemName: symbol).foregroundStyle(DS.color(severity)).accessibilityHidden(true)
            Text(sentence).font(DS.Typography.label).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.s)
        .background(DS.color(severity).opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Chart.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    private var severity: Severity {
        switch diagnosis {
        case .nominal: .nominal
        case .cpuBusy, .warming: .attention
        case .hot: .critical
        }
    }

    private var symbol: String {
        switch diagnosis {
        case .nominal: "checkmark.circle"
        case .cpuBusy: "cpu"
        case .warming: "thermometer.medium"
        case .hot: "flame.fill"
        }
    }

    private var sentence: String {
        func names(_ culprits: [Culprit]) -> String {
            culprits.map { culprit in
                let name = store.groups.lazy.flatMap(\.members).first { $0.pid == culprit.pid }
                    .map { store.identities.identity(for: $0).name } ?? culprit.command
                return culprit.isGraphicsProxy ? String(localized: "\(name) (graphics)") : name
            }.joined(separator: " + ")
        }
        switch diagnosis {
        case .nominal:
            return String(localized: "All quiet.")
        case .cpuBusy(let culprits):
            return String(localized: "CPU under load. Top consumer: \(names(culprits))")
        case .warming(let culprits):
            return culprits.isEmpty ? String(localized: "Warming up.") : String(localized: "Warming up. Top consumer: \(names(culprits))")
        case .hot(let seconds, let culprits):
            let duration = seconds >= 60 ? String(localized: "\(seconds / 60) min") : String(localized: "\(seconds) s")
            return culprits.isEmpty
                ? String(localized: "Hot for \(duration). No single culprit.")
                : String(localized: "Hot for \(duration). Likely cause: \(names(culprits))")
        }
    }
}

struct MiniChartCard<Chart: View>: View {
    var title: String
    var value: String
    var detail: String
    var severity: Severity
    var symbol: String?
    @ViewBuilder var chart: () -> Chart

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Text(title).font(DS.Typography.secondary).foregroundStyle(.secondary)
                if let symbol { Image(systemName: symbol).font(.caption2).foregroundStyle(DS.color(severity)) }
            }
            Text(value).font(DS.Typography.value).lineLimit(1).minimumScaleFactor(0.8)
            chart().frame(height: 22)
            Text(detail.isEmpty ? " " : detail).font(DS.Typography.secondary).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(DS.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: DS.Chart.cornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value). \(detail)")
    }
}

struct ProcessGroupRow: View {
    var group: ProcessGroup
    var identity: ProcessIdentityCache.Identity
    var canEscalate: Bool
    var action: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Group {
                if let icon = identity.icon { Image(nsImage: icon).resizable() } else { Image(systemName: "terminal") }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(identity.name).font(DS.Typography.label).lineLimit(1)
                if group.count > 1 {
                    Text("\(group.count) processes").font(DS.Typography.secondary).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: DS.Spacing.s)
            VStack(alignment: .trailing, spacing: 1) {
                Text(group.energyImpact.formatted(.number.precision(.fractionLength(0))))
                    .font(DS.Typography.value)
                Text("\(Int((group.cpuFraction * 100).rounded()))% · \(group.physFootprintBytes.formatted(.byteCount(style: .memory)))")
                    .font(DS.Typography.secondary).foregroundStyle(.secondary)
            }
            .frame(width: 96, alignment: .trailing)

            Button(action: action) {
                Image(systemName: canEscalate ? "bolt.fill" : "xmark.circle")
                    .foregroundStyle(canEscalate ? DS.color(.critical) : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(canEscalate ? String(localized: "Force Quit") : String(localized: "Terminate"))
            .accessibilityLabel(canEscalate ? String(localized: "Force Quit \(identity.name)") : String(localized: "Terminate \(identity.name)"))
        }
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityElement(children: .contain)
    }
}
