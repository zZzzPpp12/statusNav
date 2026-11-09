import Foundation
import IOKit
import StatusNavCore

enum BluetoothHIDBatteryReader {
    /// Cached HID properties only; never discover, pair or open a device connection.
    static func read() -> [String: [DeviceBattery]] {
        var result: [String: [DeviceBattery]] = [:]
        for serviceClass in ["AppleDeviceManagementHIDEventService", "IOHIDDevice"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            var count = 0
            while count < 512 {
                let service = IOIteratorNext(iterator)
                guard service != 0 else { break }
                defer { IOObjectRelease(service) }
                count += 1
                var properties: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let values = properties?.takeRetainedValue() as? [String: Any],
                      let address = values["DeviceAddress"] as? String ?? values["BluetoothAddress"] as? String else { continue }
                let id = address.lowercased().filter { $0.isHexDigit }
                guard id.count == 12 else { continue }
                var levels: [DeviceBattery] = []
                for (key, label) in [("BatteryPercentLeft", "左"), ("BatteryPercentRight", "右"), ("BatteryPercentCase", "盒")] {
                    if let percent = BluetoothSnapshot.percentage(values[key]) { levels.append(DeviceBattery(label: label, percent: percent)) }
                }
                if levels.isEmpty, let percent = BluetoothSnapshot.percentage(values["BatteryPercent"]) {
                    levels.append(DeviceBattery(label: "电量", percent: percent))
                }
                if !levels.isEmpty, result[id] == nil { result[id] = levels }
            }
        }
        return result
    }
}
