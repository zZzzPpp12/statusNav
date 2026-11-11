import SwiftUI
import StatusNavCore

/// The fill itself is the charge indicator; no separate progress bar is needed.
struct BatteryChargeIcon: View {
    let battery: BatteryState

    private var tint: Color {
        battery.isLow ? .orange : battery.charging ? .green : .primary
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.55), lineWidth: 1.2)
                if battery.percentage != nil {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint)
                        .frame(width: 30 * battery.progress, height: 14)
                        .padding(.leading, 3)
                }
                if battery.charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(battery.progress > 0.55 ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                } else if battery.percentage == nil {
                    Text("?").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .frame(width: 36, height: 20)
            Capsule()
                .fill(.secondary.opacity(0.55))
                .frame(width: 2.5, height: 8)
        }
        .frame(width: 42, height: 30)
    }
}

/// Observe telemetry directly so the three readings refresh together, including while details are collapsed.
struct BatteryPowerSummaryView: View {
    @ObservedObject var telemetry: TelemetryMonitor
    let battery: BatteryState
    private var power: PowerSnapshot { telemetry.power }
    private var inputDisconnected: Bool { battery.percentage != nil && !battery.externalPower }

    var body: some View {
        HStack(spacing: 6) {
            metric("充电器输入", symbol: "powerplug.fill", tint: .orange,
                   value: inputDisconnected ? "未接入" : PowerSnapshot.wattsText(power.inputWatts),
                   subtitle: inputDisconnected ? "电池供电" : "实时输入",
                   help: "充电器实际输入 Mac 的功率，不是适配器标称功率；硬件未提供时显示不可用。")
            metric("电池功率", symbol: batterySymbol, tint: batteryTint,
                   value: PowerSnapshot.wattsText(power.batteryNetWatts.map(abs)),
                   subtitle: batteryDirection,
                   help: "电池净功率由电压和有符号电流估算；充入表示充电，放出表示电池正在供电。")
            metric("系统消耗功率", symbol: "desktopcomputer", tint: .blue,
                   value: PowerSnapshot.wattsText(power.systemWatts),
                   subtitle: "整机消耗",
                   help: power.systemSource + "，不等于各应用 CPU 能耗之和，也不能与分项重复相加。")
        }
    }

    private var batteryDirection: String {
        guard let watts = power.batteryNetWatts, watts.isFinite else { return "等待有效读数" }
        if watts > 0.05 { return "充入电池" }
        if watts < -0.05 { return "电池放出" }
        return "净功率接近零"
    }

    private var batterySymbol: String {
        guard let watts = power.batteryNetWatts else { return "battery.100percent" }
        return watts < -0.05 ? "arrow.up.right" : watts > 0.05 ? "arrow.down.left" : "equal"
    }

    private var batteryTint: Color {
        guard let watts = power.batteryNetWatts else { return .secondary }
        return watts < -0.05 ? .orange : .green
    }

    private func metric(_ title: String, symbol: String, tint: Color, value: String,
                        subtitle: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 3) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).foregroundStyle(.secondary)
            }
            .font(.system(size: 9))
            .lineLimit(1)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .help(help)
        .accessibilityElement(children: .combine)
    }
}
