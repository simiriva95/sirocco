import SwiftUI

/// A plotted series: timestamps are absolute, the chart maps them onto a sliding window.
struct ChartSeries: Identifiable {
    var id: String
    var label: String
    var color: Color
    var points: [(Date, Double)]
}

/// Nice axis maximum: 1, 2, 5 × 10ⁿ at or above `value` (never below `floor`).
enum ChartScale {
    static func niceMax(_ value: Double, floor: Double) -> Double {
        let v = max(value, floor)
        guard v > 0 else { return floor }
        let magnitude = pow(10, Foundation.floor(log10(v)))
        for step in [1.0, 2.0, 5.0, 10.0] where step * magnitude >= v { return step * magnitude }
        return 10 * magnitude
    }

    /// Positions (0…1 across the window) for grid lines every `window / divisions`.
    static func timeTicks(divisions: Int) -> [Double] { (1..<divisions).map { Double($0) / Double(divisions) } }
}

/// Line + area chart over a sliding time window. `stacked` draws series as cumulative layers
/// (memory by type); otherwise they overlay. Grid and axis labels are drawn here, once, for
/// every chart in the app.
struct TimeSeriesChart: View {
    var series: [ChartSeries]
    var window: TimeInterval
    var now: Date
    var yMax: Double?                 // nil → nice auto-scale on the visible data
    var yFloor: Double = 1
    var stacked = false
    var leadingInset: CGFloat = 0     // to line up with a heatmap's row labels below
    var formatY: (Double) -> String

    private static let gridDivisions = 4
    static let labelWidth: CGFloat = 56

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let plot = CGRect(x: leadingInset, y: 4, width: size.width - Self.labelWidth - leadingInset, height: size.height - 18)
            let visible = series.map { s in s.points.filter { now.timeIntervalSince($0.0) <= window } }
            let top = yMax ?? ChartScale.niceMax(peak(visible), floor: yFloor)
            guard top > 0 else { return }

            drawGrid(context, plot: plot, top: top, size: size)

