import Foundation

/// uid → login name via `getpwuid`, cached forever (uids do not change while we run).
final class UserNames: @unchecked Sendable {
    private var cache: [UInt32: String] = [:]
    private let lock = NSLock()

    func name(for uid: UInt32) -> String {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[uid] { return cached }
        let name = getpwuid(uid).flatMap { $0.pointee.pw_name }.map { String(cString: $0) } ?? String(uid)
        cache[uid] = name
        return name
    }
}
