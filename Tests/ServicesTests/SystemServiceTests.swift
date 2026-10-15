import Testing
@testable import Services

@Suite struct CPUTicksTests {
    @Test func usageIsTheBusyShareOfTheInterval() {
        let before = CPUTicks(user: 100, system: 50, nice: 0, idle: 850)
        let after = CPUTicks(user: 160, system: 70, nice: 20, idle: 1000)
        #expect(after.usage(since: before) == 100.0 / 250.0)
    }

    @Test func noElapsedTicksReadsAsIdle() {
        let ticks = CPUTicks(user: 1, system: 1, nice: 1, idle: 1)
        #expect(ticks.usage(since: ticks) == 0)
    }

    @Test func liveSamplesStayInRange() throws {
        let first = try #require(CPUTicks.now())
        let second = try #require(CPUTicks.now())
        let usage = second.usage(since: first)
        #expect(usage >= 0 && usage <= 1)
    }
}
