import Foundation

/// Cumulative counter → per-second rate. `if_data` byte counters are `u_int32` and wrap every
/// 4 GB, so the width is a parameter: a wrap must not read as a negative burst.
enum CounterRate {
    static func perSecond(now: UInt64, previous: UInt64, elapsed: Double, bits: Int = 64) -> Double {
        guard elapsed > 0 else { return 0 }
        let delta: UInt64
        if now >= previous { delta = now - previous }
        else if bits < 64 { delta = (UInt64(1) << UInt64(bits)) - previous + now }
        else { return 0 }   // counter reset (device unplugged/replugged): skip this interval
        return Double(delta) / elapsed
    }
}

struct DiskCounters: Equatable, Sendable {
    var bytesRead: UInt64
    var bytesWritten: UInt64
}

struct InterfaceCounters: Equatable, Sendable {
    var name: String
    var received: UInt64
    var sent: UInt64
}

struct DiskThroughput: Equatable, Sendable {
    var readBytesPerSecond: Double
    var writeBytesPerSecond: Double
    static let zero = DiskThroughput(readBytesPerSecond: 0, writeBytesPerSecond: 0)
}

struct InterfaceThroughput: Equatable, Sendable, Identifiable {
    var name: String
    var receivedBytesPerSecond: Double
    var sentBytesPerSecond: Double
    var id: String { name }
    var total: Double { receivedBytesPerSecond + sentBytesPerSecond }
}

/// Owns the previous counters; pure apart from that.
struct ThroughputTracker: Sendable {
    private var previousDisk: DiskCounters?
    private var previousInterfaces: [String: InterfaceCounters] = [:]

    mutating func update(disk: DiskCounters?, interfaces: [InterfaceCounters], elapsed: Double)
        -> (disk: DiskThroughput?, network: [InterfaceThroughput]) {
        defer {
            previousDisk = disk
            previousInterfaces = Dictionary(uniqueKeysWithValues: interfaces.map { ($0.name, $0) })
        }
        var diskRate: DiskThroughput?
        if let disk, let before = previousDisk {
            diskRate = DiskThroughput(
                readBytesPerSecond: CounterRate.perSecond(now: disk.bytesRead, previous: before.bytesRead, elapsed: elapsed),
                writeBytesPerSecond: CounterRate.perSecond(now: disk.bytesWritten, previous: before.bytesWritten, elapsed: elapsed))
        }
        let network = interfaces.compactMap { now -> InterfaceThroughput? in
            guard let before = previousInterfaces[now.name] else { return nil }
            return InterfaceThroughput(
                name: now.name,
                receivedBytesPerSecond: CounterRate.perSecond(now: now.received, previous: before.received, elapsed: elapsed, bits: 32),
                sentBytesPerSecond: CounterRate.perSecond(now: now.sent, previous: before.sent, elapsed: elapsed, bits: 32))
        }
        return (diskRate, network)
    }
}

/// One aligned sample of everything the Performance tab plots. Fixed-size history in the store.
struct PerformanceSample: Sendable {
    var timestamp: Date
    var cpu: CPULoad
    var memory: MemoryLoad
    var disk: DiskThroughput
    var network: [InterfaceThroughput]
    var thermalLevel: Int
}
