import Darwin
import Foundation
import StatusNavCore

enum ApplicationActivityReader {
    static func read(applications: [ApplicationIdentity]) -> [ProcessSample] {
        let count = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: min(16_384, Int(count) / MemoryLayout<pid_t>.size + 128))
        let returned = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_UID_ONLY), getuid(), $0.baseAddress, Int32($0.count))
        }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanosecondsPerTick = Double(timebase.numer) / Double(max(1, timebase.denom))
        let identities = applications.sorted { $0.path.count < $1.path.count }
        var result: [ProcessSample] = []
        for pid in pids.prefix(max(0, min(pids.count, Int(returned) / MemoryLayout<pid_t>.size))) where pid > 0 {
            var name = [CChar](repeating: 0, count: 4_096)
            guard proc_pidpath(pid, &name, UInt32(name.count)) > 0 else { continue }
            let path = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard let app = identities.first(where: { path.hasPrefix($0.path + "/") }) else { continue }
            var usage = rusage_info_v6()
            let status = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            }
            if status == 0 {
                result.append(ProcessSample(pid: pid, started: usage.ri_proc_start_abstime, app: app,
                    cpuNanoseconds: (Double(usage.ri_user_time) + Double(usage.ri_system_time)) * nanosecondsPerTick,
                    energyNanojoules: usage.ri_energy_nj > 0 ? usage.ri_energy_nj : nil,
                    memoryBytes: usage.ri_phys_footprint))
            } else {
                var fallback = rusage_info_v4()
                let read = withUnsafeMutablePointer(to: &fallback) {
                    $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
                }
                if read == 0 {
                    result.append(ProcessSample(pid: pid, started: fallback.ri_proc_start_abstime, app: app,
                        cpuNanoseconds: (Double(fallback.ri_user_time) + Double(fallback.ri_system_time)) * nanosecondsPerTick,
                        energyNanojoules: nil, memoryBytes: fallback.ri_phys_footprint))
                }
            }
        }
        return result
    }
}
