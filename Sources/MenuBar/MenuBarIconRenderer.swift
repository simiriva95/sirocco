import AppKit

/// What the icon shows. Equatable so the controller redraws only when something visible changed.
struct MenuBarIconModel: Equatable {
    enum Glyph: Equatable { case dot, hollowTriangle, triangle, octagon }
    var bars: [Int]            // quantized sparkline, 0…sparklineLevels
    var glyph: Glyph?          // thermal shape (thermal content only)
    var label: String?         // "42%" (cpu / memory content)
    var severity: Severity
}

enum MenuBarIconRenderer {
    static let height: CGFloat = 18
    static let sparklineWidth: CGFloat = 26
    static let sparklineLevels = 12
    static let sparklineCapacity = 60
    private static let gap: CGFloat = 3
    private static let glyphWidth: CGFloat = 9
    private static var labelFont: NSFont { .monospacedDigitSystemFont(ofSize: 9, weight: .bold) }

    static func model(history: [Double], thermal: ProcessInfo.ThermalState, content: IconContent) -> MenuBarIconModel {
        // Auto-ranged (never below 25 %): an idle Mac at a fixed 0…100 % scale is a flat line,
        // which reads as "broken", not "idle". The popover charts keep the absolute scale.
        let recent = Array(history.suffix(sparklineCapacity))
        let scale = max(recent.max() ?? 0, 0.25)
        let bars = SparklineGeometry.quantize(recent, maxValue: scale, levels: sparklineLevels)
        switch content {
        case .thermal:
            let glyph: MenuBarIconModel.Glyph = switch thermal {
            case .nominal: .dot
            case .fair: .hollowTriangle
            case .serious: .triangle
            case .critical: .octagon
            @unknown default: .hollowTriangle
            }
            return MenuBarIconModel(bars: bars, glyph: glyph, label: nil, severity: thermal.severity)
        case .cpu, .memory:
            let value = history.last ?? 0
            return MenuBarIconModel(bars: bars, glyph: nil, label: "\(Int((value * 100).rounded()))%", severity: .nominal)
        }
    }

    static func image(for model: MenuBarIconModel) -> NSImage {
        let labelWidth = model.label.map { ($0 as NSString).size(withAttributes: [.font: labelFont]).width.rounded(.up) } ?? 0
        let tail = model.glyph != nil ? glyphWidth : labelWidth
        let size = NSSize(width: sparklineWidth + gap + tail, height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            let stroke: NSColor = .labelColor
            let rect = CGRect(x: 0, y: 2, width: sparklineWidth, height: height - 4)
            let points = SparklineGeometry.points(values: model.bars.map(Double.init), maxValue: Double(sparklineLevels),
                                                  capacity: sparklineCapacity, in: rect)
            if points.count > 1 {
                stroke.withAlphaComponent(0.25).setFill()
                NSBezierPath(cgPath: SparklineGeometry.areaPath(points, baseline: rect.maxY)).fill()
                stroke.setStroke()
                let line = NSBezierPath(cgPath: SparklineGeometry.linePath(points))
                line.lineWidth = 1.25
                line.lineJoinStyle = .round
                line.stroke()
            } else {
                stroke.withAlphaComponent(0.4).setFill()
                NSBezierPath(rect: CGRect(x: 0, y: rect.maxY - 1, width: sparklineWidth, height: 1)).fill()
            }
            let tailOrigin = sparklineWidth + gap
            if let glyph = model.glyph {
                drawGlyph(glyph, color: model.severity == .nominal ? stroke : DS.nsColor(model.severity),
                          in: CGRect(x: tailOrigin, y: (height - glyphWidth) / 2, width: glyphWidth, height: glyphWidth))
            } else if let label = model.label {
                let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: stroke]
                let textSize = (label as NSString).size(withAttributes: attributes)
                (label as NSString).draw(at: CGPoint(x: tailOrigin, y: (height - textSize.height) / 2), withAttributes: attributes)
            }
            return true
        }
        // Template images get free dark-mode / highlight handling but are monochrome, so the
        // orange/red states draw as regular images and rely on shape + color together.
        image.isTemplate = model.severity == .nominal
        return image
    }

    private static func drawGlyph(_ glyph: MenuBarIconModel.Glyph, color: NSColor, in rect: CGRect) {
        color.setFill()
        color.setStroke()
        switch glyph {
        case .dot:
            NSBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5)).fill()
        case .hollowTriangle, .triangle:
            let path = NSBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY - 0.5))
            path.line(to: CGPoint(x: rect.maxX - 0.5, y: rect.minY + 0.5))
            path.line(to: CGPoint(x: rect.minX + 0.5, y: rect.minY + 0.5))
            path.close()
            path.lineWidth = 1.25
            if glyph == .triangle { path.fill() } else { path.stroke() }
        case .octagon:
            let path = NSBezierPath()
            let c = rect.insetBy(dx: 0.5, dy: 0.5)
            let k = c.width * 0.29
            let corners = [
                CGPoint(x: c.minX + k, y: c.maxY), CGPoint(x: c.maxX - k, y: c.maxY),
                CGPoint(x: c.maxX, y: c.maxY - k), CGPoint(x: c.maxX, y: c.minY + k),
                CGPoint(x: c.maxX - k, y: c.minY), CGPoint(x: c.minX + k, y: c.minY),
                CGPoint(x: c.minX, y: c.minY + k), CGPoint(x: c.minX, y: c.maxY - k),
            ]
            path.move(to: corners[0])
            for point in corners.dropFirst() { path.line(to: point) }
            path.close()
            path.fill()
        }
    }
}
