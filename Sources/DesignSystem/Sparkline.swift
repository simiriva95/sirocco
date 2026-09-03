import SwiftUI

/// The one place that decides how a time series becomes a path. Used by both the SwiftUI
/// `Canvas` charts and the Core Graphics menu bar icon, so they cannot drift apart.
enum SparklineGeometry {
    /// Right-aligned: the newest value sits at the right edge and the series scrolls in
    /// from the right as the buffer fills.
    static func points(values: [Double], maxValue: Double, capacity: Int, in rect: CGRect) -> [CGPoint] {
        guard !values.isEmpty, capacity > 1, maxValue > 0 else { return [] }
        let step = rect.width / CGFloat(capacity - 1)
        let start = rect.maxX - step * CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let clamped = min(max(value / maxValue, 0), 1)
            return CGPoint(x: start + step * CGFloat(index), y: rect.maxY - CGFloat(clamped) * rect.height)
        }
    }

    static func linePath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    static func areaPath(_ points: [CGPoint], baseline: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: baseline))
        for point in points { path.addLine(to: point) }
        path.addLine(to: CGPoint(x: last.x, y: baseline))
        path.closeSubpath()
        return path
    }

    /// Integer levels 0…`levels`, used to decide whether a redraw is perceptible.
    static func quantize(_ values: [Double], maxValue: Double, levels: Int) -> [Int] {
        values.map { Int((min(max($0 / maxValue, 0), 1) * Double(levels)).rounded()) }
    }
}

/// Small line + area chart for a 0…max series. Accessibility label is the caller's job.
struct SparklineView: View {
    var values: [Double]
    var maxValue: Double = 1
    var capacity: Int
    var color: Color

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0, dy: DS.Chart.lineWidth)
            let points = SparklineGeometry.points(values: values, maxValue: maxValue, capacity: capacity, in: rect)
            guard points.count > 1 else { return }
            context.fill(Path(SparklineGeometry.areaPath(points, baseline: rect.maxY)), with: .color(color.opacity(DS.Chart.fillOpacity)))
            context.stroke(Path(SparklineGeometry.linePath(points)), with: .color(color),
                           style: StrokeStyle(lineWidth: DS.Chart.lineWidth, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Thermal history as a strip of colored segments; the current state is also spelled out
/// next to it by the caller, so the strip is decoration for sighted users, not the message.
struct ThermalStripView: View {
    var levels: [Int]       // 0…3, oldest → newest
    var capacity: Int

    var body: some View {
        Canvas { context, size in
            guard capacity > 0 else { return }
            let width = size.width / CGFloat(capacity)
            let start = size.width - width * CGFloat(levels.count)
            for (index, level) in levels.enumerated() {
                let rect = CGRect(x: start + width * CGFloat(index), y: 0, width: width + 0.5, height: size.height)
                let severity: Severity = level == 0 ? .nominal : level == 1 ? .attention : .critical
                context.fill(Path(rect), with: .color(DS.color(severity).opacity(level == 0 ? 0.35 : 0.9)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityHidden(true)
    }
}
