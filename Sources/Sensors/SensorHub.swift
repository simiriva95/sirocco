import Foundation

/// Owns the sensor sources, probes them once, reads on demand. Lives inside the Sampler actor.
final class SensorHub {
    private var sources: [any SensorSource] = []
    private var probed = false

    private func probeIfNeeded() {
        guard !probed else { return }
        probed = true
        for candidate: any SensorSource in [HIDTemperatureSource(), SMCSource()] where candidate.probe() {
            sources.append(candidate)
        }
    }

    func read(at timestamp: Date) -> SensorSnapshot {
        probeIfNeeded()
        let readings = SensorClassifier.clean(sources.flatMap { $0.read() })
        let smc = sources.first { $0 is SMCSource } as? SMCSource
        let limits = Dictionary(uniqueKeysWithValues: readings.filter { $0.kind == .fanRPM }.enumerated().compactMap { index, fan in
            smc?.fanLimits(index).map { (fan.id, FanLimits(min: $0.min, max: $0.max)) }
        })
        return SensorSnapshot(timestamp: timestamp, readings: readings, battery: BatterySource.read(),
                              fanLimits: limits, availableSources: sources.map(\.sourceName))
    }
}
