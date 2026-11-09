import Foundation
import CoreFoundation

public struct BacklightSnapshot: Equatable, Sendable {
    public var brightnessPercent: Double?
    public var brightnessNits: Double?
    public var driveMilliamps: Double?
    public private(set) var watts: Double?
    public private(set) var powerSource: String?
    public private(set) var rejectedZero = false
    public init() {}

    public static func parse(parameters: [String: Any]) -> Self {
        var result = Self()
        if let range = parameters["brightness"] as? [String: Any],
           let value = number(range["value"]), let minimum = number(range["min"]),
           let maximum = number(range["max"]), minimum >= 0, maximum > minimum,
           (minimum...maximum).contains(value) {
            result.brightnessPercent = (value - minimum) / (maximum - minimum) * 100
        }
        if let value = parameter("BrightnessMilliNits", parameters), (0...10_000_000).contains(value) {
            result.brightnessNits = value / 1_000
        }
        if let value = parameter("BrightnessMicroAmps", parameters), (0...1_000_000).contains(value) {
            result.driveMilliamps = value / 1_000
        }
        return result
    }

    public mutating func applyPower(_ value: Double?, source: String?, displayActive: Bool?) {
        watts = nil; powerSource = nil; rejectedZero = false
        guard let value, value.isFinite, (0...150).contains(value) else { return }
        powerSource = source
        // Acknowledging a key does not prove it measures this machine's backlight.
        // Driver brightness fields are operating parameters, not a power meter.
        let requestsLight = brightnessPercent.map { $0 > 0 }
            ?? brightnessNits.map { $0 > 0 } ?? driveMilliamps.map { $0 > 0 } ?? false
        if value == 0, displayActive == true, requestsLight {
            rejectedZero = true
        } else { watts = value }
    }

    private static func parameter(_ key: String, _ parameters: [String: Any]) -> Double? {
        guard let row = parameters[key] as? [String: Any], let value = number(row["value"]) else { return nil }
        if let minimum = number(row["min"]), value < minimum { return nil }
        if let maximum = number(row["max"]), value > maximum { return nil }
        return value
    }
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
}
