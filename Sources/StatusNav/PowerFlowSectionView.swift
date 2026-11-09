import SwiftUI
import StatusNavCore

struct PowerFlowSectionView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject private var telemetry: TelemetryMonitor
    init(monitor: SystemMonitor) { self.monitor = monitor; telemetry = monitor.telemetry }
    private var power: PowerSnapshot { telemetry.power }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("功耗流").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("约每 4 秒更新").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            VStack(spacing: 7) {
                PanelDetailRow("适配器 → Mac", monitor.battery.externalPower || monitor.battery.percentage == nil ? PowerSnapshot.wattsText(power.inputWatts) : "未接入")
                PanelDetailRow(batteryDirection, PowerSnapshot.wattsText(power.batteryNetWatts.map(abs)))
                    .help("由电池电压和净电流估算；接通电源时也可能由电池辅助供电")
                PanelDetailRow("系统整机", PowerSnapshot.wattsText(power.systemWatts))
                    .help(power.systemSource + "，不等于各应用 CPU 能耗之和")
            }
            VStack(spacing: 7) {
                if let active = power.internalDisplayActive { PanelDetailRow("内置屏状态", active ? "已激活" : "未激活") }
                PanelDetailRow("内置屏背光功率", power.backlight.rejectedZero ? "读数不一致" : PowerSnapshot.wattsText(power.displayWatts))
                    .help("仅背光传感器，不代表整个显示系统功耗" + (power.backlight.powerSource.map { " · " + $0 } ?? ""))
                if let brightness = power.backlight.brightnessPercent {
                    PanelDetailRow("内屏亮度设置", String(format: "%.0f%%", brightness))
                }
                if let nits = power.backlight.brightnessNits {
                    PanelDetailRow("背光亮度（报告）", String(format: "%.1f nit", nits))
                }
                if let current = power.backlight.driveMilliamps {
                    PanelDetailRow("背光驱动电流（报告）", String(format: "%.2f mA", current))
                }
                if power.backlight.rejectedZero {
                    Text("显示驱动报告亮度，但功率通道返回 0 W，暂不采用该值。亮度和驱动电流不能直接换算为屏幕功耗。")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if power.portWatts.isEmpty {
                    PanelDetailRow("USB / Type-C 输出", "硬件未提供读数")
                } else {
                    PanelDetailRow("可读 USB 通道合计", PowerSnapshot.wattsText(power.portWatts.values.reduce(0, +)))
                    ForEach(power.portWatts.keys.sorted(), id: \.self) { channel in
                        PanelDetailRow("通道 \(channel)", PowerSnapshot.wattsText(power.portWatts[channel]))
                            .padding(.leading, 12)
                    }
                }
            }
            Text("整机可能包含下列分项，不能重复相加。硬件报告可能延迟；通道编号不代表物理接口位置，不可用不等于 0 W。")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if monitor.appActivityEnabled {
                Divider().opacity(0.6)
                ApplicationActivityView(telemetry: telemetry)
            }
        }
        .onAppear { monitor.setPowerDetailsVisible(true) }
        .onDisappear { monitor.setPowerDetailsVisible(false) }
    }
    private var batteryDirection: String {
        guard let watts = power.batteryNetWatts else { return "电池净功率（估计）" }
        if watts < -0.05 { return "电池 → Mac（估计）" }
        if watts > 0.05 { return "Mac → 电池（估计）" }
        return "电池净功率（估计）"
    }
}

private struct ApplicationActivityView: View {
    @ObservedObject var telemetry: TelemetryMonitor
    private var energyAvailable: Bool { telemetry.applications.contains { $0.cpuWatts != nil } }
    private var rows: [ApplicationActivity] {
        let all = energyAvailable ? telemetry.applications.filter { $0.cpuWatts != nil } : telemetry.applications
        return Array(all.sorted {
            let a = energyAvailable ? ($0.cpuWatts ?? 0) : $0.cpuPercent
            let b = energyAvailable ? ($1.cpuWatts ?? 0) : $1.cpuPercent
            if a != b { return a > b }
            return $0.app.name < $1.app.name
        }.prefix(5))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(energyAvailable ? "应用 CPU 能耗 · 估计" : "应用 CPU 活动")
                .font(.system(size: 12, weight: .semibold))
            if rows.isEmpty {
                Text(telemetry.applicationSampling ? "正在采样，稍后显示…" : "系统未提供可读的应用活动")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "app").foregroundStyle(.secondary).frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.app.name).font(.system(size: 11)).lineLimit(1).help(row.app.name)
                        Text("\(row.processCount) 个进程 · " + ByteCountFormatter.string(fromByteCount: Int64(clamping: row.memoryBytes), countStyle: .memory))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        if energyAvailable && row.energyProcessCount < row.processCount {
                            Text("其中 \(row.energyProcessCount) 个进程能耗可读").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        if energyAvailable { Text("CPU " + PowerSnapshot.wattsText(row.cpuWatts)) }
                        Text(String(format: "%.1f%% CPU", row.cpuPercent)).foregroundStyle(.secondary)
                    }.font(.system(size: 10)).monospacedDigit()
                }
            }
            Text("仅当前用户的可读进程；CPU 能耗不包含 GPU、屏幕或网络，不能当作整应用功耗。无能耗计数时按 CPU 活动排序，单核满载为 100%。")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
