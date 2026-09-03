/// Phase 2 will gate some features behind a paid license (14-day trial, one-time purchase).
/// Nothing is gated today, but every future gate goes through this protocol so licensing
/// becomes an implementation swap, not a refactor.
enum GatedFeature: Sendable {
    case performanceHistory   // 5/15-minute windows
    case sensors
    case startupItems
}

protocol LicenseGating: Sendable {
    func isUnlocked(_ feature: GatedFeature) -> Bool
}

struct AlwaysUnlocked: LicenseGating {
    func isUnlocked(_ feature: GatedFeature) -> Bool { true }
}
