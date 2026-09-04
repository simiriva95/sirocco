import Foundation

/// Phase-1 licensing: a 14-day trial for everyone, full access with the owner's password.
/// Deterrent, not DRM — the source is private, the hash is salted PBKDF2, and that is the
/// honest extent of it. Paid licensing (merchant of record) plugs into the same protocol later.
enum LicenseState: Equatable, Sendable {
    case trial(daysLeft: Int)
    case expired
    case unlocked
}

protocol LicenseGating: Sendable {
    func isUnlocked(_ feature: GatedFeature) -> Bool
}

enum GatedFeature: Sendable {
    case everything   // phase 1 gates the whole app after the trial
}

/// Pure trial arithmetic. `lastSeen` defeats the obvious "set the clock back" trick: the
/// effective now never moves backwards.
enum TrialClock {
    static let trialDays = 14

    static func state(installDate: Date, lastSeen: Date, now: Date, unlocked: Bool) -> LicenseState {
        if unlocked { return .unlocked }
        let effectiveNow = max(now, lastSeen)
        let elapsedDays = Int(effectiveNow.timeIntervalSince(installDate) / 86_400)
        let left = trialDays - elapsedDays
        return left > 0 ? .trial(daysLeft: left) : .expired
    }
}
