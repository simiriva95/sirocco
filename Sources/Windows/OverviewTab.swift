import SwiftUI

/// The dashboard: what is happening, in one screen. Diagnosis on top, the three vital charts,
/// then the top consumers per resource with one-click navigation to the process.
struct OverviewTab: View {
    @Environment(MetricsStore.self) private var store
    @Environment(MainWindowModel.self) private var model
    @Environment(AppSettings.self) private var settings

    private static let window: TimeInterval = 300
    private static let topCount = 5

    var body: some View {
        let samples = store.performance.elements
        let now = samples.last?.timestamp ?? Date()
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                DiagnosisRow(diagnosis: store.diagnosis)
                HStack(alignment: .top, spacing: DS.Spacing.m) {
                    cpuCard(samples, now: now)
                    memoryCard(samples, now: now)
                    thermalCard(samples, now: now)
                }
                HStack(alignment: .top, spacing: DS.Spacing.m) {
                    topList(String(localized: "Top CPU"), symbol: "cpu",
                            groups: store.groups.sorted { $0.cpuFraction > $1.cpuFraction }) { Format.percent($0.cpuFraction) }
                    topList(String(localized: "Top memory"), symbol: "memorychip",
                            groups: store.groups.sorted { $0.physFootprintBytes > $1.physFootprintBytes }) { Format.bytes($0.physFootprintBytes) }
                    topList(String(localized: "Top energy"), symbol: "bolt",
                            groups: store.groups) { $0.energyImpact.formatted(.number.precision(.fractionLength(0))) }
                }
                footer(samples.last)
            }
            .padding(DS.Spacing.l)
        }
    }

    // MARK: Charts

    private func cpuCard(_ samples: [PerformanceSample], now: Date) -> some View {
        let cpu = samples.last?.cpu ?? .zero
        let severity = settings.cpuSeverity(cpu.total)
        return ChartCard(title: String(localized: "CPU"), value: Format.percent(cpu.total),
                         legend: [(String(localized: "P"), .orange, Format.percent(cpu.performance)), (String(localized: "E"), .green, Format.percent(cpu.efficiency))],
                         accessibilitySummary: String(localized: "Total \(Format.percent(cpu.total)), performance cores \(Format.percent(cpu.performance)), efficiency cores \(Format.percent(cpu.efficiency))")) {
            TimeSeriesChart(series: [ChartSeries(id: "cpu", label: "", color: DS.color(severity), points: samples.map { ($0.timestamp, $0.cpu.total) })],
                            window: Self.window, now: now, yMax: 1, formatY: Format.percent).frame(height: 90)
        }
    }

    private func memoryCard(_ samples: [PerformanceSample], now: Date) -> some View {
        let memory = samples.last?.memory ?? .zero
        return ChartCard(title: String(localized: "Memory"), value: Format.bytes(memory.usedBytes),
                         legend: [(String(localized: "of"), .clear, Format.bytes(memory.totalBytes)),
                                  (String(localized: "Swap"), .clear, Format.bytes(memory.swapUsedBytes))],
                         accessibilitySummary: String(localized: "Used \(Format.bytes(memory.usedBytes)) of \(Format.bytes(memory.totalBytes)), pressure \(memory.pressure.severity == .nominal ? String(localized: "normal") : String(localized: "elevated"))")) {
            TimeSeriesChart(series: [ChartSeries(id: "mem", label: "", color: DS.color(memory.pressure.severity),
                                                 points: samples.map { ($0.timestamp, Double($0.memory.usedBytes)) })],
                            window: Self.window, now: now, yMax: Double(max(memory.totalBytes, 1)), formatY: { Format.bytes($0) }).frame(height: 90)
        }
    }

    private func thermalCard(_ samples: [PerformanceSample], now: Date) -> some View {
        let sensors = store.sensors
        var legend: [(label: String, color: Color, value: String)] = []
        if let die = sensors?.cpuDieCelsius { legend.append((String(localized: "CPU die"), .orange, Format.celsius(die))) }
        if let watts = sensors?.systemPowerWatts { legend.append((String(localized: "Power"), .blue, Format.watts(watts))) }
        if let battery = sensors?.battery { legend.append((String(localized: "Battery"), .green, Format.percent(battery.chargePercent / 100))) }
        let visible = samples.filter { now.timeIntervalSince($0.timestamp) <= Self.window }
        return ChartCard(title: String(localized: "Thermal"), value: store.thermalState.localizedName, legend: legend,
                         accessibilitySummary: ([store.thermalState.localizedName] + legend.map { "\($0.label) \($0.value)" }).joined(separator: ", ")) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: store.thermalState.symbolName).foregroundStyle(DS.color(store.thermalState.severity))
                    Text(thermalHint).font(DS.Typography.secondary).foregroundStyle(.secondary)
                }
                ThermalStripView(levels: visible.map(\.thermalLevel), capacity: max(visible.count, 1)).frame(height: 14)
                Spacer(minLength: 0)
            }
            .frame(height: 90, alignment: .top)
        }
    }

    private var thermalHint: String {
        switch store.thermalState {
        case .nominal: String(localized: "No thermal pressure.")
        case .fair: String(localized: "Slightly warm; fans may spin up.")
        case .serious: String(localized: "Hot: performance is being reduced.")
        case .critical: String(localized: "Critical: the system is throttling hard.")
        @unknown default: ""
        }
    }

    // MARK: Top lists

    private func topList(_ title: String, symbol: String, groups: [ProcessGroup], value: @escaping (ProcessGroup) -> String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(title).font(DS.Typography.title)
            }
            if groups.isEmpty {
                Text("Loading…").font(DS.Typography.secondary).foregroundStyle(.secondary)
            }
            ForEach(groups.prefix(Self.topCount)) { group in
                let identity = store.identities.identity(for: group.leader)
                Button {
                    model.selection = [group.leader.pid]
                    model.tab = .processes
                    model.showInspector = true
                } label: {
                    HStack(spacing: DS.Spacing.s) {
                        Group {
                            if let icon = identity.icon { Image(nsImage: icon).resizable() } else { Image(systemName: "terminal") }
                        }
                        .frame(width: 16, height: 16).accessibilityHidden(true)
                        Text(identity.name).lineLimit(1)
                        if group.count > 1 {
                            Text("\(group.count)").font(DS.Typography.secondary).foregroundStyle(.secondary)
                                .padding(.horizontal, 5).background(.quaternary, in: Capsule())
                        }
                        Spacer(minLength: DS.Spacing.s)
                        Text(value(group)).font(DS.Typography.value).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(identity.name), \(value(group))")
                .accessibilityHint(String(localized: "Shows the process in the Processes tab"))
            }
        }
        .padding(DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func footer(_ last: PerformanceSample?) -> some View {
        HStack(spacing: DS.Spacing.l) {
            if let disk = last?.disk {
                Label("↓ \(Format.rate(disk.readBytesPerSecond))  ↑ \(Format.rate(disk.writeBytesPerSecond))", systemImage: "internaldrive")
                    .accessibilityLabel(String(localized: "Disk read \(Format.rate(disk.readBytesPerSecond)), write \(Format.rate(disk.writeBytesPerSecond))"))
            }
            if let network = last?.network, !network.isEmpty {
                let rx = network.reduce(0) { $0 + $1.receivedBytesPerSecond }, tx = network.reduce(0) { $0 + $1.sentBytesPerSecond }
                Label("↓ \(Format.rate(rx))  ↑ \(Format.rate(tx))", systemImage: "network")
                    .accessibilityLabel(String(localized: "Network received \(Format.rate(rx)), sent \(Format.rate(tx))"))
            }
            Spacer()
            if let me = store.selfSample {
                Text("Sirocco · \(Format.percent(me.cpuFraction)) CPU · \(Format.bytes(me.physFootprintBytes))")
            }
        }
        .font(DS.Typography.secondary).foregroundStyle(.secondary)
    }
}
