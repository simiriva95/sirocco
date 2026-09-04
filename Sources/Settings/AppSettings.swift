import Foundation
import Observation
import ServiceManagement

enum IconContent: String, CaseIterable, Sendable {
    case thermal, cpu, memory

    var localizedName: String {
        switch self {
        case .thermal: String(localized: "Thermal state")
        case .cpu: String(localized: "CPU")
        case .memory: String(localized: "Memory")
        }
    }
}

enum Theme: String, CaseIterable, Sendable {
    case system, light, dark

    var localizedName: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

/// UserDefaults-backed. Every property has a visible effect somewhere; nothing speculative.
@MainActor @Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var iconContent: IconContent { didSet { defaults.set(iconContent.rawValue, forKey: "iconContent") } }
    var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    /// Seconds between samples when only the menu bar is visible (popover is always 1 s).
    var restIntervalSeconds: Int { didSet { defaults.set(restIntervalSeconds, forKey: "restInterval") } }
    /// CPU fractions (0…1) above which charts and the icon switch to attention / critical.
    var cpuAttention: Double { didSet { defaults.set(cpuAttention, forKey: "cpuAttention") } }
    var cpuCritical: Double { didSet { defaults.set(cpuCritical, forKey: "cpuCritical") } }
    /// true → GiB-based like Activity Monitor ("GB" label, 1024); false → decimal GB (1000).
    var binaryUnits: Bool { didSet { defaults.set(binaryUnits, forKey: "binaryUnits"); Format.binaryUnits = binaryUnits } }
    /// Extra process names (p_comm or app name) that must never be terminated from the UI.
    var protectedNames: [String] { didSet { defaults.set(protectedNames, forKey: "protectedNames") } }

    var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    init() {
        iconContent = IconContent(rawValue: defaults.string(forKey: "iconContent") ?? "") ?? .thermal
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        restIntervalSeconds = [1, 2, 5].contains(defaults.integer(forKey: "restInterval")) ? defaults.integer(forKey: "restInterval") : 2
        cpuAttention = defaults.object(forKey: "cpuAttention") as? Double ?? 0.6
        cpuCritical = defaults.object(forKey: "cpuCritical") as? Double ?? 0.9
        binaryUnits = defaults.object(forKey: "binaryUnits") as? Bool ?? true
        protectedNames = defaults.stringArray(forKey: "protectedNames") ?? []
        launchAtLogin = SMAppService.mainApp.status == .enabled
        Format.binaryUnits = binaryUnits
    }

    func cpuSeverity(_ fraction: Double) -> Severity {
        fraction >= cpuCritical ? .critical : fraction >= cpuAttention ? .attention : .nominal
    }
}
