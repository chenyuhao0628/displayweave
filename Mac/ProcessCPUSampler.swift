import Foundation
import Darwin

/// Process user + system CPU seconds / monotonic wall seconds. 100% = one core.
/// Owned by the benchmark's serial queue; never substitutes zero for missing data.
struct ProcessCPUSampler {
    private var previous: (cpu: Double, uptime: Double)?
    mutating func reset() { previous = nil }

    mutating func sample(cpuSeconds: Double?, uptime: Double) -> Double? {
        guard let cpuSeconds, cpuSeconds.isFinite, cpuSeconds >= 0,
              uptime.isFinite, uptime >= 0 else { reset(); return nil }
        let old = previous
        previous = (cpuSeconds, uptime)
        guard let old, uptime > old.uptime, cpuSeconds >= old.cpu else { return nil }
        let percent = (cpuSeconds - old.cpu) / (uptime - old.uptime) * 100
        return percent.isFinite ? percent : nil
    }

    mutating func sample() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { reset(); return nil }
        let seconds = Double(usage.ru_utime.tv_sec) + Double(usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        return sample(cpuSeconds: seconds, uptime: ProcessInfo.processInfo.systemUptime)
    }
}
