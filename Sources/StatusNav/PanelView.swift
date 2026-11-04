import AppKit
import SwiftUI
import StatusNavCore

@MainActor
struct PanelView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var audio: AudioController
    let openSettings: () -> Void
    let quit: () -> Void

    private var accent: Color { Color(red: 0.20, green: 0.55, blue: 0.46) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("StatusNav").font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("你的 Mac，一眼掌握").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("实时").font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(accent.opacity(0.12), in: Capsule()).foregroundStyle(accent)
            }
            VStack(spacing: 0) {
                batterySection
                Divider().padding(.horizontal, 14)
                networkSection
            }
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

            audioSection

            if let error = audio.error {
                HStack(alignment: .top) {
                    Text(error).font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button { audio.error = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("关闭错误提示")
                }
            }

            HStack(spacing: 12) {
                Button(action: openSettings) { Label("偏好设置", systemImage: "slider.horizontal.3") }
                Spacer()
                Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("刷新状态").accessibilityLabel("刷新状态")
                Button(action: quit) { Image(systemName: "power") }
                    .help("退出 StatusNav").accessibilityLabel("退出 StatusNav")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary).buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 340)
    }

    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                badge(monitor.battery.charging ? "bolt.fill" : "battery.75percent", color: monitor.battery.isLow ? .orange : accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("电池").font(.system(size: 13, weight: .semibold))
                    Text(monitor.battery.summary).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(monitor.battery.percentage.map { "\($0)%" } ?? "—")
                    .font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
            }
            if monitor.battery.percentage != nil {
                ProgressView(value: monitor.battery.progress).tint(monitor.battery.isLow ? .orange : accent)
            }
        }.padding(14)
    }

    private var networkSection: some View {
        HStack(spacing: 10) {
            badge(monitor.network.symbol, color: .blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(monitor.network.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(networkDetail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { openSystemSettings("com.apple.wifi-settings") } label: {
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium))
            }.buttonStyle(.plain).foregroundStyle(.secondary).help("打开 Wi-Fi 设置")
                .accessibilityLabel("打开 Wi-Fi 设置")
        }.padding(14)
    }

    private var networkDetail: String {
        if monitor.network.kind == .wifi {
            if let rssi = monitor.network.rssi { return "无线连接 · 信号 \(rssi) dBm" }
            return "无线连接 · 网络名称可能受系统隐私保护"
        }
        if monitor.network.kind == .ethernet { return "有线连接" }
        if monitor.network.kind == .other { return "系统网络可用" }
        return monitor.network.wifiEnabled ? "Wi-Fi 已开启 · 等待连接" : "Wi-Fi 已关闭"
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("声音").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(audio.muted ? "已静音" : "\(Int((audio.volume * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button { audio.toggleMute() } label: {
                    Image(systemName: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 20)
                }.buttonStyle(.plain).disabled(!audio.canMute)
                    .accessibilityLabel(audio.muted ? "取消静音" : "静音")
                Slider(value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }), in: 0...1)
                    .tint(accent).disabled(!audio.canSetVolume).accessibilityLabel("输出音量")
            }
            if !audio.canSetVolume {
                Text("此设备不支持系统音量调节，请使用设备自身控制。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Picker(selection: Binding(get: { audio.deviceID }, set: { audio.selectDevice($0) })) {
                if audio.devices.isEmpty { Text("无可用设备").tag(UInt32(0)) }
                ForEach(audio.devices) { device in Text(device.name).tag(device.id) }
            } label: { Text("输出设备").font(.system(size: 11)) }
            .controlSize(.small).disabled(audio.devices.isEmpty)
        }
        .padding(14)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func badge(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .medium))
            .foregroundStyle(color).frame(width: 34, height: 34)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
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
