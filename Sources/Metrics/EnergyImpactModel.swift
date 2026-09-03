/// THE energy impact formula. One place, versioned. Changing a coefficient is a changelog line.
///
/// Activity Monitor's "Energy Impact" is a composite of CPU time, idle wakeups, GPU time and
/// QoS. GPU time and QoS per process are not readable through public API, so this model
/// covers CPU, wakeups and disk I/O only — see README "Energy impact".
///
/// Scale: 100 == one core saturated with no other activity.
struct EnergyImpactModel: Equatable, Sendable {
    let version: Int
    /// Points per package idle wakeup per second. A package wakeup pulls the whole SoC
    /// out of a low-power state; 200 wakeups/s ≈ one busy core.
    let packageIdleWakeupWeight: Double
    /// Points per interrupt wakeup per second (cheaper than package wakeups).
    let interruptWakeupWeight: Double
    /// Points per MB/s of disk I/O (read + write).
    let diskMegabyteWeight: Double

    func score(_ p: ProcessSample) -> Double {
        let cpu = p.cpuFraction * 100
        let wakeups = p.packageIdleWakeupsPerSecond * packageIdleWakeupWeight
            + p.interruptWakeupsPerSecond * interruptWakeupWeight
        let disk = (p.diskReadBytesPerSecond + p.diskWriteBytesPerSecond) / 1_048_576 * diskMegabyteWeight
        return cpu + wakeups + disk
    }

    static let v1 = EnergyImpactModel(version: 1, packageIdleWakeupWeight: 0.5,
                                      interruptWakeupWeight: 0.05, diskMegabyteWeight: 0.5)
    static let current = v1
}
