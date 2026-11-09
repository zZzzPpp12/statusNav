import Foundation
import CoreFoundation

public struct DeviceBattery: Equatable, Sendable {
    public let label: String
    public let percent: Int
    public init(label: String, percent: Int) { self.label = label; self.percent = percent }
}
public struct BluetoothDeviceState: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let connected: Bool
    public let kind: String
    public let batteries: [DeviceBattery]
}
public struct BluetoothSnapshot: Equatable, Sendable {
    public var poweredOn: Bool?
    public var devices: [BluetoothDeviceState] = []
    public var updatedAt: Date?
    public init() {}

    public mutating func fillMissingBatteryLevels(_ levels: [String: [DeviceBattery]]) {
        devices = devices.map { device in
            guard device.connected, device.batteries.isEmpty, let readings = levels[device.id] else { return device }
            let valid = readings.filter { (0...100).contains($0.percent) }
            return BluetoothDeviceState(id: device.id, name: device.name, connected: true, kind: device.kind, batteries: valid)
        }
    }

    public static func percentage(_ value: Any?) -> Int? {
        let number: Double?
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { number = n.doubleValue }
        else if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            number = Double((trimmed.hasSuffix("%") ? String(trimmed.dropLast()) : trimmed)
                .trimmingCharacters(in: .whitespaces))
        } else { number = nil }
        guard let number, number.isFinite, (0...100).contains(number), number.rounded() == number else { return nil }
        return Int(number)
    }

    public static func parse(_ data: Data, at date: Date = Date()) -> BluetoothSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let report = root["SPBluetoothDataType"] else { return nil }
        let sections: [[String: Any]]
        if let list = report as? [[String: Any]] { sections = list }
        else if let section = report as? [String: Any] { sections = [section] }
        else { return nil }
        var result = BluetoothSnapshot(); result.updatedAt = date
        var devices: [String: BluetoothDeviceState] = [:]
        var ordinal = 0
        for section in sections {
            if let properties = section["controller_properties"] as? [String: Any],
               let state = properties["controller_state"] as? String {
                if state == "attrib_on" { result.poweredOn = true }
                else if state == "attrib_off", result.poweredOn == nil { result.poweredOn = false }
            }
            let controllerOff = (section["controller_properties"] as? [String: Any])?["controller_state"] as? String == "attrib_off"
            for (key, connection) in [("device_not_connected", false), ("device_connected", true), ("devices_list", false)] {
                var entries = section[key] as? [[String: Any]] ?? []
                if let single = section[key] as? [String: Any] { entries = [single] }
                for entry in entries {
                    for (name, raw) in entry {
                        guard let properties = raw as? [String: Any] else { continue }
                        let reportedConnected = key == "devices_list"
                            ? (properties["device_connected"] as? String == "attrib_yes") : connection
                        let connected = reportedConnected && !controllerOff
                        ordinal += 1
                        let address = (properties["device_address"] as? String ?? "").lowercased()
                            .filter { $0.isHexDigit }
                        let id = address.count == 12 ? address : "entry:\(ordinal):" + name
                        if devices[id]?.connected == true && !connected { continue }
                        var levels: [DeviceBattery] = []
                        if connected {
                            for (field, label) in [("device_batteryLevelLeft", "左"), ("device_batteryLevelRight", "右"),
                                                   ("device_batteryLevelCase", "盒")] {
                                if let level = percentage(properties[field]) { levels.append(DeviceBattery(label: label, percent: level)) }
                            }
                            if levels.isEmpty, let level = percentage(properties["device_batteryLevelMain"])
                                ?? percentage(properties["device_batteryLevel"]) {
                                levels.append(DeviceBattery(label: "电量", percent: level))
                            }
                        }
                        if let old = devices[id], old.connected == connected, !old.batteries.isEmpty, levels.isEmpty { continue }
                        let kind = properties["device_minorType"] as? String ?? properties["device_majorType"] as? String ?? ""
                        devices[id] = BluetoothDeviceState(id: id, name: name, connected: connected, kind: kind, batteries: levels)
                    }
                }
            }
        }
        result.devices = devices.values.sorted {
            if $0.connected != $1.connected { return $0.connected }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return result
    }
}
