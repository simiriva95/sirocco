import Foundation
import Observation

/// Trial state persisted twice (UserDefaults + a file in Application Support): the earliest
/// install date wins, so deleting one copy does not restart the trial.
@MainActor @Observable
final class LicenseManager: LicenseGating {
    private(set) var state: LicenseState = .trial(daysLeft: TrialClock.trialDays)
    private let defaults = UserDefaults.standard
    private let markerURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sirocco", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(".trial")
    }()

    init() {
        refresh()
    }

    nonisolated func isUnlocked(_ feature: GatedFeature) -> Bool {
        MainActor.assumeIsolated { state != .expired }
    }

    var isExpired: Bool { state == .expired }

    /// Re-evaluates the state and advances the anti-rollback clock. Cheap; called on every tick.
    func refresh(now: Date = Date()) {
        let install = installDate(creatingAt: now)
        let lastSeen = defaults.object(forKey: "trialLastSeen") as? Date ?? now
        if now > lastSeen { defaults.set(now, forKey: "trialLastSeen") }
        let unlocked = !UnlockSecret.hashHex.isEmpty && defaults.string(forKey: "unlockToken") == UnlockSecret.hashHex
        state = TrialClock.state(installDate: install, lastSeen: lastSeen, now: now, unlocked: unlocked)
        if ProcessInfo.processInfo.environment["SIROCCO_TRIAL"] == "expired" { state = .expired }   // debug: preview the locked UI
    }

    /// Returns false on a wrong password. On success the app is unlocked on this Mac for good.
    func unlock(password: String) -> Bool {
        guard Unlock.verify(password: password) else { return false }
        defaults.set(UnlockSecret.hashHex, forKey: "unlockToken")
        refresh()
        return true
    }

    private func installDate(creatingAt now: Date) -> Date {
        var candidates: [Date] = []
        if let stored = defaults.object(forKey: "trialInstallDate") as? Date { candidates.append(stored) }
        if let text = try? String(contentsOf: markerURL, encoding: .utf8), let seconds = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            candidates.append(Date(timeIntervalSince1970: seconds))
        }
        let install = candidates.min() ?? now
        if candidates.count < 2 || candidates.min() != candidates.max() {   // heal the missing/late copy
            defaults.set(install, forKey: "trialInstallDate")
            try? String(install.timeIntervalSince1970).write(to: markerURL, atomically: true, encoding: .utf8)
        }
        return install
    }
}
