import CShims

/// Enumerates processes with one `sysctl(KERN_PROC_ALL)` call and reads per-process
/// counters with `proc_pid_rusage`. Owns a reusable buffer: no allocation per tick once
/// the process count has stabilised. Not thread-safe by design — owned by the `Sampler` actor.
final class ProcessEnumerator {
    private var buffer: UnsafeMutableRawPointer
    private var capacity: Int

    init() {
        capacity = 1024 * MemoryLayout<kinfo_proc>.stride
        buffer = .allocate(byteCount: capacity, alignment: MemoryLayout<kinfo_proc>.alignment)
    }

    deinit { buffer.deallocate() }

    /// Static + cumulative facts for every readable, non-zombie process.
    func snapshot(includeThreads: Bool = false) -> [ProcessCounters] {
        guard let count = fillBuffer() else { return [] }
        var result: [ProcessCounters] = []
        result.reserveCapacity(count)
        let stride = MemoryLayout<kinfo_proc>.stride
        for i in 0..<count {
            let info = buffer.load(fromByteOffset: i * stride, as: kinfo_proc.self)
            guard Int32(info.kp_proc.p_stat) != SZOMB else { continue }
            let pid = info.kp_proc.p_pid
            guard let usage = Self.rusage(pid: pid) else { continue }   // gone, or not readable
            let command = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            result.append(ProcessCounters(
                id: ProcessID(pid: pid, startTime: usage.ri_proc_start_abstime),
                parentPID: info.kp_eproc.e_ppid,
                uid: info.kp_eproc.e_ucred.cr_uid,
                command: command,
                userTimeNs: MachTime.nanoseconds(fromAbsolute: usage.ri_user_time),
                systemTimeNs: MachTime.nanoseconds(fromAbsolute: usage.ri_system_time),
                packageIdleWakeups: usage.ri_pkg_idle_wkups,
                interruptWakeups: usage.ri_interrupt_wkups,
                diskBytesRead: usage.ri_diskio_bytesread,
                diskBytesWritten: usage.ri_diskio_byteswritten,
                physFootprintBytes: usage.ri_phys_footprint,
                residentBytes: usage.ri_resident_size,
                threadCount: includeThreads ? Self.threadCount(pid: pid) : nil))
        }
        return result
    }

    /// Returns the number of `kinfo_proc` entries now in `buffer`, growing it on ENOMEM.
    private func fillBuffer() -> Int? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        for _ in 0..<4 {
            var size = capacity
            if sysctl(&mib, u_int(mib.count), buffer, &size, nil, 0) == 0 {
                return size / MemoryLayout<kinfo_proc>.stride
            }
            guard errno == ENOMEM else { return nil }
            buffer.deallocate()
            capacity *= 2
            buffer = .allocate(byteCount: capacity, alignment: MemoryLayout<kinfo_proc>.alignment)
        }
        return nil
    }

    static func rusage(pid: Int32) -> rusage_info_v4? {
        var info = rusage_info_v4()
        // libproc quirk: `rusage_info_t` is `void *`, so the parameter type is `void **`, but the
        // kernel writes the *struct* at that address. C callers cast `&info` to `rusage_info_t *`;
        // we must do the same reinterpretation. Passing a pointer to a pointer smashes the stack.
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self))
        }
        return result == 0 ? info : nil
    }

    /// `PROC_PIDTASKINFO` is only readable for our own processes (EPERM otherwise) → nil.
    static func threadCount(pid: Int32) -> Int? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let written = withUnsafeMutablePointer(to: &info) { proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, size) }
        return written == size ? Int(info.pti_threadnum) : nil
    }

    static func isAlive(pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Full executable path, or nil.
    static func path(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))   // PROC_PIDPATHINFO_MAXSIZE, a macro Swift cannot import
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
    }

    /// Responsible pid (Chrome for a Chrome Helper), or nil when unknown / self.
    static func responsiblePID(for pid: Int32) -> Int32? {
        let responsible = responsibility_get_pid_responsible_for_pid(pid)
        return responsible > 0 && responsible != pid ? responsible : nil
    }
}
