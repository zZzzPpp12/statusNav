import Foundation
import Testing
import HardwareTelemetry
@testable import StatusNavCore

@Test func trafficUsesElapsedTimeAndResetsAcrossInterfacesSleepAndCounterResets() {
    var tracker = TrafficTracker()
    #expect(tracker.receive(.init(interface: "en0", received: 100, sent: 50, uptime: 1)) == nil)
    let rate = tracker.receive(.init(interface: "en0", received: 2100, sent: 550, uptime: 3))
    #expect(rate == TrafficRates(download: 1000, upload: 250))
    #expect(tracker.receive(.init(interface: "en1", received: 9000, sent: 5000, uptime: 5)) == nil)
    #expect(tracker.receive(.init(interface: "en1", received: 5, sent: 1, uptime: 7)) == nil)
    #expect(tracker.receive(.init(interface: "en1", received: 50_000, sent: 99, uptime: 100)) == nil)
    #expect(tracker.receive(.init(interface: "en1", received: 50_000, sent: 99, uptime: 100)) == nil)
    tracker.reset()
    #expect(tracker.receive(.init(interface: "en1", received: 50_100, sent: 100, uptime: 102)) == nil)
}

@Test func menuOptionsAreIndependentAndMissingPowerNeverBecomesZero() {
    let rates = TrafficRates(download: 1200, upload: 0)
    #expect(MenuReadout.text(percentage: 80, showPercentage: false, batteryNetWatts: -4,
        showPower: false, rates: rates, showRates: false).isEmpty)
    let power = MenuReadout.text(percentage: nil, showPercentage: false, batteryNetWatts: -4,
        showPower: true, rates: rates, showRates: false)
    #expect(power.contains("放4.0W")); #expect(!power.contains("↓"))
    let network = MenuReadout.text(percentage: 80, showPercentage: true, batteryNetWatts: nil,
        showPower: false, rates: rates, showRates: true)
    #expect(network.contains("80%")); #expect(network.contains("↓1.2KB/s")); #expect(!network.contains("W"))
    #expect(MenuReadout.text(percentage: nil, showPercentage: false, batteryNetWatts: nil,
        showPower: true, rates: nil, showRates: false).contains("—W"))
    #expect(MenuReadout.text(percentage: nil, showPercentage: false, batteryNetWatts: 8,
        showPower: true, rates: nil, showRates: false).contains("充8.0W"))
    #expect(TrafficRates.text(.nan) == "—")
}

@Test func signedBatteryCurrentHandlesBothUnsignedWrapsAndRejectsNonsense() {
    #expect(PowerSnapshot.signedCurrent(-302) == -0.302)
    #expect(PowerSnapshot.signedCurrent(Int64(UInt32(bitPattern: -302))) == -0.302)
    #expect(PowerSnapshot.signedCurrent(0) == 0)
    #expect(PowerSnapshot.signedCurrent(9_999_999) == nil)
    #expect(PowerSnapshot.signedCurrent(Int64.min) == nil)
    #expect(PowerSnapshot.wattsText(nil) == "不可用")
    #expect(PowerSnapshot.wattsText(0) == "0.00 W")
}

@Test func smcScalarDecodingHandlesEndiannessUnknownTypesAndNonfiniteValues() {
    func decode(_ type: String, _ bytes: [UInt8]) -> Double? {
        var result = 0.0
        let valid = bytes.withUnsafeBufferPointer { SNDecodeSMCScalar(type, $0.baseAddress, UInt32($0.count), &result) }
        return valid ? result : nil
    }
    #expect(decode("flt ", [0, 0, 0xc0, 0x3f]) == 1.5)
    #expect(decode("fpe2", [0, 6]) == 1.5)
    #expect(decode("sp78", [0xff, 0x80]) == -0.5)
    #expect(decode("flt ", [0, 0, 0x80, 0x7f]) == nil)
    #expect(decode("ui16", [0, 10]) == nil)
    #expect(decode("flt ", [0, 0]) == nil)
}

@Test func applicationActivityDoesNotAssignOldCountersToReusedPIDs() {
    let app = ApplicationIdentity(path: "/A.app", name: "A")
    func sample(_ pid: Int32, _ start: UInt64, _ cpu: Double, _ energy: UInt64?) -> ProcessSample {
        ProcessSample(pid: pid, started: start, app: app, cpuNanoseconds: cpu, energyNanojoules: energy, memoryBytes: 100)
    }
    var tracker = ActivityTracker()
    #expect(tracker.receive([sample(1, 1, 1e9, 1_000_000_000)], at: 1).isEmpty)
    let rows = tracker.receive([sample(1, 1, 3e9, 5_000_000_000)], at: 3)
    #expect(rows.count == 1); #expect(rows.first?.cpuPercent == 100); #expect(rows.first?.cpuWatts == 2)
    #expect(tracker.receive([sample(1, 2, 1e9, 2_000_000_000)], at: 5).isEmpty)
    #expect(tracker.receive([sample(1, 2, 5e9, 4_000_000_000)], at: 100).isEmpty)
}

@Test func missingApplicationEnergyKeepsCpuActivityWithoutInventingWatts() {
    let app = ApplicationIdentity(path: "/A.app", name: "A")
    var tracker = ActivityTracker()
    let one = ProcessSample(pid: 1, started: 1, app: app, cpuNanoseconds: 0, energyNanojoules: nil, memoryBytes: 100)
    let two = ProcessSample(pid: 1, started: 1, app: app, cpuNanoseconds: 1e9, energyNanojoules: nil, memoryBytes: 100)
    _ = tracker.receive([one], at: 1)
    let result = tracker.receive([two], at: 3)
    #expect(result.first?.cpuPercent == 50)
    #expect(result.first?.cpuWatts == nil)
}

@Test func batterySensorsKeepSignedCurrentAndMilliUnits() {
    var current = 0.0
    let currentBytes: [UInt8] = [0xd2, 0xfe]
    #expect(currentBytes.withUnsafeBufferPointer { SNDecodeBatteryScalar("si16", $0.baseAddress, 2, true, &current) })
    #expect(current == -0.302)
    var voltage = 0.0
    let voltageBytes: [UInt8] = [0xee, 0x31]
    #expect(voltageBytes.withUnsafeBufferPointer { SNDecodeBatteryScalar("ui16", $0.baseAddress, 2, false, &voltage) })
    #expect(voltage == 12.782)
    #expect(!voltageBytes.withUnsafeBufferPointer { SNDecodeBatteryScalar("ui16", $0.baseAddress, 2, true, &current) })
}
