import SwiftUI
import StatusNavCore

struct PanelDetailRow: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(.secondary).fixedSize()
            Spacer(minLength: 0)
            Text(value)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .combine)
    }
}

struct PanelSectionHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var value: String = ""
    @Binding var expanded: Bool
    let settingsPane: String
    var settingsTitle: String? = nil
    var batteryState: BatteryState? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    if let batteryState {
                        BatteryChargeIcon(battery: batteryState)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: symbol).font(.system(size: 17)).frame(width: 22)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(title).fontWeight(.semibold)
                            Spacer(minLength: 0)
                            if !value.isEmpty { Text(value).monospacedDigit().fixedSize() }
                        }
                        Text(subtitle)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "收起\(title)详情" : "展开\(title)详情")
            .accessibilityLabel("\(title)，\(subtitle)，\(value)")
            .accessibilityValue(expanded ? "已展开" : "已收起")
            Button { openSystemSettings(settingsPane) } label: {
                Image(systemName: "gearshape").frame(width: 22, height: 24)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("打开\(settingsTitle ?? title)系统设置").accessibilityLabel("打开\(settingsTitle ?? title)系统设置")
        }
    }
}

struct BatterySectionView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var expanded = false
    @ObservedObject var navigation: PowerFlowNavigation
    init(monitor: SystemMonitor, navigation: PowerFlowNavigation, initiallyExpanded: Bool = false) {
        self.monitor = monitor
        self.navigation = navigation
        _expanded = State(initialValue: initiallyExpanded)
    }

    private var battery: BatteryState { monitor.battery }
    private var details: BatteryDetails { battery.details }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSectionHeader(title: "电池", subtitle: subtitle,
                symbol: battery.charging ? "battery.100percent.bolt" : "battery.75percent",
                value: battery.percentage.map { "\($0)%" } ?? "—", expanded: $expanded,
                settingsPane: "com.apple.preference.battery", batteryState: battery)
            BatteryPowerSummaryView(telemetry: monitor.telemetry, battery: battery,
                                    animationsEnabled: monitor.panelVisible && !navigation.state.isPresented,
                                    navigation: navigation)
            if battery.percentage != nil {
                HStack(spacing: 8) {
                    Text(details.condition ?? "电池状态未提供")
                    Spacer(minLength: 0)
                    if let capacity = details.capacityPercent {
                        Text("容量估计 \(capacity)%")
                            .help("根据满充容量与设计容量估算，可能与系统设置略有差异")
                    }
                    if let cycles = details.cycleCount { Text("\(cycles) 次循环") }
                }
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            if expanded {
                VStack(spacing: 7) {
                    PanelDetailRow("供电来源", battery.externalPower ? "电源适配器" : battery.percentage == nil ? "未提供" : "电池")
                    if let remaining = details.remainingTimeText { PanelDetailRow("预计可用", remaining) }
                    if let condition = details.condition { PanelDetailRow("健康状况", condition) }
                    if let capacity = details.capacityPercent { PanelDetailRow("最大容量（估计）", "\(capacity)%") }
                    if let cycles = details.cycleCount { PanelDetailRow("循环次数", "\(cycles) 次") }
                    if let watts = details.adapterWatts { PanelDetailRow("适配器功率", "\(watts) W")
                        .help("系统报告的适配器功率，不代表实时充电功率") }
                    if let voltage = details.voltage {
                        PanelDetailRow("电池电压", voltage.formatted(.number.precision(.fractionLength(2))) + " V")
                    }
                    PanelDetailRow("低电量模式", details.lowPowerMode ? "已开启" : "已关闭")
                }
                .padding(.top, 3)
                Divider().opacity(0.6)
                PowerFlowSectionView(monitor: monitor)
            }
        }
    }

    private var subtitle: String {
        if !battery.externalPower, let time = details.remainingTimeText {
            return "使用电池 · \(time)"
        }
        return battery.summary
    }
}

