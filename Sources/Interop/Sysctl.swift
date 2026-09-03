import CShims

/// Typed `sysctlbyname` reads. Only fixed-size integers and one struct are needed.
enum Sysctl {
    static func integer(_ name: String) -> Int64? {
        var buffer: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        switch size {
        case 4: return Int64(Int32(truncatingIfNeeded: buffer))
        case 8: return Int64(bitPattern: buffer)
        default: return nil
        }
    }

    static func swapUsage() -> (used: UInt64, total: UInt64)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return (usage.xsu_used, usage.xsu_total)
    }

    static func coreTopology() -> CoreTopology {
        let logical = Int(integer("hw.logicalcpu") ?? 0)
        // perflevel0 = Performance, perflevel1 = Efficiency. Missing on Intel → 0 E cores.
        let efficiency = Int(integer("hw.perflevel1.logicalcpu") ?? 0)
        return CoreTopology(logicalCount: logical, efficiencyCoreCount: min(efficiency, logical))
    }

    static func physicalMemory() -> UInt64 {
        UInt64(integer("hw.memsize") ?? 0)
    }

    static func memoryPressure() -> MemoryPressure {
        MemoryPressure(rawValue: Int(integer("kern.memorystatus_vm_pressure_level") ?? 1)) ?? .normal
    }
}
