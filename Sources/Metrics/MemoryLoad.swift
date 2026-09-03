/// System memory the way Activity Monitor reports it. `total - free` is meaningless on
/// macOS (the kernel deliberately fills RAM with file cache), so "used" is
/// app + wired + compressed, with app = internal pages − purgeable pages.
struct MemoryLoad: Equatable, Sendable {
    var totalBytes: UInt64
    var appBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var cachedFilesBytes: UInt64
    var swapUsedBytes: UInt64
    var swapTotalBytes: UInt64
    var pressure: MemoryPressure

    var usedBytes: UInt64 { appBytes &+ wiredBytes &+ compressedBytes }
    var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }

    static let zero = MemoryLoad(totalBytes: 0, appBytes: 0, wiredBytes: 0, compressedBytes: 0,
                                 cachedFilesBytes: 0, swapUsedBytes: 0, swapTotalBytes: 0, pressure: .normal)
}

/// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4
}
