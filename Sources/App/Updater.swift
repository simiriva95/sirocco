import Foundation
import Observation
import Sparkle

/// Sparkle 2 wrapper. The appcast is served from the public downloads repository and every
/// update is EdDSA-signed at release time (`make release`), which is what Sparkle verifies —
/// ad-hoc code signing gives it nothing else to check.
@MainActor @Observable
final class Updater {
    private let controller: SPUStandardUpdaterController

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
