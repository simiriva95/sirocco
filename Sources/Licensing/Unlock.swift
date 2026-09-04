import CommonCrypto
import Foundation

enum Unlock {
    /// Hex PBKDF2-HMAC-SHA256 (32 bytes). Same parameters as Tools/unlock-hash.swift.
    static func derive(password: String, salt: String = UnlockSecret.salt, iterations: UInt32 = UnlockSecret.iterations) -> String {
        var key = [UInt8](repeating: 0, count: 32)
        let passwordBytes = Array(password.utf8)
        let saltBytes = Array(salt.utf8)
        let status = passwordBytes.withUnsafeBufferPointer { pass in
            saltBytes.withUnsafeBufferPointer { salt in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self) }, pass.count,
                                     salt.baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &key, key.count)
            }
        }
        guard status == kCCSuccess else { return "" }
        return key.map { String(format: "%02x", $0) }.joined()
    }

    /// Constant-time comparison against the embedded hash; an empty embedded hash never matches.
    static func verify(password: String, expectedHex: String = UnlockSecret.hashHex) -> Bool {
        guard !expectedHex.isEmpty else { return false }
        let candidate = Array(derive(password: password).utf8)
        let expected = Array(expectedHex.utf8)
        guard candidate.count == expected.count else { return false }
        return zip(candidate, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
