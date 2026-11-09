import Foundation

public struct TrafficSample: Equatable, Sendable {
    public let interface: String
    public let received: UInt64
    public let sent: UInt64
    public let uptime: Double
    public init(interface: String, received: UInt64, sent: UInt64, uptime: Double) {
        self.interface = interface; self.received = received; self.sent = sent; self.uptime = uptime
    }
}
public struct TrafficRates: Equatable, Sendable {
    public let download: Double
    public let upload: Double
    public init(download: Double, upload: Double) { self.download = download; self.upload = upload }
    public static func text(_ bytes: Double) -> String {
        guard bytes.isFinite, bytes >= 0 else { return "—" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bytes; var unit = 0
        while value >= 1_000 && unit < units.count - 1 { value /= 1_000; unit += 1 }
        return String(format: unit > 0 && value < 10 ? "%.1f%@" : "%.0f%@", value, units[unit])
    }
}
public struct TrafficTracker: Sendable {
    private var previous: TrafficSample?
    public init() {}
    public mutating func reset() { previous = nil }
    public mutating func receive(_ sample: TrafficSample) -> TrafficRates? {
        defer { previous = sample }
        guard let old = previous, old.interface == sample.interface,
              sample.uptime.isFinite, old.uptime.isFinite,
              sample.uptime > old.uptime, sample.uptime - old.uptime <= 15,
              sample.received >= old.received, sample.sent >= old.sent else { return nil }
        let elapsed = sample.uptime - old.uptime
        return TrafficRates(download: Double(sample.received - old.received) / elapsed,
                            upload: Double(sample.sent - old.sent) / elapsed)
    }
}

public struct PowerSnapshot: Equatable, Sendable {
    public var systemWatts: Double?
    public var inputWatts: Double?
    /// Positive means energy flowing into the battery; negative means discharge.
    public var batteryNetWatts: Double?
    public var displayWatts: Double?
    public var internalDisplayActive: Bool?
    public var portWatts: [Int: Double] = [:]
    public var systemSource = "硬件传感器"
    public var updatedAt: Date?
    public init() {}
    public static func wattsText(_ watts: Double?) -> String {
        guard let watts, watts.isFinite else { return "不可用" }
        return String(format: abs(watts) < 10 ? "%.2f W" : "%.1f W", watts)
    }
    public static func signedCurrent(_ raw: Int64) -> Double? {
        let signed = raw > Int64(Int32.max) && raw <= Int64(UInt32.max)
            ? Int64(Int32(bitPattern: UInt32(raw))) : raw
        guard abs(Double(signed)) <= 50_000 else { return nil }
        return Double(signed) / 1_000
    }
}

public enum MenuReadout {
    public static func text(percentage: Int?, showPercentage: Bool, batteryNetWatts: Double?,
                            showPower: Bool, rates: TrafficRates?, showRates: Bool) -> String {
        var parts: [String] = []
        if showPercentage, let percentage { parts.append("\(percentage)%") }
        if showPower {
            if let watts = batteryNetWatts, watts.isFinite {
                let direction = watts > 0.05 ? "充" : watts < -0.05 ? "放" : ""
                parts.append(direction + String(format: "%.1fW", abs(watts)))
            } else { parts.append("—W") }
        }
        if showRates {
            parts.append("↓" + (rates.map { TrafficRates.text($0.download) } ?? "—")
                         + " ↑" + (rates.map { TrafficRates.text($0.upload) } ?? "—"))
        }
        return parts.isEmpty ? "" : " " + parts.joined(separator: "  ")
    }
}

public struct ApplicationIdentity: Equatable, Sendable {
    public let path: String
    public let name: String
    public init(path: String, name: String) { self.path = path; self.name = name }
}
public struct ProcessSample: Equatable, Sendable {
    public let pid: Int32
    public let started: UInt64
    public let app: ApplicationIdentity
    public let cpuNanoseconds: Double
    public let energyNanojoules: UInt64?
    public let memoryBytes: UInt64
    public init(pid: Int32, started: UInt64, app: ApplicationIdentity, cpuNanoseconds: Double,
                energyNanojoules: UInt64?, memoryBytes: UInt64) {
        self.pid = pid; self.started = started; self.app = app; self.cpuNanoseconds = cpuNanoseconds
        self.energyNanojoules = energyNanojoules; self.memoryBytes = memoryBytes
    }
}
public struct ApplicationActivity: Identifiable, Equatable, Sendable {
    public var id: String { app.path }
    public let app: ApplicationIdentity
    public var cpuPercent = 0.0
    public var cpuWatts: Double?
    public var memoryBytes: UInt64 = 0
    public var processCount = 0
    public var energyProcessCount = 0
}
public struct ActivityTracker: Sendable {
    private var previous: [Int32: ProcessSample] = [:]
    private var uptime: Double?
    public init() {}
    public mutating func reset() { previous = [:]; uptime = nil }
    public mutating func receive(_ samples: [ProcessSample], at now: Double) -> [ApplicationActivity] {
        defer { previous = Dictionary(samples.map { ($0.pid, $0) }, uniquingKeysWith: { _, new in new }); uptime = now }
        guard let last = uptime, now > last, now - last <= 20 else { return [] }
        let elapsed = now - last
        var groups: [String: ApplicationActivity] = [:]
        for sample in samples {
            guard let old = previous[sample.pid], old.started == sample.started, old.app == sample.app,
                  sample.cpuNanoseconds.isFinite, sample.cpuNanoseconds >= old.cpuNanoseconds else { continue }
            var row = groups[sample.app.path] ?? ApplicationActivity(app: sample.app)
            row.cpuPercent += (sample.cpuNanoseconds - old.cpuNanoseconds) / 1e9 / elapsed * 100
            if let energy = sample.energyNanojoules, let oldEnergy = old.energyNanojoules,
               energy >= oldEnergy {
                row.cpuWatts = (row.cpuWatts ?? 0) + Double(energy - oldEnergy) / 1e9 / elapsed
                row.energyProcessCount += 1
            }
            row.memoryBytes = row.memoryBytes &+ sample.memoryBytes
            row.processCount += 1
            groups[sample.app.path] = row
        }
        return Array(groups.values)
    }
}
