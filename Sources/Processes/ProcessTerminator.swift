import Foundation
import Observation

/// SIGTERM first, explicit escalation to SIGKILL. Every path checks `TerminationPolicy`.
@MainActor @Observable
final class ProcessTerminator {
    enum Outcome: Equatable, Sendable {
        case signalled
        case denied(TerminationPolicy.Denial)
        case failed(Signals.Failure)
    }

    static let escalationDelay: TimeInterval = 3

    let policy = TerminationPolicy(ownPID: getpid(), currentUID: getuid())
    /// pid → when SIGTERM was sent. Cleared when the pid disappears or after SIGKILL.
    private(set) var pendingTermination: [Int32: Date] = [:]

    func terminate(_ sample: ProcessSample) -> Outcome {
        if let denial = policy.denial(pid: sample.pid, command: sample.command, uid: sample.uid) {
            return .denied(denial)
        }
        if let failure = Signals.terminate(pid: sample.pid) { return .failed(failure) }
        pendingTermination[sample.pid] = Date()
        return .signalled
    }

    func forceKill(_ sample: ProcessSample) -> Outcome {
        if let denial = policy.denial(pid: sample.pid, command: sample.command, uid: sample.uid) {
            return .denied(denial)
        }
        pendingTermination[sample.pid] = nil
        if let failure = Signals.forceKill(pid: sample.pid) { return .failed(failure) }
        return .signalled
    }

    /// True when SIGTERM was sent long enough ago that offering SIGKILL is reasonable.
    func canEscalate(pid: Int32, now: Date = Date()) -> Bool {
        guard let sent = pendingTermination[pid] else { return false }
        return now.timeIntervalSince(sent) >= Self.escalationDelay
    }

    func forget(deadPIDs: (Int32) -> Bool) {
        pendingTermination = pendingTermination.filter { !deadPIDs($0.key) }
    }
}
