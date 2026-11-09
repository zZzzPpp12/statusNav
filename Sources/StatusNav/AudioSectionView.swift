import SwiftUI

struct AudioSectionView: View {
    @ObservedObject var output: AudioController
    @ObservedObject var input: AudioController
    @State private var inputExpanded = false

    init(output: AudioController, input: AudioController, initiallyExpanded: Bool = false) {
        self.output = output
        self.input = input
        _inputExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("声音").fontWeight(.semibold)
                Spacer()
                Text(output.muted ? "已静音" : volumeText(output))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                Button { openSystemSettings("com.apple.Sound-Settings.extension") } label: {
                    Image(systemName: "gearshape").frame(width: 22, height: 24)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("打开声音设置").accessibilityLabel("打开声音设置")
            }
            HStack(spacing: 10) {
                Button { output.toggleMute() } label: {
                    Image(systemName: output.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15)).frame(width: 22, height: 24)
                }
                .buttonStyle(.plain).disabled(!output.canMute)
                .help(output.muted ? "取消静音" : "静音")
                .accessibilityLabel(output.muted ? "取消静音" : "静音")
                Slider(value: Binding(get: { output.volume }, set: { output.setVolume($0) }), in: 0...1)
                    .tint(.primary).controlSize(.small).disabled(!output.canSetVolume)
                    .accessibilityLabel("输出音量")
            }
            if !output.canSetVolume {
                Text("请使用设备自身调节音量")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text("输出设备 · \(output.devices.count)")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            AudioDeviceListView(controller: output)

            Divider().opacity(0.6).padding(.vertical, 3)
            PanelSectionHeader(title: "麦克风", subtitle: input.deviceName, symbol: "mic.fill",
                               value: input.muted ? "已静音" : volumeText(input), expanded: $inputExpanded,
                               settingsPane: "com.apple.Sound-Settings.extension", settingsTitle: "声音")
            if inputExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 10) {
                        Text("输入音量").font(.system(size: 11)).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { input.volume }, set: { input.setVolume($0) }), in: 0...1)
                            .tint(.primary).controlSize(.small).disabled(!input.canSetVolume)
                            .accessibilityLabel("输入音量")
                    }
                    if !input.canSetVolume {
                        Text("此设备未提供可调输入音量")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    AudioDeviceListView(controller: input)
                }
            }
            if let error = input.error {
                HStack(alignment: .top) {
                    Text(error).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { input.error = nil } label: { Image(systemName: "xmark").frame(width: 20, height: 20) }
                        .buttonStyle(.plain).accessibilityLabel("关闭输入设备错误提示")
                }
                .font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
    }

    private func volumeText(_ controller: AudioController) -> String {
        guard controller.hasVolumeReading else { return "—" }
        return "\(Int((controller.volume * 100).rounded()))%"
    }
}

private struct AudioDeviceListView: View {
    @ObservedObject var controller: AudioController
    @State private var expanded = false

    private var orderedDevices: [AudioDevice] {
        controller.devices.sorted {
            if ($0.id == controller.deviceID) != ($1.id == controller.deviceID) { return $0.id == controller.deviceID }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            if controller.devices.isEmpty {
                Text("无可用设备").font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
            }
            ForEach(Array(orderedDevices.prefix(expanded ? orderedDevices.count : 3))) { device in
                AudioDeviceRow(device: device, selected: device.id == controller.deviceID,
                               direction: controller.direction) { controller.selectDevice(device.id) }
            }
            if controller.devices.count > 3 {
                Button(expanded ? "收起设备" : "显示其余 \(controller.devices.count - 3) 个设备") { expanded.toggle() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
            }
        }
    }
}

private struct AudioDeviceRow: View {
    let device: AudioDevice
    let selected: Bool
    let direction: AudioDirection
    let select: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: device.symbol(direction: direction))
                    .font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name).font(.system(size: 12, weight: selected ? .medium : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(device.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor).accessibilityHidden(true)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 4)
            .contentShape(Rectangle())
            .background(.primary.opacity(hovered ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .accessibilityLabel("\(device.name)，\(device.subtitle)")
        .accessibilityValue(selected ? "当前设备" : "")
        .help(selected ? "当前设备" : "切换到\(device.name)")
    }
}
