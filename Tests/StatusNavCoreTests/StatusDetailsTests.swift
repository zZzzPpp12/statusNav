import Testing
@testable import StatusNavCore

@Test func capacityEstimatesRejectPercentagesAndInvalidUnits() {
    #expect(BatteryDetails.capacityPercentage(fullMAh: 6_000, designMAh: 7_000) == 86)
    #expect(BatteryDetails.capacityPercentage(fullMAh: 7_100, designMAh: 7_000) == 100)
    #expect(BatteryDetails.capacityPercentage(fullMAh: 100, designMAh: 7_000) == nil)
    #expect(BatteryDetails.capacityPercentage(fullMAh: 7_000, designMAh: 100) == nil)
    #expect(BatteryDetails.capacityPercentage(fullMAh: 7_000, designMAh: 0) == nil)
    #expect(BatteryDetails.capacityPercentage(fullMAh: 7_000, designMAh: .nan) == nil)
    #expect(BatteryDetails.capacityPercentage(fullMAh: .infinity, designMAh: 7_000) == nil)
    #expect(BatteryDetails.capacityPercentage(fullMAh: 20_000, designMAh: 7_000) == nil)
    #expect(BatteryDetails.capacityPercentage(fullMAh: nil, designMAh: 7_000) == nil)
}

@Test func remainingTimeDoesNotPresentUnknownAsZeroMinutes() {
    var details = BatteryDetails()
    #expect(details.remainingTimeText == nil)
    details.minutesToEmpty = -1
    #expect(details.remainingTimeText == nil)
    details.minutesToEmpty = 0
    #expect(details.remainingTimeText == nil)
    details.minutesToEmpty = 45
    #expect(details.remainingTimeText == "约 45 分钟")
    details.minutesToEmpty = 120
    #expect(details.remainingTimeText == "约 2 小时")
    details.minutesToEmpty = 125
    #expect(details.remainingTimeText == "约 2 小时 5 分钟")
}

@Test func fullChargeOnlyChangesTheSummaryWhenExternalPowerIsConnected() {
    #expect(BatteryState(percentage: 100, externalPower: true, fullyCharged: true).summary.contains("已充满"))
    #expect(BatteryState(percentage: 100, fullyCharged: true).summary == "使用电池供电")
    #expect(BatteryState(percentage: 80, charging: true, externalPower: true, fullyCharged: true).summary == "正在充电")
}

@Test func signalToNoiseRequiresTwoValidCompatibleMeasurements() {
    var network = NetworkState()
    network.rssi = -52
    #expect(network.signalToNoise == nil)
    network.noise = -92
    #expect(network.signalToNoise == 40)
    network.noise = 0
    #expect(network.signalToNoise == nil)
    network.noise = -30
    #expect(network.signalToNoise == nil)
    network.rssi = 0
    #expect(network.signalToNoise == nil)
}

@Test func linkRatesRemainUnknownForInvalidSystemReadings() {
    var network = NetworkState()
    #expect(network.linkRateText == nil)
    for invalid in [0.0, -1, .nan, .infinity] {
        network.transmitRate = invalid
        #expect(network.linkRateText == nil)
    }
    network.transmitRate = 866.7
    #expect(network.linkRateText == "867 Mbps")
}
