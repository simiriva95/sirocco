// Generates Sources/Licensing/UnlockSecret.swift from a password typed locally.
// Usage: swift Tools/unlock-hash.swift   (run from the repository root)
import CommonCrypto
import Foundation

let salt = "sirocco.v1.7f3c9a2e5b1d"
let iterations: UInt32 = 200_000

func derive(_ password: String) -> String {
    var key = [UInt8](repeating: 0, count: 32)
    let pass = Array(password.utf8), saltBytes = Array(salt.utf8)
    let status = pass.withUnsafeBufferPointer { p in saltBytes.withUnsafeBufferPointer { s in
        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self) }, p.count,
                             s.baseAddress, s.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &key, key.count) } }
    precondition(status == kCCSuccess)
    return key.map { String(format: "%02x", $0) }.joined()
}

guard let first = getpass("Unlock password: "), let second = getpass("Repeat: ") else { exit(1) }
let a = String(cString: first), b = String(cString: second)
guard a == b else { print("Passwords differ."); exit(1) }
guard a.count >= 12 else { print("Use at least 12 characters: the hash is only as strong as the password."); exit(1) }
let source = """
/// PBKDF2-HMAC-SHA256 hash of the owner's unlock password. Generated locally with
/// `make unlock-hash` — the password itself never touches the repository or the assistant.
/// An empty hash means nobody can unlock (trial only).
enum UnlockSecret {
    static let salt = "\(salt)"
    static let iterations: UInt32 = \(iterations)
    static let hashHex = "\(derive(a))"
}

"""
try source.write(toFile: "Sources/Licensing/UnlockSecret.swift", atomically: true, encoding: .utf8)
print("Written Sources/Licensing/UnlockSecret.swift (git-ignored). Rebuild with `make build` or `make release`.")
