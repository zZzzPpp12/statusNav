import Foundation

public struct BatteryDetails: Equatable, Sendable {
    public var minutesToEmpty: Int?
    public var cycleCount: Int?
    public var capacityPercent: Int?
    public var condition: String?
    public var adapterWatts: Int?
    public var voltage: Double?
    public var lowPowerMode = false

    public init() {}

    public static func capacityPercentage(fullMAh: Double?, designMAh: Double?) -> Int? {
        guard let fullMAh, let designMAh, fullMAh.isFinite, designMAh.isFinite,
              fullMAh > 100, designMAh > 100, fullMAh <= 100_000, designMAh <= 100_000,
              fullMAh <= designMAh * 1.5 else { return nil }
        return min(100, Int((fullMAh / designMAh * 100).rounded()))
    }

    public var remainingTimeText: String? {
        guard let minutesToEmpty, minutesToEmpty > 0 else { return nil }
        let hours = minutesToEmpty / 60
        let minutes = minutesToEmpty % 60
        if hours == 0 { return "约 \(minutes) 分钟" }
        if minutes == 0 { return "约 \(hours) 小时" }
        return "约 \(hours) 小时 \(minutes) 分钟"
    }
}