struct NetworkSectionView: View {
    @ObservedObject var monitor: SystemMonitor
    @Binding var showMenuRates: Bool
    @State private var expanded = false
    init(monitor: SystemMonitor, showMenuRates: Binding<Bool>, initiallyExpanded: Bool = false) {
        self.monitor = monitor
        _showMenuRates = showMenuRates
        _expanded = State(initialValue: initiallyExpanded)
    }

    private var network: NetworkState { monitor.network }
    private var connected: Bool { network.kind != .offline }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSectionHeader(title: title, subtitle: subtitle, symbol: network.symbol,
                               expanded: $expanded, settingsPane: settingsPane, settingsTitle: "网络")
            if connected {
                VStack(spacing: 6) {
                    PanelDetailRow("IP 地址", network.ipv4Address ?? network.ipv6Address ?? "未分配")
                    if let rate = network.linkRateText {
                        PanelDetailRow("连接速率", rate)
                            .help("无线链路的协商速率，不代表互联网下载速度")
                    }
                }
            }
            if connected { NetworkTrafficView(telemetry: monitor.telemetry) }
            Toggle("状态栏显示实时网速", isOn: $showMenuRates)
                .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                .foregroundStyle(.secondary)
                .help("显示实际下载和上传速率；关闭面板后也会继续更新")
            if expanded {
                VStack(spacing: 7) {
                    if let interface = network.interfaceName { PanelDetailRow("网络接口", interface) }
                    if let ipv6 = network.ipv6Address, network.ipv4Address != nil { PanelDetailRow("IPv6", ipv6) }
                    if let standard = network.standard { PanelDetailRow("无线标准", standard) }
                    if let band = network.band { PanelDetailRow("频段", band) }
                    if let channel = network.channel { PanelDetailRow("信道", String(channel)) }
                    if let rssi = network.rssi { PanelDetailRow("信号强度", "\(rssi) dBm") }
                    if let noise = network.noise { PanelDetailRow("噪声", "\(noise) dBm") }
                    if let snr = network.signalToNoise { PanelDetailRow("信噪比", "\(snr) dB") }
                    if let security = network.security { PanelDetailRow("安全性", security) }
                    if connected {
                        PanelDetailRow("数据模式", network.isConstrained ? "低数据模式" : "标准")
                        if network.isExpensive { PanelDetailRow("连接类型", "按流量计费") }
                    } else {
                        PanelDetailRow("Wi-Fi", network.wifiEnabled ? "已开启，尚未连接" : "已关闭")
                    }
                    if network.kind == .wifi && network.name == nil {
                        Text("系统未提供网络名称，连接状态仍可正常显示。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 3)
            }
        }
    }

    private var title: String {
        switch network.kind {
        case .wifi: network.name ?? "Wi-Fi"
        case .ethernet: "以太网"
        case .other: "网络"
        case .offline: "Wi-Fi"
        }
    }

    private var subtitle: String {
        if connected {
            let parts = [network.band, network.rssi.map { "\($0) dBm" }].compactMap { $0 }
            return parts.isEmpty ? "已连接" : "已连接 · " + parts.joined(separator: " · ")
        }
        return network.wifiEnabled ? "未连接" : "已关闭"
    }

    private var settingsPane: String {
        network.kind == .wifi || network.kind == .offline ? "com.apple.wifi-settings" : "com.apple.Network-Settings.extension"
    }
}

private struct NetworkTrafficView: View {
    @ObservedObject var telemetry: TelemetryMonitor
    private var rateLabel: String {
        let down = telemetry.rates.map { TrafficRates.text($0.download) } ?? "—"
        let up = telemetry.rates.map { TrafficRates.text($0.upload) } ?? "—"
        return "↓" + down + "   ↑" + up
    }
    var body: some View {
        HStack {
            Text("实时流量").foregroundStyle(.secondary)
            Spacer()
            Text(rateLabel)
                .monospacedDigit()
        }.font(.system(size: 11)).accessibilityElement(children: .combine)
    }
}
