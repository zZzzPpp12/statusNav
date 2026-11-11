import Testing
@testable import StatusNavCore

@Test func batteryFlowReversesWhenChargingBecomesDischarging() {
    var power = PowerSnapshot()
    power.batteryNetWatts = 12
    let charging = PowerFlowRoute.make(.battery, power: power, battery: .init(percentage: 60, externalPower: true))
    #expect(charging.direction == .forward)
    #expect(charging.pathText == "Mac 电源 → 电池")
    power.batteryNetWatts = -8
    let discharging = PowerFlowRoute.make(.battery, power: power, battery: .init(percentage: 60))
    #expect(discharging.direction == .reverse)
    #expect(discharging.watts == 8)
    #expect(discharging.pathText == "电池 → Mac 电源")
}

@Test func unpluggedChargerDoesNotAnimateAnOldInputReading() {
    var power = PowerSnapshot()
    power.inputWatts = 65
    let route = PowerFlowRoute.make(.charger, power: power, battery: .init(percentage: 70))
    #expect(route.direction == .disconnected)
    #expect(route.watts == nil)
    #expect(!route.direction.isActive)
}

@Test func missingInvalidAndNearZeroPowerNeverShowsAnActiveFlow() {
    let battery = BatteryState(percentage: 70, externalPower: true)
    for value: Double? in [nil, .nan, .infinity, -.infinity] {
        var power = PowerSnapshot()
        power.batteryNetWatts = value
        let route = PowerFlowRoute.make(.battery, power: power, battery: battery)
        #expect(route.direction == .unavailable)
        #expect(route.valueText == "不可用")
    }
    for value in [-0.05, 0, 0.05] {
        var power = PowerSnapshot()
        power.batteryNetWatts = value
        let route = PowerFlowRoute.make(.battery, power: power, battery: battery)
        #expect(route.direction == .stationary)
        #expect(!route.direction.isActive)
        #expect(route.watts != nil)
    }
}

@Test func invalidInputAndConflictingBatterySignsDoNotInventAFlow() {
    var power = PowerSnapshot()
    power.inputWatts = -10
    power.systemWatts = -5
    power.batteryNetWatts = 5
    let battery = BatteryState(percentage: 70)
    #expect(PowerFlowRoute.make(.charger, power: power, battery: .init(externalPower: true)).direction == .unavailable)
    #expect(PowerFlowRoute.make(.system, power: power, battery: battery).direction == .unavailable)
    #expect(PowerFlowRoute.make(.battery, power: power, battery: battery).direction == .unavailable)
}

@Test func externalPowerCanIncludeBatteryAssistanceAndDesktopInput() {
    var power = PowerSnapshot()
    power.inputWatts = 30
    power.batteryNetWatts = -10
    power.systemWatts = 38
    let battery = BatteryState(percentage: 50, externalPower: true)
    #expect(PowerFlowRoute.make(.charger, power: power, battery: battery).direction == .forward)
    #expect(PowerFlowRoute.make(.battery, power: power, battery: battery).direction == .reverse)
    #expect(PowerFlowRoute.make(.system, power: power, battery: battery).watts == 38)
    #expect(PowerFlowRoute.make(.charger, power: power, battery: .init()).watts == 30)
}
