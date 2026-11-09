import Foundation
import IOKit
import CoreGraphics
import HardwareTelemetry
import StatusNavCore

struct BatteryPowerContext: Equatable, Sendable {
    let external: Bool
    let charging: Bool
}
enum PowerReader {
    static func read(context: BatteryPowerContext) -> PowerSnapshot {
        var result = PowerSnapshot()
        let start = Date()
        var count: UInt32 = 0
        if CGGetActiveDisplayList(0, nil, &count) == .success {
            var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
            if CGGetActiveDisplayList(count, &displays, &count) == .success {
                result.internalDisplayActive = displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 }
            }
        }
        var sensors = SNPowerMeters()
        if SNReadPowerMeters(&sensors) {
            if sensors.validMask & 1 != 0 { result.systemWatts = sensors.systemWatts }
            if sensors.validMask & 2 != 0 { result.inputWatts = sensors.inputWatts }
            if sensors.validMask & 4 != 0 { result.displayWatts = sensors.displayWatts }
            if sensors.validMask & 128 != 0, context.external || sensors.batteryNetWatts < 0 {
                result.batteryNetWatts = sensors.batteryNetWatts
            }
            let ports = withUnsafeBytes(of: sensors.outputWatts) { Array($0.bindMemory(to: Double.self)) }
            for index in 0..<4 where sensors.validMask & (8 << index) != 0 { result.portWatts[index + 1] = ports[index] }
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let raw = properties?.takeRetainedValue() as? [String: Any],
               let timestamp = (raw["UpdateTime"] as? NSNumber)?.doubleValue,
               (-5...90).contains(start.timeIntervalSince1970 - timestamp),
               raw["ExternalConnected"] as? Bool == context.external {
                if result.batteryNetWatts == nil, let volts = number(raw["Voltage"]), (1_000...30_000).contains(volts),
                   let current = raw["Amperage"] as? NSNumber,
                   CFGetTypeID(current) != CFBooleanGetTypeID(),
                   !["f", "d"].contains(String(cString: current.objCType)),
                   let amps = PowerSnapshot.signedCurrent(current.int64Value), context.external || amps < 0 {
                    result.batteryNetWatts = volts / 1_000 * amps
                }
                if let telemetry = raw["PowerTelemetryData"] as? [String: Any] {
                    if result.systemWatts == nil, let load = number(telemetry["SystemLoad"]), load > 0, load <= 1_000_000 {
                        result.systemWatts = load / 1_000
                        result.systemSource = "电源管理报告"
                    }
                    if result.inputWatts == nil, let input = number(telemetry["SystemPowerIn"]), (0...1_000_000).contains(input) {
                        result.inputWatts = input / 1_000
                    }
                }
            }
        }
        guard Date().timeIntervalSince(start) < 10 else { return PowerSnapshot() }
        result.updatedAt = start
        return result
    }
    private static func number(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
}
