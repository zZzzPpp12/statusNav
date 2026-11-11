import Foundation

public enum BatteryChargeState: Equatable, Sendable {
    case unavailable, idle, charging, full

    public var symbol: String? {
        switch self {
        case .charging: "bolt.fill"
        case .full: "checkmark"
        case .unavailable, .idle: nil
        }
    }
}

public struct BatteryState: Equatable, Sendable {
    public var percentage: Int?
    public var charging: Bool
    public var externalPower: Bool
    public var minutesToFull: Int?
    public var fullyCharged: Bool
    public var details = BatteryDetails()

    public init(percentage: Int? = nil, charging: Bool = false, externalPower: Bool = false, minutesToFull: Int? = nil,
                fullyCharged: Bool = false) {
        self.percentage = percentage.map { min(100, max(0, $0)) }
        self.charging = charging
        self.externalPower = externalPower
        self.minutesToFull = minutesToFull.flatMap { $0 > 0 ? $0 : nil }
        self.fullyCharged = fullyCharged
    }

    public static func percentage(current: Int, maximum: Int) -> Int? {
        guard maximum > 0 else { return nil }
        return Int((min(1, max(0, Double(current) / Double(maximum))) * 100).rounded())
    }

    public var progress: Double { Double(percentage ?? 0) / 100 }
    public var isLow: Bool { percentage.map { $0 <= 20 && !externalPower } ?? false }
    public var chargeState: BatteryChargeState {
        guard let percentage else { return .unavailable }
        // An active charge takes precedence over a stale fully-charged reading.
        if charging { return .charging }
        if fullyCharged || percentage == 100 { return .full }
        return .idle
    }
    public var summary: String {
        guard percentage != nil else { return "无内置电池" }
        if charging, let minutesToFull { return "正在充电 · 约 \(minutesToFull) 分钟充满" }
        if charging { return "正在充电" }
        if externalPower && chargeState == .full { return "已充满 · 已接通电源" }
        if externalPower { return "已接通电源" }
        return "使用电池供电"
    }
}

public enum ConnectionKind: String, Sendable {
    case wifi, ethernet, other, offline
}

public struct NetworkState: Equatable, Sendable {
    public var kind: ConnectionKind = .offline
    public var wifiEnabled = false
    public var name: String?
    public var rssi: Int?
    public var interfaceName: String?
    public var ipv4Address: String?
    public var ipv6Address: String?
    public var transmitRate: Double?
    public var band: String?
    public var channel: Int?
    public var noise: Int?
    public var security: String?
    public var standard: String?
    public var isExpensive = false
    public var isConstrained = false
    public init() {}
    public var title: String {
        switch kind {
        case .wifi: name ?? "Wi-Fi 已连接"
        case .ethernet: "以太网已连接"
        case .other: "网络已连接"
        case .offline: "网络未连接"
        }
    }
    public var symbol: String {
        switch kind {
        case .wifi: "wifi"
        case .ethernet: "network"
        case .other: "globe"
        case .offline: "wifi.slash"
        }
    }

    public var signalToNoise: Int? {
        guard let rssi, let noise, (-127..<0).contains(rssi), (-127..<0).contains(noise), rssi >= noise else { return nil }
        return rssi - noise
    }

    /// The negotiated wireless link rate is not an Internet speed measurement.
    public var linkRateText: String? {
        guard let transmitRate, transmitRate.isFinite, transmitRate > 0 else { return nil }
        return String(format: "%.0f Mbps", transmitRate)
    }
}

public enum VolumeScale {
    public static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    public static func activeDots(volume: Double, muted: Bool, count: Int = 4) -> Int {
        guard !muted, count > 0 else { return 0 }
        return Int(ceil(normalized(volume) * Double(count)))
    }
}
