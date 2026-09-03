import Foundation

/// Immutable result of one sampling tick. Both surfaces read the same value.
struct SystemSnapshot: Sendable {
    var timestamp: Date
    var cpu: CPULoad?                      // nil on the very first tick (no delta yet)
    var memory: MemoryLoad
    var thermalState: ProcessInfo.ThermalState
    var processes: [ProcessSample]?        // nil when nobody is looking at processes
    var responsiblePIDs: [Int32: Int32]    // pid → responsible pid, only for helpers
}
