import SwiftUI

struct PerformanceTab: View {
    @Environment(MetricsStore.self) private var store
    @State private var window: TimeInterval = 300

    private static let windows: [(TimeInterval, String)] = [(60, "1 min"), (300, "5 min"), (900, "15 min")]
    private static let seriesColors: [Color] = [.blue, .purple, .teal, .pink, .indigo, .mint]

    var body: some View {
        let samples = store.performance.elements
        let now = samples.last?.timestamp ?? Date()
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                HStack {
                    Spacer()
                    Picker(String(localized: "Window"), selection: $window) {
                        ForEach(Self.windows, id: \.0) { Text(String(localized: String.LocalizationValue($0.1))).tag($0.0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                if samples.count < 2 {
                    ContentUnavailableView(String(localized: "Collecting samples…"), systemImage: "waveform.path.ecg")
                        .frame(minHeight: 200)
                } else {
                    cpuCard(samples, now: now)
                    memoryCard(samples, now: now)
                    HStack(alignment: .top, spacing: DS.Spacing.m) {
                        diskCard(samples, now: now)
                        networkCard(samples, now: now)
                    }
                    thermalCard(samples, now: now)
                }
            }
            .padding(DS.Spacing.l)
        }
    }

    // MARK: Cards

    private func cpuCard(_ samples: [PerformanceSample], now: Date) -> some View {
        let last = samples.last!.cpu
        let hasSplit = store.topology.efficiencyCoreCount > 0 && store.topology.performanceCoreCount > 0
        var series = [ChartSeries(id: "total", label: String(localized: "Total"), color: .blue, points: samples.map { ($0.timestamp, $0.cpu.total) })]
        if hasSplit {
            series += [
                ChartSeries(id: "p", label: String(localized: "Performance cores"), color: .orange, points: samples.map { ($0.timestamp, $0.cpu.performance) }),
                ChartSeries(id: "e", label: String(localized: "Efficiency cores"), color: .green, points: samples.map { ($0.timestamp, $0.cpu.efficiency) }),
            ]
        }
        return ChartCard(title: String(localized: "CPU"), value: percent(last.total),
                         legend: series.map { s in (s.label, s.color, percent(s.points.last?.1 ?? 0)) },
                         accessibilitySummary: String(localized: "Total \(percent(last.total)), performance cores \(percent(last.performance)), efficiency cores \(percent(last.efficiency))")) {
            TimeSeriesChart(series: series, window: window, now: now, yMax: 1, leadingInset: CoreHeatmap.labelWidth, formatY: percent).frame(height: 120)
            CoreHeatmap(samples: samples.map { ($0.timestamp, $0.cpu.cores.map(\.usage)) }, topology: store.topology, window: window, now: now)
                .frame(height: CGFloat(max(store.topology.logicalCount, 1)) * 11 + 6)
                .padding(.top, DS.Spacing.xs)
        }
    }

    private func memoryCard(_ samples: [PerformanceSample], now: Date) -> some View {
        let last = samples.last!.memory
        let layers: [(String, Color, KeyPath<MemoryLoad, UInt64>)] = [
            (String(localized: "App"), .blue, \.appBytes),
            (String(localized: "Wired"), .orange, \.wiredBytes),
            (String(localized: "Compressed"), .purple, \.compressedBytes),
            (String(localized: "Cached files"), .gray, \.cachedFilesBytes),
        ]
        let series = layers.map { label, color, key in
            ChartSeries(id: label, label: label, color: color, points: samples.map { ($0.timestamp, Double($0.memory[keyPath: key])) })
        }
        return ChartCard(title: String(localized: "Memory"), value: "\(bytes(last.usedBytes)) / \(bytes(last.totalBytes))",
                         legend: layers.map { ($0.0, $0.1, bytes(last[keyPath: $0.2])) },
                         accessibilitySummary: String(localized: "Used \(bytes(last.usedBytes)) of \(bytes(last.totalBytes)), pressure \(last.pressure.severity == .nominal ? String(localized: "normal") : String(localized: "elevated"))")) {
            TimeSeriesChart(series: series, window: window, now: now, yMax: Double(last.totalBytes), stacked: true, formatY: { bytes(UInt64($0)) })
                .frame(height: 140)
            Text("Swap used: \(bytes(last.swapUsedBytes)) of \(bytes(last.swapTotalBytes))")
                .font(DS.Typography.secondary).foregroundStyle(.secondary)
        }
    }

    private func diskCard(_ samples: [PerformanceSample], now: Date) -> some View {
        let last = samples.last!.disk
        let series = [
            ChartSeries(id: "read", label: String(localized: "Read"), color: .blue, points: samples.map { ($0.timestamp, $0.disk.readBytesPerSecond) }),
            ChartSeries(id: "write", label: String(localized: "Write"), color: .orange, points: samples.map { ($0.timestamp, $0.disk.writeBytesPerSecond) }),
        ]
        return ChartCard(title: String(localized: "Disk"), value: "",
                         legend: [(series[0].label, .blue, rate(last.readBytesPerSecond)), (series[1].label, .orange, rate(last.writeBytesPerSecond))],
                         accessibilitySummary: String(localized: "Read \(rate(last.readBytesPerSecond)), write \(rate(last.writeBytesPerSecond))")) {
            TimeSeriesChart(series: series, window: window, now: now, yFloor: 102_400, formatY: { rate($0) }).frame(height: 120)
        }
    }

    private func networkCard(_ samples: [PerformanceSample], now: Date) -> some View {
        // Interfaces that moved any bytes inside the window, busiest first, at most three.
        var totals: [String: Double] = [:]
        for sample in samples where now.timeIntervalSince(sample.timestamp) <= window {
            for interface in sample.network { totals[interface.name, default: 0] += interface.total }
        }
        let names = totals.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        var series: [ChartSeries] = []
        var legend: [(label: String, color: Color, value: String)] = []
        for (index, name) in names.enumerated() {
            let color = Self.seriesColors[index % Self.seriesColors.count]
            let latest = samples.last?.network.first { $0.name == name }
            series.append(ChartSeries(id: "\(name)-rx", label: name, color: color,
                                      points: samples.map { ($0.timestamp, $0.network.first { $0.name == name }?.receivedBytesPerSecond ?? 0) }))
            series.append(ChartSeries(id: "\(name)-tx", label: name, color: color.opacity(0.55),
                                      points: samples.map { ($0.timestamp, $0.network.first { $0.name == name }?.sentBytesPerSecond ?? 0) }))
            legend.append((name, color, "↓ \(rate(latest?.receivedBytesPerSecond ?? 0)) ↑ \(rate(latest?.sentBytesPerSecond ?? 0))"))
        }
        return ChartCard(title: String(localized: "Network"), value: "", legend: legend,
                         accessibilitySummary: legend.map { "\($0.label) \($0.value)" }.joined(separator: ", ")) {
            if series.isEmpty {
                Text("No network traffic in this window.").font(DS.Typography.secondary).foregroundStyle(.secondary).frame(height: 120)
            } else {
                TimeSeriesChart(series: series, window: window, now: now, yFloor: 10_240, formatY: { rate($0) }).frame(height: 120)
            }
        }
    }

    private func thermalCard(_ samples: [PerformanceSample], now: Date) -> some View {
        let visible = samples.filter { now.timeIntervalSince($0.timestamp) <= window }
        return ChartCard(title: String(localized: "Thermal state"), value: store.thermalState.localizedName,
                         accessibilitySummary: store.thermalState.localizedName) {
            ThermalStripView(levels: visible.map(\.thermalLevel), capacity: max(visible.count, 1)).frame(height: 18)
            Text("Power draw and temperatures need sensor access — coming with the Sensors tab.")
                .font(DS.Typography.secondary).foregroundStyle(.secondary)
        }
    }

    // MARK: Formatting

    private func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
    private func bytes(_ value: UInt64) -> String {Format.bytes(value) }
    private func rate(_ bytesPerSecond: Double) -> String {
        bytesPerSecond < 1 ? "0 B/s" :Format.bytes(UInt64(bytesPerSecond)) + "/s"
    }
}
