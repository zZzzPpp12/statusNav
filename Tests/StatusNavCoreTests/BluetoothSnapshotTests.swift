import Foundation
import Testing
@testable import StatusNavCore

@Test func bluetoothOnlyDisplaysBatteryForConnectedDevicesAndPreservesRealZero() throws {
    let report: [String: Any] = ["SPBluetoothDataType": [[
        "controller_properties": ["controller_state": "attrib_on"],
        "device_connected": [["Headphones": ["device_address": "AA-BB-CC-DD-EE-01", "device_batteryLevelMain": "0%"]]],
        "device_not_connected": [["Mouse": ["device_address": "AA:BB:CC:DD:EE:02", "device_batteryLevelMain": "90%"]]]
    ]]]
    let data = try JSONSerialization.data(withJSONObject: report)
    let snapshot = try #require(BluetoothSnapshot.parse(data))
    #expect(snapshot.devices.count == 2)
    #expect(snapshot.devices.first?.connected == true)
    #expect(snapshot.devices.first?.batteries.first?.percent == 0)
    #expect(snapshot.devices.last?.batteries.isEmpty == true)
    #expect(BluetoothSnapshot.percentage(true) == nil)
    #expect(BluetoothSnapshot.percentage("5%0") == nil)
    #expect(BluetoothSnapshot.percentage("101%") == nil)
}

@Test func bluetoothSeparatesEarbudPartsAndDoesNotDuplicateAddresses() throws {
    let paired: [String: Any] = ["SPBluetoothDataType": [[
        "device_connected": [["Pods": ["device_address": "AA-BB-CC-DD-EE-01", "device_batteryLevelLeft": "45%",
            "device_batteryLevelRight": "60%", "device_batteryLevelCase": "10%"]]],
        "device_not_connected": [["Old name": ["device_address": "AA:BB:CC:DD:EE:01"]]]
    ]]]
    let parsed = try #require(BluetoothSnapshot.parse(try JSONSerialization.data(withJSONObject: paired)))
    #expect(parsed.devices.count == 1)
    #expect(parsed.devices[0].batteries.map(\.label) == ["左", "右", "盒"])
    #expect(parsed.devices[0].batteries.map(\.percent) == [45, 60, 10])
}

@Test func bluetoothDistinguishesInvalidReportsFromNoDevicesAndRespectsPoweredOff() throws {
    #expect(BluetoothSnapshot.parse(Data("{}".utf8)) == nil)
    let empty = try JSONSerialization.data(withJSONObject: ["SPBluetoothDataType": [[String: String]()]])
    #expect(BluetoothSnapshot.parse(empty)?.devices.isEmpty == true)
    let off: [String: Any] = ["SPBluetoothDataType": [["controller_properties": ["controller_state": "attrib_off"],
        "device_connected": [["Mouse": ["device_address": "AA:BB:CC:DD:EE:01", "device_batteryLevelMain": "80%"]]]]]]
    let result = try #require(BluetoothSnapshot.parse(try JSONSerialization.data(withJSONObject: off)))
    #expect(result.poweredOn == false)
    #expect(result.devices.first?.connected == false)
    #expect(result.devices.first?.batteries.isEmpty == true)
}

@Test func hidBatteryFallbackRequiresExactIdentityAndConnectedState() throws {
    let report: [String: Any] = ["SPBluetoothDataType": [[
        "device_connected": [["Mouse": ["device_address": "AA-BB-CC-DD-EE-01"]]],
        "device_not_connected": [["Other Mouse": ["device_address": "AA-BB-CC-DD-EE-02"]]]
    ]]]
    var snapshot = try #require(BluetoothSnapshot.parse(try JSONSerialization.data(withJSONObject: report)))
    snapshot.fillMissingBatteryLevels([
        "aabbccddee01": [DeviceBattery(label: "电量", percent: 0)],
        "aabbccddee02": [DeviceBattery(label: "电量", percent: 80)],
        "unknown": [DeviceBattery(label: "电量", percent: 90)]
    ])
    #expect(snapshot.devices.first?.batteries.first?.percent == 0)
    #expect(snapshot.devices.last?.batteries.isEmpty == true)
}
