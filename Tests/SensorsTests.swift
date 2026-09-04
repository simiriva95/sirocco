import XCTest
@testable import Sirocco

final class SensorsTests: XCTestCase {
    func testSMCDecoding() {
        XCTAssertEqual(SMCValue.decode(type: "flt ", bytes: [0x00, 0x00, 0x2d, 0x41])!, 10.8125, accuracy: 1e-6)   // 0x412d0000 LE
        XCTAssertEqual(SMCValue.decode(type: "ui8 ", bytes: [2]), 2)
        XCTAssertEqual(SMCValue.decode(type: "ui16", bytes: [0x09, 0x0c]), 2316)
        XCTAssertEqual(SMCValue.decode(type: "fpe2", bytes: [0x24, 0x40]), 2320)
        XCTAssertNil(SMCValue.decode(type: "flt ", bytes: [1, 2]), "wrong length → nil, never garbage")
        XCTAssertEqual(SMCValue.string(SMCValue.code("PSTR")), "PSTR")
    }

    func testClassifierGroupsVendorNamesAndDropsGarbage() {
        let readings = [
            SensorReading(id: "hid:PMU tdie3", name: "PMU tdie3", kind: .temperature, value: 41.6),
            SensorReading(id: "hid:PMU tdie3", name: "PMU tdie3", kind: .temperature, value: 42.9),   // same die, 3 PMUs → keep hottest
            SensorReading(id: "hid:PMU tdev1", name: "PMU tdev1", kind: .temperature, value: -9201.1),
            SensorReading(id: "hid:NAND CH0 temp", name: "NAND CH0 temp", kind: .temperature, value: 35),
            SensorReading(id: "hid:gas gauge battery", name: "gas gauge battery", kind: .temperature, value: 33),
            SensorReading(id: "smc:Tg05", name: "GPU Tg05", kind: .temperature, value: 48),
            SensorReading(id: "smc:F0Ac", name: "Fan 1", kind: .fanRPM, value: 0),
        ]
        let cleaned = SensorClassifier.clean(readings)
        XCTAssertEqual(cleaned.count, 5)
        XCTAssertEqual(cleaned.first { $0.id == "hid:PMU tdie3" }?.value, 42.9)
        XCTAssertNil(cleaned.first { $0.id == "hid:PMU tdev1" })
        XCTAssertEqual(SensorClassifier.summary(.cpu, in: cleaned), 42.9)
        XCTAssertEqual(SensorClassifier.summary(.gpu, in: cleaned), 48)
        XCTAssertEqual(SensorClassifier.summary(.ssd, in: cleaned), 35)
        XCTAssertEqual(SensorClassifier.group(forTemperatureNamed: "pACC MTR Temp Sensor0"), .cpu, "M1 naming")
    }

    func testBatteryDerivation() {
        let status = BatteryStatus.derive(currentRaw: 5164, maxRaw: 5972, designCapacity: 6249, currentPercent: 91, cycleCount: 130,
                                          isCharging: false, externalConnected: false, voltageMillivolts: 12682, amperageMilliamps: -841,
                                          timeRemaining: 419, temperatureRaw: 3062)
        XCTAssertEqual(status.chargePercent, 86.47, accuracy: 0.01)
        XCTAssertEqual(status.healthPercent!, 95.57, accuracy: 0.01)
        XCTAssertEqual(status.watts, -10.666, accuracy: 0.001)
        XCTAssertEqual(status.minutesRemaining, 419)
        XCTAssertEqual(status.temperatureCelsius!, 30.62, accuracy: 0.001)
        XCTAssertNil(BatteryStatus.derive(currentRaw: nil, maxRaw: nil, designCapacity: nil, currentPercent: 50, cycleCount: 0, isCharging: true,
                                          externalConnected: true, voltageMillivolts: 0, amperageMilliamps: 0, timeRemaining: 65535, temperatureRaw: nil).minutesRemaining)
    }
}
