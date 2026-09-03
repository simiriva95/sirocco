import CShims

/// `proc_pid_rusage` times are in mach absolute time units. On Intel that was 1 ns per tick;
/// on Apple Silicon the timebase is 125/3 (24 MHz), so forgetting this makes every CPU
/// percentage ~42× too small. Converted once, here.
enum MachTime {
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    static func nanoseconds(fromAbsolute ticks: UInt64) -> UInt64 {
        timebase.numer == timebase.denom ? ticks : ticks * timebase.numer / timebase.denom
    }
}
