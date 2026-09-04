import Foundation
import Observation

/// Loaded when the Startup tab appears; nothing runs in the background.
@MainActor @Observable
final class StartupStore {
    private(set) var items: [LaunchItem] = []
    private(set) var isLoading = false
    var errorMessage: String?
    private let launchctl = LaunchctlClient()

    func reload() {
        guard !isLoading else { return }
        isLoading = true
        let launchctl = launchctl
        Task.detached(priority: .userInitiated) {
            let userDisabled = launchctl.disabledLabels(system: false)
            let systemDisabled = launchctl.disabledLabels(system: true)
            let items = LaunchItems.scan(directory: LaunchItems.userAgentsDirectory, source: .userAgent, disabledLabels: userDisabled)
                + LaunchItems.scan(directory: LaunchItems.systemAgentsDirectory, source: .systemAgent, disabledLabels: systemDisabled)
                + LaunchItems.scan(directory: LaunchItems.systemDaemonsDirectory, source: .systemDaemon, disabledLabels: systemDisabled)
            let sorted = items.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            await MainActor.run { [weak self] in
                self?.items = sorted
                self?.isLoading = false
            }
        }
    }

    func setEnabled(_ enabled: Bool, item: LaunchItem) {
        let launchctl = launchctl
        Task.detached { [weak self] in
            let failure = launchctl.setEnabled(enabled, item: item)
            await MainActor.run {
                guard let self else { return }
                if let failure { self.errorMessage = failure }
                self.reload()
            }
        }
    }
}
