import AppKit
import SwiftUI
import StatusNavCore

@MainActor
struct PanelView: View {
    static let width: CGFloat = 304
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var audio: AudioController
    let openSettings: () -> Void
    let quit: () -> Void
    var contentSizeDidChange: (@MainActor @Sendable (CGSize) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            batterySection
            Divider()
            networkSection
            Divider()
            audioSection

            if let error = audio.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { audio.error = nil } label: {
                        Image(systemName: "xmark").frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭错误提示")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Divider()
            HStack(spacing: 8) {
                Button("设置…", action: openSettings)
                    .frame(minHeight: 24)
                Spacer()
                Button { monitor.refresh() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
                }
                .help("刷新状态").accessibilityLabel("刷新状态")
                Button(action: quit) {
                    Image(systemName: "power").frame(width: 24, height: 24)
                }
                .help("退出 StatusNav").accessibilityLabel("退出 StatusNav")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: PanelContentSizeKey.self, value: geometry.size)
            }
        }
        .onPreferenceChange(PanelContentSizeKey.self) { size in
            Task { @MainActor in contentSizeDidChange?(size) }
        }
    }

    private var batterySection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: monitor.battery.charging ? "battery.100percent.bolt" : "battery.75percent")
                .font(.system(size: 17))
                .foregroundStyle(monitor.battery.isLow ? Color.orange : Color.primary)
                .frame(width: 22, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("电池").fontWeight(.semibold)
                    Spacer()
                    Text(monitor.battery.percentage.map { "\($0)%" } ?? "—")
                        .monospacedDigit()
                        .fixedSize()
                }
                Text(monitor.battery.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var networkSection: some View {
        Button { openSystemSettings("com.apple.wifi-settings") } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: monitor.network.symbol)
                    .font(.system(size: 17))
                    .frame(width: 22, height: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(networkLabel).fontWeight(.semibold)
                    Text(networkDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("打开网络设置")
        .accessibilityLabel("\(networkLabel)，\(networkDetail)，打开网络设置")
    }

    private var networkLabel: String {
        switch monitor.network.kind {
        case .wifi: "Wi-Fi"
        case .ethernet: "以太网"
        case .other: "网络"
        case .offline: "Wi-Fi"
        }
    }

    private var networkDetail: String {
        switch monitor.network.kind {
        case .wifi:
            let name = monitor.network.name ?? "已连接"
            if let rssi = monitor.network.rssi { return "\(name) · \(rssi) dBm" }
            return name
        case .ethernet, .other:
            return "已连接"
        case .offline:
            return monitor.network.wifiEnabled ? "未连接" : "已关闭"
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("声音").fontWeight(.semibold)
                Spacer()
                Text(audio.muted ? "已静音" : "\(Int((audio.volume * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button { audio.toggleMute() } label: {
                    Image(systemName: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15))
                        .frame(width: 22, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(!audio.canMute)
                .help(audio.muted ? "取消静音" : "静音")
                .accessibilityLabel(audio.muted ? "取消静音" : "静音")
                Slider(value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }), in: 0...1)
                    .controlSize(.small)
                    .tint(.primary)
                    .disabled(!audio.canSetVolume)
                    .accessibilityLabel("输出音量")
            }
            if !audio.canSetVolume {
                Text("请使用设备自身调节音量")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Text("输出设备")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Picker("输出设备", selection: Binding(get: { audio.deviceID }, set: { audio.selectDevice($0) })) {
                    if audio.devices.isEmpty { Text("无可用设备").tag(UInt32(0)) }
                    ForEach(audio.devices) { device in Text(device.name).tag(device.id) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: 186)
                .disabled(audio.devices.isEmpty)
            }
        }
    }
}

private struct PanelContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

@MainActor
func openSystemSettings(_ pane: String) {
    guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
    NSWorkspace.shared.open(url)
}

@MainActor
struct PreferencesView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("菜单栏图标") {
                Toggle("显示电池百分比", isOn: $settings.showPercentage)
                Toggle("使用状态颜色", isOn: $settings.colorful)
                Stepper("图标大小：\(Int(settings.iconSize))", value: $settings.iconSize, in: 22...32, step: 2)
            }
            Section("显示位置") {
                Toggle("同时在 Dock 显示实时图标", isOn: $settings.showDock)
            }
            Section {
                Text("外环显示电量，中心显示网络，底部四点显示音量。充电时中心显示闪电。")
                Text("系统状态在本机读取；不收集使用统计。Wi-Fi 名称不可用时仍显示连接状态。")
            }.font(.caption).foregroundStyle(.secondary)
            Section {
                Link("GitHub · zZzzPpp12/statusNav", destination: URL(string: "https://github.com/zZzzPpp12/statusNav")!)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 420, height: 360)
    }
}
