import Foundation
import Testing
@testable import StatusNavCore

private func litBacklightParameters() -> [String: Any] { [
    "brightness": ["min": 0, "max": 65_536, "value": 32_768],
    "BrightnessMilliNits": ["min": 8_714, "max": 2_179_711, "value": 139_691],
    "BrightnessMicroAmps": ["min": 191, "max": 51_384, "value": 2_819]
] }

@Test func backlightDriverUnitsRemainSeparateFromPower() {
    let report = BacklightSnapshot.parse(parameters: litBacklightParameters())
    #expect(report.brightnessPercent == 50)
    #expect(report.brightnessNits == 139.691)
    #expect(report.driveMilliamps == 2.819)
    #expect(report.watts == nil)
}

@Test func litBacklightDoesNotPresentUncorroboratedZeroAsMeasuredPower() {
    var report = BacklightSnapshot.parse(parameters: litBacklightParameters())
    report.applyPower(0, source: "PBLR", displayActive: true)
    #expect(report.rejectedZero)
    #expect(report.watts == nil)
    #expect(report.powerSource == "PBLR")
    report.applyPower(1.25, source: "PBLR", displayActive: true)
    #expect(!report.rejectedZero)
    #expect(report.watts == 1.25)
    report.applyPower(nil, source: nil, displayActive: true)
    #expect(report.watts == nil)
    #expect(report.powerSource == nil)
}

@Test func inactiveOrDarkDisplayCanStillHaveARealZeroReading() {
    var report = BacklightSnapshot.parse(parameters: litBacklightParameters())
    report.applyPower(0, source: "PBLR", displayActive: false)
    #expect(report.watts == 0)
    #expect(!report.rejectedZero)
    report.brightnessPercent = 0
    report.applyPower(0, source: "PDBR", displayActive: true)
    #expect(report.watts == 0)
    #expect(!report.rejectedZero)
}

@Test func invalidBacklightReportsNeverProduceAReading() {
    var report = BacklightSnapshot.parse(parameters: [
        "brightness": ["min": 100, "max": 0, "value": 50],
        "BrightnessMilliNits": ["value": Double.nan],
        "BrightnessMicroAmps": ["value": true]
    ])
    #expect(report.brightnessPercent == nil)
    #expect(report.brightnessNits == nil)
    #expect(report.driveMilliamps == nil)
    for watts in [-1, 151, .infinity, .nan] {
        report.applyPower(watts, source: "PBLR", displayActive: true)
        #expect(report.watts == nil)
    }
    let outOfRange = BacklightSnapshot.parse(parameters: [
        "brightness": ["min": 0, "max": 100, "value": 101],
        "BrightnessMilliNits": ["min": 0, "max": 100, "value": 101],
        "BrightnessMicroAmps": ["min": 0, "max": 100, "value": -1]
    ])
    #expect(outOfRange.brightnessPercent == nil)
    #expect(outOfRange.brightnessNits == nil)
    #expect(outOfRange.driveMilliamps == nil)
}
