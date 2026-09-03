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

@MainActor @Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var iconContent: IconContent {
        didSet { defaults.set(iconContent.rawValue, forKey: "iconContent") }
    }

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
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
