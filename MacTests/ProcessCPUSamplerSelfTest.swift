import Foundation

@main enum ProcessCPUSamplerSelfTest {
    static func main() {
        var sampler = ProcessCPUSampler()
        precondition(sampler.sample(cpuSeconds: 10, uptime: 100) == nil)
        precondition(sampler.sample(cpuSeconds: 10.5, uptime: 101) == 50)
        precondition(sampler.sample(cpuSeconds: 12.5, uptime: 102) == 200,
                     "one fully occupied core is 100%; process totals can exceed it")
        precondition(sampler.sample(cpuSeconds: 12.5, uptime: 103) == 0)
        precondition(sampler.sample(cpuSeconds: 13, uptime: 103) == nil)
        precondition(sampler.sample(cpuSeconds: 1, uptime: 104) == nil)
        precondition(sampler.sample(cpuSeconds: .nan, uptime: 105) == nil)
        precondition(sampler.sample(cpuSeconds: 2, uptime: 106) == nil)
        precondition(sampler.sample(cpuSeconds: nil, uptime: 107) == nil)
        precondition(sampler.sample(cpuSeconds: 3, uptime: 108) == nil)
        sampler.reset()
        precondition(sampler.sample() == nil)
        Thread.sleep(forTimeInterval: 0.02)
        let actual = sampler.sample()
        precondition(actual != nil && actual!.isFinite && actual! >= 0)
        print("Process CPU interval, multi-core units, invalid/reset and getrusage sampling PASS")
    }
}
