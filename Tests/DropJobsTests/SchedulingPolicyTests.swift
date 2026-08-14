import DropJobs
import Testing

@Test func suspendsWhenThermalStateIsSerious() {
    let state = PowerState(thermalState: .serious, isLowPowerModeEnabled: false, isOnACPower: true, batteryLevel: 1.0)
    #expect(SchedulingPolicy.shouldSuspend(state))
}

@Test func suspendsWhenLowPowerModeIsEnabled() {
    let state = PowerState(thermalState: .nominal, isLowPowerModeEnabled: true, isOnACPower: true, batteryLevel: 1.0)
    #expect(SchedulingPolicy.shouldSuspend(state))
}

@Test func suspendsWhenBatteryBelow20PercentOffPower() {
    let state = PowerState(thermalState: .nominal, isLowPowerModeEnabled: false, isOnACPower: false, batteryLevel: 0.15)
    #expect(SchedulingPolicy.shouldSuspend(state))
}

@Test func doesNotSuspendWhenBatteryLowButOnACPower() {
    let state = PowerState(thermalState: .nominal, isLowPowerModeEnabled: false, isOnACPower: true, batteryLevel: 0.05)
    #expect(!SchedulingPolicy.shouldSuspend(state))
}

@Test func doesNotSuspendUnderNominalConditions() {
    let state = PowerState(thermalState: .fair, isLowPowerModeEnabled: false, isOnACPower: true, batteryLevel: 0.8)
    #expect(!SchedulingPolicy.shouldSuspend(state))
}

@Test func ocrAndInsightAreLimitedToOneConcurrentJob() {
    #expect(SchedulingPolicy.maxConcurrentJobs(forKind: .ocr) == 1)
    #expect(SchedulingPolicy.maxConcurrentJobs(forKind: .insight) == 1)
    #expect(SchedulingPolicy.maxConcurrentJobs(forKind: .extract) == 2)
}

@Test func backoffGrowsExponentially() {
    #expect(BackoffPolicy.delaySeconds(forAttempt: 1, jitter: 0) == 2)
    #expect(BackoffPolicy.delaySeconds(forAttempt: 2, jitter: 0) == 4)
    #expect(BackoffPolicy.delaySeconds(forAttempt: 3, jitter: 0) == 8)
    #expect(BackoffPolicy.delaySeconds(forAttempt: 4, jitter: 0) == 16)
}
