import Foundation

public enum PowerFlowKind: String, CaseIterable, Identifiable, Sendable {
    case charger, battery, system
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .charger: "充电器输入"
        case .battery: "电池功率"
        case .system: "系统消耗功率"
        }
    }
}

public enum PowerFlowNode: Equatable, Sendable {
    case charger, mac, battery, system
    public var title: String {
        switch self {
        case .charger: "充电器"
        case .mac: "Mac 电源"
        case .battery: "电池"
        case .system: "系统运行"
        }
    }
}

public enum PowerFlowDirection: Equatable, Sendable {
    case forward, reverse, stationary, unavailable, disconnected
    public var isActive: Bool { self == .forward || self == .reverse }
}

public struct PowerFlowRoute: Equatable, Sendable {
    public let kind: PowerFlowKind
    /// Canonical diagram endpoints. Reverse flow keeps these nodes fixed on screen.
    public let source: PowerFlowNode
    public let target: PowerFlowNode
    public let watts: Double?
    public let direction: PowerFlowDirection

    public var valueText: String {
        direction == .disconnected ? "未接入" : PowerSnapshot.wattsText(watts)
    }
    public var statusText: String {
        switch direction {
        case .unavailable: return "等待有效读数"
        case .disconnected: return "电池供电"
        case .stationary: return kind == .battery ? "净功率接近零" : "暂无功率流动"
        case .reverse: return "电池放出"
        case .forward:
            switch kind {
            case .charger: return "正在输入"
            case .battery: return "充入电池"
            case .system: return "整机消耗"
            }
        }
    }
    public var pathText: String {
        switch direction {
        case .reverse: "\(target.title) → \(source.title)"
        case .forward: "\(source.title) → \(target.title)"
        case .stationary: "\(source.title) · \(target.title)"
        case .unavailable: "\(source.title) ↔ \(target.title) · 方向未知"
        case .disconnected: "充电器未接入"
        }
    }

    public static func make(_ kind: PowerFlowKind, power: PowerSnapshot, battery: BatteryState) -> Self {
        let source: PowerFlowNode = kind == .charger ? .charger : .mac
        let target: PowerFlowNode = kind == .battery ? .battery : kind == .charger ? .mac : .system
        if kind == .charger, battery.percentage != nil, !battery.externalPower {
            return Self(kind: kind, source: source, target: target, watts: nil, direction: .disconnected)
        }
        let raw: Double?
        switch kind {
        case .charger: raw = power.inputWatts
        case .battery: raw = power.batteryNetWatts
        case .system: raw = power.systemWatts
        }
        guard let raw, raw.isFinite,
              kind == .battery || raw >= 0,
              kind != .battery || battery.externalPower || raw <= 0 else {
            return Self(kind: kind, source: source, target: target, watts: nil, direction: .unavailable)
        }
        let direction: PowerFlowDirection = abs(raw) <= 0.05 ? .stationary : raw < 0 ? .reverse : .forward
        return Self(kind: kind, source: source, target: target, watts: abs(raw), direction: direction)
    }
}
