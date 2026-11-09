import SwiftUI
import StatusNavCore

private struct BluetoothMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        p.move(to: point(0.42, 0.08)); p.addLine(to: point(0.42, 0.92)); p.addLine(to: point(0.78, 0.68))
        p.addLine(to: point(0.16, 0.28)); p.move(to: point(0.16, 0.72)); p.addLine(to: point(0.78, 0.32))
        p.addLine(to: point(0.42, 0.08))
        return p
    }
}
struct BluetoothSectionView: View {
    @ObservedObject var monitor: BluetoothMonitor
    @State private var showDisconnected = false
    init(monitor: BluetoothMonitor, initiallyExpanded: Bool = false) {
        self.monitor = monitor
        _showDisconnected = State(initialValue: initiallyExpanded)
    }
    private var connected: [BluetoothDeviceState] { monitor.snapshot.devices.filter(\.connected) }
    private var disconnected: [BluetoothDeviceState] { monitor.snapshot.devices.filter { !$0.connected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                BluetoothMark().stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 17, height: 20).frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text("蓝牙设备").fontWeight(.semibold)
                    Text(summary).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { monitor.refresh() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 22, height: 24)
                }.buttonStyle(.plain).disabled(monitor.loading)
                    .help("刷新蓝牙设备").accessibilityLabel("刷新蓝牙设备")
                Button { openSystemSettings("com.apple.BluetoothSettings") } label: {
                    Image(systemName: "gearshape").frame(width: 22, height: 24)
                }.buttonStyle(.plain).help("打开蓝牙设置").accessibilityLabel("打开蓝牙设置")
            }
            if monitor.loading {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("正在读取设备报告…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if let error = monitor.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(connected) { row($0) }
                if connected.isEmpty && !monitor.loading {
                    Text(monitor.snapshot.poweredOn == false ? "请在系统设置中开启蓝牙" : "暂无已连接设备")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if !disconnected.isEmpty {
                    Button { showDisconnected.toggle() } label: {
                        HStack {
                            Text("未连接的已配对设备 · \(disconnected.count)")
                            Spacer()
                            Image(systemName: showDisconnected ? "chevron.up" : "chevron.down")
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if showDisconnected { ForEach(disconnected) { row($0) } }
                }
                if let time = monitor.snapshot.updatedAt {
                    Text("读取于 " + time.formatted(date: .omitted, time: .shortened) + " · 电量由设备报告")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }
    }
    private var summary: String {
        if monitor.snapshot.poweredOn == false { return "蓝牙已关闭" }
        if monitor.snapshot.updatedAt == nil { return "连接状态与可读取电量" }
        return "已连接 \(connected.count) · 已配对 \(monitor.snapshot.devices.count)"
    }
    private func row(_ device: BluetoothDeviceState) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol(device)).frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                if device.connected {
                    Text(device.batteries.isEmpty ? "未提供电量" : device.batteries.map { "\($0.label) \($0.percent)%" }.joined(separator: " · "))
                        .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(device.connected ? "已连接" : "未连接").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
        }.padding(.vertical, 5).accessibilityElement(children: .combine)
    }
    private func symbol(_ device: BluetoothDeviceState) -> String {
        let text = (device.kind + " " + device.name).lowercased()
        if text.contains("airpod") || text.contains("head") || text.contains("耳") { return "headphones" }
        if text.contains("keyboard") || text.contains("键盘") { return "keyboard" }
        if text.contains("mouse") || text.contains("鼠标") { return "computermouse" }
        if text.contains("trackpad") { return "trackpad" }
        if text.contains("phone") { return "iphone" }
        if text.contains("speaker") { return "hifispeaker" }
        return "wave.3.right"
    }
}
