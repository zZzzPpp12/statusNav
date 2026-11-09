import AppKit
import SwiftUI
import StatusNavCore

@MainActor
struct PanelView: View {
    static let width: CGFloat = 336
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var audio: AudioController
    let openSettings: () -> Void
    let quit: () -> Void
    var expandedDetails = false
    var contentSizeDidChange: (@MainActor @Sendable (CGSize) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BatterySectionView(monitor: monitor, initiallyExpanded: expandedDetails)
            Divider()
            NetworkSectionView(monitor: monitor, initiallyExpanded: expandedDetails)
            Divider()
            AudioSectionView(output: audio, input: monitor.inputAudio, initiallyExpanded: expandedDetails)

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
