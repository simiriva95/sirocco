import SwiftUI
import AppKit

/// Semantic severity. Every colored element also changes shape or text: color is never the
/// only carrier of meaning (menu bar in dark mode, color-blind users, Increase Contrast).
enum Severity: Int, Comparable, Sendable {
    case nominal, attention, critical
    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
}

enum DS {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    enum Typography {
        static let value = Font.system(.body, weight: .semibold).monospacedDigit()
        static let secondary = Font.system(.caption).monospacedDigit()
        static let label = Font.system(.callout)
        static let title = Font.system(.subheadline, weight: .semibold)
    }

    enum Chart {
        static let lineWidth: CGFloat = 1.5
        static let fillOpacity = 0.18
        static let cornerRadius: CGFloat = 6
        static let popoverWidth: CGFloat = 340
    }

    static func color(_ severity: Severity) -> Color {
        switch severity {
        case .nominal: .green
        case .attention: .orange
        case .critical: .red
        }
    }

    static func nsColor(_ severity: Severity) -> NSColor {
        switch severity {
        case .nominal: .systemGreen
        case .attention: .systemOrange
        case .critical: .systemRed
        }
    }
}

extension ProcessInfo.ThermalState {
    var severity: Severity {
        switch self {
        case .nominal: .nominal
        case .fair: .attention
        case .serious, .critical: .critical
        @unknown default: .attention
        }
    }

    /// 0…3, used for the thermal strip.
    var level: Int {
        switch self {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        @unknown default: 1
        }
    }

    var localizedName: String {
        switch self {
        case .nominal: String(localized: "Nominal")
        case .fair: String(localized: "Fair")
        case .serious: String(localized: "Serious")
        case .critical: String(localized: "Critical")
        @unknown default: String(localized: "Unknown")
        }
    }

    /// SF Symbol paired with the color, so the state reads without color.
    var symbolName: String {
        switch self {
        case .nominal: "thermometer.low"
        case .fair: "thermometer.medium"
        case .serious: "thermometer.high"
        case .critical: "flame.fill"
        @unknown default: "thermometer.medium"
        }
    }
}

extension MemoryPressure {
    var severity: Severity {
        switch self {
        case .normal: .nominal
        case .warning: .attention
        case .critical: .critical
        }
    }
}
