import CShims
import Foundation
import IOKit

/// AppleSMC user client: fans, power rails, a few temperatures. Works unprivileged on Apple
/// Silicon; keys are undocumented and per-model, so every read may return nil.
final class SMCSource: SensorSource {
    let sourceName = "SMC"
    private var connection: io_connect_t = 0
    private var fanCount = 0

    private static let handleYPCEvent: UInt32 = 2
    private static let cmdReadKey: UInt8 = 5
    private static let cmdGetKeyInfo: UInt8 = 9

    deinit { if connection != 0 { IOServiceClose(connection) } }

    func probe() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return false }
        fanCount = Int(readNumber("FNum") ?? 0)
        return readNumber("PSTR") != nil || fanCount > 0
    }

    func read() -> [SensorReading] {
        var result: [SensorReading] = []
        for fan in 0..<fanCount {
            if let rpm = readNumber("F\(fan)Ac") {
                result.append(SensorReading(id: "smc:F\(fan)Ac", name: String(localized: "Fan \(fan + 1)"), kind: .fanRPM, value: rpm))
            }
        }
        let power: [(String, String)] = [("PSTR", String(localized: "System power")), ("PDTR", String(localized: "Adapter power")),
                                         ("PPBR", String(localized: "Battery power"))]
        for (key, name) in power {
            if let watts = readNumber(key) { result.append(SensorReading(id: "smc:\(key)", name: name, kind: .power, value: watts)) }
        }
        for key in ["Tg05", "Tg0f", "TG0P"] {   // GPU die on recent chips; missing keys are fine
            if let celsius = readNumber(key) {
                result.append(SensorReading(id: "smc:\(key)", name: "GPU \(key)", kind: .temperature, value: celsius))
                break
            }
        }
        return result
    }

    /// Fan speed limits, when the SMC exposes them.
    func fanLimits(_ fan: Int) -> (min: Double, max: Double)? {
        guard let min = readNumber("F\(fan)Mn"), let max = readNumber("F\(fan)Mx") else { return nil }
        return (min, max)
    }

    // MARK: Wire protocol

    private func readNumber(_ key: String) -> Double? {
        guard let (type, bytes) = readRaw(key) else { return nil }
        return SMCValue.decode(type: type, bytes: bytes)
    }

    private func readRaw(_ key: String) -> (type: String, bytes: [UInt8])? {
        var query = SMCKeyData()
        query.key = SMCValue.code(key)
        query.data8 = Self.cmdGetKeyInfo
        guard let info = call(query), info.result == 0, info.keyInfo.dataSize > 0, info.keyInfo.dataSize <= 32 else { return nil }
        var request = SMCKeyData()
        request.key = query.key
        request.keyInfo = info.keyInfo
        request.data8 = Self.cmdReadKey
        guard let value = call(request), value.result == 0 else { return nil }
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0.prefix(Int(info.keyInfo.dataSize))) }
        return (SMCValue.string(info.keyInfo.dataType), bytes)
    }

    private func call(_ input: SMCKeyData) -> SMCKeyData? {
        var input = input
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.size
        let result = IOConnectCallStructMethod(connection, Self.handleYPCEvent, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize)
        return result == KERN_SUCCESS ? output : nil
    }
}

/// Pure decoding of SMC payloads — the part worth a unit test.
enum SMCValue {
    static func code(_ key: String) -> UInt32 { key.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    static func string(_ code: UInt32) -> String {
        String(bytes: [UInt8(code >> 24), UInt8(code >> 16 & 0xff), UInt8(code >> 8 & 0xff), UInt8(code & 0xff)], encoding: .ascii) ?? "????"
    }

    static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt " where bytes.count == 4:
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })   // little-endian float
        case "ui8 " where bytes.count == 1: return Double(bytes[0])
        case "ui16" where bytes.count == 2: return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count == 4: return Double(bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        case "fpe2" where bytes.count == 2: return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4     // Intel fans
        case "sp78" where bytes.count == 2: return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256   // Intel temps
        default: return nil
        }
    }
}
