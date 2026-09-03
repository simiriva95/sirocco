/// Decides whether a process may be signalled at all. Not bypassable from the UI:
/// every kill path goes through `denial(for:)` before touching `kill(2)`.
struct TerminationPolicy: Sendable {
    let ownPID: Int32
    let currentUID: UInt32

    static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "coreaudiod", "backupd",
    ]
    static let protectedPrefixes: [String] = ["mds", "mdworker"]   // mds, mds_stores, mdworker_shared, mdsync…

    enum Denial: Equatable, Sendable {
        case systemCritical      // blocklisted name or pid ≤ 1
        case ownProcess
        case otherUser           // kill(2) would return EPERM; we know it upfront
    }

    func denial(pid: Int32, command: String, uid: UInt32) -> Denial? {
        if pid == ownPID { return .ownProcess }
        if pid <= 1 || Self.protectedNames.contains(command) { return .systemCritical }
        if Self.protectedPrefixes.contains(where: { command.hasPrefix($0) }) { return .systemCritical }
        if uid != currentUID && currentUID != 0 { return .otherUser }
        return nil
    }
}
