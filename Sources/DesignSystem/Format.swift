import Foundation

/// Number formatting used by every surface. One switch for the unit system (Settings › Units).
@MainActor
enum Format {
    static var binaryUnits = true

    static func bytes(_ value: UInt64) -> String {
        value == 0 ? "0" : value.formatted(.byteCount(style: binaryUnits ? .memory : .file))   // not "Zero kB"
    }

    static func bytes(_ value: Double) -> String { bytes(UInt64(max(value, 0))) }

    static func rate(_ bytesPerSecond: Double) -> String {
        bytesPerSecond < 1 ? "0 B/s" : bytes(bytesPerSecond) + "/s"
    }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
    static func celsius(_ value: Double) -> String { String(format: "%.1f °C", value) }
    static func watts(_ value: Double) -> String { String(format: "%.1f W", value) }
}