            var baseline = [Date: Double]()      // running stack per timestamp
            for (index, points) in visible.enumerated() {
                guard points.count > 1 else { continue }
                let color = series[index].color
                var lower: [CGPoint] = []
                var upper: [CGPoint] = []
                for (time, value) in points {
                    let x = plot.minX + plot.width * CGFloat(1 - now.timeIntervalSince(time) / window)
                    let base = stacked ? (baseline[time] ?? 0) : 0
                    let y0 = plot.maxY - plot.height * CGFloat(min(base / top, 1))
                    let y1 = plot.maxY - plot.height * CGFloat(min((base + value) / top, 1))
                    lower.append(CGPoint(x: x, y: y0))
                    upper.append(CGPoint(x: x, y: y1))
                    if stacked { baseline[time] = base + value }
                }
                var area = Path()
                area.move(to: lower[0])
                for p in upper { area.addLine(to: p) }
                for p in lower.reversed() { area.addLine(to: p) }
                area.closeSubpath()
                context.fill(area, with: .color(color.opacity(stacked ? 0.55 : DS.Chart.fillOpacity)))
                var line = Path()
                line.move(to: upper[0])
                for p in upper.dropFirst() { line.addLine(to: p) }
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: DS.Chart.lineWidth, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func peak(_ visible: [[(Date, Double)]]) -> Double {
        if stacked {
            var sums = [Date: Double]()
            for points in visible { for (t, v) in points { sums[t, default: 0] += v } }
            return sums.values.max() ?? 0
        }
        return visible.flatMap { $0.map(\.1) }.max() ?? 0
    }

    private func drawGrid(_ context: GraphicsContext, plot: CGRect, top: Double, size: CGSize) {
        let grid = Color.secondary.opacity(0.18)
        for i in 0...Self.gridDivisions {
            let fraction = Double(i) / Double(Self.gridDivisions)
            let y = plot.maxY - plot.height * CGFloat(fraction)
            context.stroke(Path { $0.move(to: CGPoint(x: plot.minX, y: y)); $0.addLine(to: CGPoint(x: plot.maxX, y: y)) },
                           with: .color(grid), lineWidth: 0.5)
            let label = Text(formatY(top * fraction)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
            context.draw(context.resolve(label), at: CGPoint(x: plot.maxX + 6, y: y), anchor: .leading)
        }
        for fraction in ChartScale.timeTicks(divisions: Self.gridDivisions) {
            let x = plot.minX + plot.width * CGFloat(fraction)
            context.stroke(Path { $0.move(to: CGPoint(x: x, y: plot.minY)); $0.addLine(to: CGPoint(x: x, y: plot.maxY)) },
                           with: .color(grid), lineWidth: 0.5)
            let seconds = window * (1 - fraction)
            let text = seconds >= 60 ? "−\(Int(seconds / 60)) min" : "−\(Int(seconds)) s"
            let label = Text(text).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
            context.draw(context.resolve(label), at: CGPoint(x: x, y: size.height - 2), anchor: .bottom)
        }
    }
}

/// Per-core usage over time: one row per core, intensity = usage. Rows are grouped by kind
/// (Efficiency first, then Performance), which is the visual signature of Apple Silicon.
struct CoreHeatmap: View {
    var samples: [(Date, [Double])]
    var topology: CoreTopology
    var window: TimeInterval
    var now: Date

    static let labelWidth: CGFloat = 26
    private static let groupGap: CGFloat = 6

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let count = topology.logicalCount
            guard count > 0 else { return }
            let hasGap = topology.efficiencyCoreCount > 0 && topology.performanceCoreCount > 0
            let rowHeight = (size.height - (hasGap ? Self.groupGap : 0)) / CGFloat(count)
            let plotWidth = size.width - Self.labelWidth - TimeSeriesChart.labelWidth   // same x axis as the chart above
            let visible = samples.filter { now.timeIntervalSince($0.0) <= window }
            func rowY(_ core: Int) -> CGFloat {
                CGFloat(core) * rowHeight + (hasGap && core >= topology.efficiencyCoreCount ? Self.groupGap : 0)
            }
            for core in 0..<count {
                let y = rowY(core)
                let kind = topology.kind(ofCore: core)
                let index = kind == .efficiency ? core + 1 : core - topology.efficiencyCoreCount + 1
                let label = Text("\(kind == .efficiency ? "E" : "P")\(index)").font(.system(size: 9, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
                context.draw(context.resolve(label), at: CGPoint(x: 0, y: y + rowHeight / 2), anchor: .leading)
                context.fill(Path(CGRect(x: Self.labelWidth, y: y, width: plotWidth, height: rowHeight - 1)), with: .color(.secondary.opacity(0.08)))
            }
            guard visible.count > 1 else { return }
            for (i, sample) in visible.enumerated() {
                let x1 = Self.labelWidth + plotWidth * CGFloat(1 - now.timeIntervalSince(sample.0) / window)
                let nextTime = i + 1 < visible.count ? visible[i + 1].0 : now
                let x2 = Self.labelWidth + plotWidth * CGFloat(1 - now.timeIntervalSince(nextTime) / window)
                let width = max(x2 - x1, 1)
                for (core, usage) in sample.1.enumerated() where core < count {
                    let y = rowY(core)
                    // Heat ramp: one hue whose opacity is the usage, turning red only when a core is pinned.
                    let color: Color = usage > 0.9 ? DS.color(.critical) : DS.color(.attention)
                    context.fill(Path(CGRect(x: x1, y: y, width: width, height: rowHeight - 1)),
                                 with: .color(color.opacity(0.06 + 0.94 * usage)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Card wrapper used by every chart section: title, live value, legend, chart.
struct ChartCard<Content: View>: View {
    var title: String
    var value: String
    var legend: [(label: String, color: Color, value: String)] = []
    var accessibilitySummary: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(DS.Typography.title)
                Spacer()
                Text(value).font(DS.Typography.value)
            }
            if !legend.isEmpty {
                HStack(spacing: DS.Spacing.m) {
                    ForEach(Array(legend.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: DS.Spacing.xs) {
                            RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 8, height: 8)
                            Text(item.label).foregroundStyle(.secondary)
                            Text(item.value).monospacedDigit()
                        }
                        .font(DS.Typography.secondary)
                    }
                }
            }
            content()
        }
        .padding(DS.Spacing.m)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: DS.Chart.cornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(accessibilitySummary)")
    }
}
