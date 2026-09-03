import CShims

/// Host-wide mach statistics: per-core ticks and VM counters.
enum MachHost {
    static func cpuTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { core in
            let base = core * stride
            return CPUTicks(user: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])),
                            system: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])),
                            idle: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])),
                            nice: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])))
        }
    }

    static func memoryLoad(totalBytes: UInt64) -> MemoryLoad? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(sysconf(_SC_PAGESIZE))
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let swap = Sysctl.swapUsage()
        return MemoryLoad(
            totalBytes: totalBytes,
            appBytes: (internalPages > purgeable ? internalPages - purgeable : 0) * page,
            wiredBytes: UInt64(stats.wire_count) * page,
            compressedBytes: UInt64(stats.compressor_page_count) * page,
            cachedFilesBytes: (UInt64(stats.external_page_count) + purgeable) * page,
            swapUsedBytes: swap?.used ?? 0,
            swapTotalBytes: swap?.total ?? 0,
            pressure: Sysctl.memoryPressure())
    }
}
