import Foundation
import IOKit
import IOKit.ps
import StatusNavCore

enum BatteryDetailsReader {
    static func read(source: [String: Any], externalPower: Bool) -> BatteryDetails {
        var result = BatteryDetails()
        result.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        if !externalPower, let minutes = source[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
            result.minutesToEmpty = minutes
        }
        let condition = source[kIOPSBatteryHealthConditionKey] as? String
        let health = source[kIOPSBatteryHealthKey] as? String
        if condition == kIOPSCheckBatteryValue || condition == kIOPSPermanentFailureValue {
            result.condition = "建议检修"
        } else {
            switch health {
            case kIOPSGoodValue: result.condition = "正常"
            case kIOPSFairValue: result.condition = "容量有所下降"
            case kIOPSPoorValue: result.condition = "建议检修"
            default: break
            }
        }
        if externalPower,
           let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
           let watts = adapter[kIOPSPowerAdapterWattsKey] as? Int, (1...1_000).contains(watts) {
            result.adapterWatts = watts
        }

        // These optional hardware readings aren't exposed on every Mac.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return result }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let values = properties?.takeRetainedValue() as? [String: Any] else { return result }
        if let count = number(values["CycleCount"]), count >= 0, count <= 100_000 {
            result.cycleCount = Int(count)
        }
        if let millivolts = number(values["Voltage"]), (1_000...30_000).contains(millivolts) {
            result.voltage = millivolts / 1_000
        }
        // Only pair measured mAh values from the same source. MaxCapacity may
        // represent a percentage, so it must not be divided by a design mAh value.
        let sources = [values, values["BatteryData"] as? [String: Any] ?? [:]]
        for readings in sources {
            if let capacity = BatteryDetails.capacityPercentage(
                fullMAh: number(readings["AppleRawMaxCapacity"]),
                designMAh: number(readings["DesignCapacity"])) {
                result.capacityPercent = capacity
                break
            }
        }
        return result
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
}
