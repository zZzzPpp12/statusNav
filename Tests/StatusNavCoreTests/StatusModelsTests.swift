import Testing
@testable import StatusNavCore

@Test func batteryCapacityHandlesMissingAndInvalidReadings() {
    #expect(BatteryState.percentage(current: 50, maximum: 0) == nil)
    #expect(BatteryState.percentage(current: 50, maximum: -1) == nil)
    #expect(BatteryState.percentage(current: 31, maximum: 60) == 52)
    #expect(BatteryState.percentage(current: 120, maximum: 100) == 100)
    #expect(BatteryState.percentage(current: -5, maximum: 100) == 0)
}

@Test func externalPowerDoesNotTriggerLowBatteryWarning() {
    #expect(BatteryState(percentage: 20).isLow)
    #expect(!BatteryState(percentage: 20, externalPower: true).isLow)
    #expect(!BatteryState().isLow)
}

@Test func unknownBatteryAndTimeRemainUnknown() {
    #expect(BatteryState().percentage == nil)
    #expect(BatteryState().summary == "无内置电池")
    #expect(BatteryState(percentage: 70, charging: true, minutesToFull: -1).minutesToFull == nil)
    #expect(BatteryState(percentage: 70, charging: true, minutesToFull: 30).summary.contains("30"))
}

@Test func volumeDotsHandleMuteBoundariesAndNonfiniteValues() {
    #expect(VolumeScale.activeDots(volume: 1, muted: true) == 0)
    #expect(VolumeScale.activeDots(volume: 0, muted: false) == 0)
    #expect(VolumeScale.activeDots(volume: 0.01, muted: false) == 1)
    #expect(VolumeScale.activeDots(volume: 0.5, muted: false) == 2)
    #expect(VolumeScale.activeDots(volume: 4, muted: false) == 4)
    #expect(VolumeScale.activeDots(volume: .nan, muted: false) == 0)
    #expect(VolumeScale.activeDots(volume: .infinity, muted: false) == 0)
    #expect(VolumeScale.activeDots(volume: 1, muted: false, count: -1) == 0)
}

@Test func wifiRemainsConnectedWhenSSIDIsPrivate() {
    var network = NetworkState()
    network.kind = .wifi
    #expect(network.title == "Wi-Fi 已连接")
    #expect(network.symbol == "wifi")
    network.name = "My Wi-Fi"
    #expect(network.title == "My Wi-Fi")
    network.kind = .ethernet
    #expect(network.title == "以太网已连接")
}
