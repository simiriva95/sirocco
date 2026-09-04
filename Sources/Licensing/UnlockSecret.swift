/// PBKDF2-HMAC-SHA256 hash of the owner's unlock password. Generated locally with
/// `make unlock-hash` — the password itself never touches the repository or the assistant.
/// An empty hash means nobody can unlock (trial only).
enum UnlockSecret {
    static let salt = "sirocco.v1.7f3c9a2e5b1d"
    static let iterations: UInt32 = 200_000
    static let hashHex = ""
}
