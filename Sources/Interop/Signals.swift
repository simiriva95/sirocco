import CShims

enum Signals {
    enum Failure: Equatable, Sendable {
        case notPermitted     // EPERM: another user's or SIP-protected process
        case noSuchProcess    // ESRCH
        case other(Int32)
    }

    static func terminate(pid: Int32) -> Failure? { send(SIGTERM, to: pid) }
    static func forceKill(pid: Int32) -> Failure? { send(SIGKILL, to: pid) }

    private static func send(_ signal: Int32, to pid: Int32) -> Failure? {
        guard kill(pid, signal) != 0 else { return nil }
        switch errno {
        case EPERM: return .notPermitted
        case ESRCH: return .noSuchProcess
        case let code: return .other(code)
        }
    }
}
