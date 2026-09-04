import Foundation

enum SensorKind: Sendable, Hashable { case temperature, fanRPM, power }

/// One reading. `id` is stable across ticks (e.g. "hid:PMU tdie3", "smc:F0Ac").
struct SensorReading: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var kind: SensorKind
    var value: Double
}

/// A source that may legitimately be unavailable on a given Mac / macOS. `probe()` runs once;
/// a source that fails is simply skipped, the rest of the app never notices.
protocol SensorSource: AnyObject {
    var sourceName: String { get }
    func probe() -> Bool
    func read() -> [SensorReading]
}

/// What the Sensors tab shows: curated groups derived from raw readings, plus the raw list.
struct SensorSnapshot: Equatable, Sendable {
    var timestamp: Date
    var readings: [SensorReading]
    var battery: BatteryStatus?
    var fanLimits: [String: FanLimits] = [:]
    var availableSources: [String]

    var cpuDieCelsius: Double? { SensorClassifier.summary(.cpu, in: readings) }
    var gpuCelsius: Double? { SensorClassifier.summary(.gpu, in: readings) }
    var ssdCelsius: Double? { SensorClassifier.summary(.ssd, in: readings) }
    var fans: [SensorReading] { readings.filter { $0.kind == .fanRPM } }
    var systemPowerWatts: Double? { readings.first { $0.id == "smc:PSTR" }?.value }
    var adapterPowerWatts: Double? { readings.first { $0.id == "smc:PDTR" }?.value }
}

struct FanLimits: Equatable, Sendable { var min: Double; var max: Double }

struct BatteryStatus: Equatable, Sendable {
    var chargePercent: Double
    var healthPercent: Double?      // AppleRawMaxCapacity / DesignCapacity
    var cycleCount: Int
    var isCharging: Bool
    var externalPower: Bool
    var watts: Double               // negative while discharging
    var minutesRemaining: Int?      // nil when unknown (65535) or on AC and full
    var temperatureCelsius: Double?

    /// Pure derivation from the raw IORegistry numbers, so it can be tested with fixtures.
    static func derive(currentRaw: Int?, maxRaw: Int?, designCapacity: Int?, currentPercent: Int?,
                       cycleCount: Int, isCharging: Bool, externalConnected: Bool,
                       voltageMillivolts: Int, amperageMilliamps: Int, timeRemaining: Int?, temperatureRaw: Int?) -> BatteryStatus {
        let charge: Double
        if let currentRaw, let maxRaw, maxRaw > 0 { charge = Double(currentRaw) / Double(maxRaw) * 100 }
        else { charge = Double(currentPercent ?? 0) }
        var health: Double?
        if let maxRaw, let designCapacity, designCapacity > 0 { health = min(Double(maxRaw) / Double(designCapacity) * 100, 100) }
        let minutes: Int? = (timeRemaining ?? 65535) == 65535 ? nil : timeRemaining
        return BatteryStatus(chargePercent: charge, healthPercent: health, cycleCount: cycleCount, isCharging: isCharging,
                             externalPower: externalConnected, watts: Double(voltageMillivolts) * Double(amperageMilliamps) / 1_000_000,
                             minutesRemaining: minutes, temperatureCelsius: temperatureRaw.map { Double($0) / 100 })
    }
}

/// Maps vendor sensor names onto the few groups a human cares about. Names differ per chip
/// generation (M1: "pACC MTR Temp Sensor*", M3/M4: "PMU tdie*"), hence prefixes, not equality.
enum SensorClassifier {
    enum Group { case cpu, gpu, ssd, battery, other }

    static let validTemperatureRange = -40.0...150.0    // "PMU tdev*" report −9201 °C: garbage

    static func group(forTemperatureNamed name: String) -> Group {
        let lower = name.lowercased()
        if lower.contains("tdie") || lower.contains("pacc") || lower.contains("eacc") || lower.contains("soc") || lower.hasPrefix("tp") { return .cpu }
        if lower.contains("gpu") || lower.hasPrefix("tg") { return .gpu }
        if lower.contains("nand") || lower.contains("ssd") { return .ssd }
        if lower.contains("battery") || lower.contains("gas gauge") || lower.hasPrefix("tb") { return .battery }
        return .other
    }

    /// Hottest valid reading of the group: heat is about the worst spot, not the average.
    static func summary(_ group: Group, in readings: [SensorReading]) -> Double? {
        readings.lazy
            .filter { $0.kind == .temperature && Self.group(forTemperatureNamed: $0.name) == group && validTemperatureRange.contains($0.value) }
            .map(\.value).max()
    }

    /// De-duplicates repeated sensor names (the PMU reports each die sensor three times) keeping
    /// the hottest value, and drops out-of-range garbage.
    static func clean(_ readings: [SensorReading]) -> [SensorReading] {
        var best: [String: SensorReading] = [:]
        for r in readings {
            if r.kind == .temperature, !validTemperatureRange.contains(r.value) { continue }
            if let existing = best[r.id], existing.value >= r.value { continue }
            best[r.id] = r
        }
        return best.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
