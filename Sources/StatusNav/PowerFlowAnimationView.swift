import SwiftUI
import StatusNavCore

extension PowerFlowRoute {
    var tint: Color {
        if direction == .unavailable || direction == .disconnected { return .secondary }
        return switch kind {
        case .charger: .orange
        case .battery: direction == .reverse ? .orange : .green
        case .system: .blue
        }
    }
    var symbol: String {
        switch kind {
        case .charger: "powerplug.fill"
        case .battery: "battery.100percent"
        case .system: "desktopcomputer"
        }
    }
}

private enum FlowMotion {
    static func phase(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
    }
}

/// The clock lives inside the small glyph, never in telemetry or the panel's layout state.
struct PowerFlowGlyph: View {
    let route: PowerFlowRoute
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var moving: Bool { enabled && !reduceMotion && route.direction.isActive }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !moving)) { context in
            let phase = moving ? FlowMotion.phase(context.date) : 0
            ZStack {
                Circle().strokeBorder(route.tint.opacity(0.13), lineWidth: 1)
                Image(systemName: route.symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(route.tint)
                    .scaleEffect(moving ? 1 + 0.07 * sin(phase * .pi * 2) : 1)
                    .opacity(moving ? 0.78 + 0.22 * sin(phase * .pi * 2) : 0.8)
                if moving {
                    Canvas { drawing, size in
                        let angle = (route.direction == .reverse ? -phase : phase) * .pi * 2 - .pi / 2
                        let x = size.width / 2 + cos(angle) * 7.5
                        let y = size.height / 2 + sin(angle) * 7.5
                        drawing.fill(Path(ellipseIn: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8)),
                                     with: .color(route.tint))
                    }
                }
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

struct PowerFlowTrack: View {
    let route: PowerFlowRoute
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var moving: Bool { enabled && !reduceMotion && route.direction.isActive }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !moving)) { context in
            let phase = FlowMotion.phase(context.date)
            Canvas { drawing, size in
                let y = size.height / 2
                let left: CGFloat = 5
                let right = max(left, size.width - 5)
                let active = route.direction.isActive
                let color = active ? route.tint : Color.secondary
                var line = Path()
                line.move(to: CGPoint(x: left, y: y))
                line.addLine(to: CGPoint(x: right, y: y))
                drawing.stroke(line, with: .color(color.opacity(0.25)),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                                  dash: active ? [] : [3, 4]))
                if active {
                    let reverse = route.direction == .reverse
                    let tip = reverse ? left : right
                    let tail = tip + (reverse ? 4 : -4)
                    var arrow = Path()
                    arrow.move(to: CGPoint(x: tail, y: y - 3))
                    arrow.addLine(to: CGPoint(x: tip, y: y))
                    arrow.addLine(to: CGPoint(x: tail, y: y + 3))
                    drawing.stroke(arrow, with: .color(color.opacity(0.8)),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    if moving {
                        for index in 0..<3 {
                            let progress = (phase + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                            let position = reverse ? 1 - progress : progress
                            let x = left + (right - left) * position
                            let dot = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
                            drawing.fill(Path(ellipseIn: dot.insetBy(dx: -2, dy: -2)), with: .color(color.opacity(0.12)))
                            drawing.fill(Path(ellipseIn: dot), with: .color(color))
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct PowerFlowDetailView: View {
    let kind: PowerFlowKind
    let power: PowerSnapshot
    let battery: BatteryState
    let animationsEnabled: Bool
    let close: () -> Void

    private var route: PowerFlowRoute { PowerFlowRoute.make(kind, power: power, battery: battery) }
    private var supporting: [PowerFlowRoute] {
        let hasBattery = battery.percentage != nil || power.batteryNetWatts != nil
        let kinds: [PowerFlowKind]
        switch kind {
        case .charger: kinds = hasBattery ? [.battery, .system] : [.system]
        case .battery: kinds = [.charger, .system]
        case .system: kinds = hasBattery ? [.charger, .battery] : [.charger]
        }
        return kinds.map { PowerFlowRoute.make($0, power: power, battery: battery) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(route.direction.isActive ? route.tint : Color.secondary).frame(width: 5, height: 5)
                Text(kind.title + "流程").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Button(action: close) { Image(systemName: "xmark").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("收起功率流程")
            }
            HStack(spacing: 6) {
                node(route.source, tint: route.tint)
                VStack(spacing: 4) {
                    Text(route.valueText).font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    PowerFlowTrack(route: route, enabled: animationsEnabled).frame(height: 20)
                    Text(route.statusText).font(.system(size: 10)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                node(route.target, tint: route.tint)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(route.pathText + "，" + route.valueText + "，" + route.statusText)

            ForEach(supporting, id: \.kind) { flow in
                PowerFlowCompactRouteView(route: flow, animationsEnabled: animationsEnabled)
            }
            Text(explanation)
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(route.tint.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11).strokeBorder(route.tint.opacity(0.13), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }

    private func node(_ node: PowerFlowNode, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: node.symbol).font(.system(size: 17))
                .foregroundStyle(tint).frame(width: 34, height: 34)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            Text(node.title).font(.system(size: 10, weight: .medium))
        }.frame(width: 56)
    }

    private var explanation: String {
        switch kind {
        case .charger: "显示充电器实际输入，不是标称功率。电池可同时充电，也可能辅助供电。"
        case .battery: "电池净功率由电压与有符号电流估算；箭头随充入、放出方向切换。"
        case .system: "整机读数来源：\(power.systemSource)。分项可能重叠，不能直接相加。"
        }
    }
}

private struct PowerFlowCompactRouteView: View {
    let route: PowerFlowRoute
    let animationsEnabled: Bool
    private var spokenText: String { "\(route.pathText)，\(route.valueText)，\(route.statusText)" }

    var body: some View {
        VStack(spacing: 4) {
            endpoints
            PowerFlowTrack(route: route, enabled: animationsEnabled).frame(height: 10)
        }
        .padding(8)
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
        .help("\(route.pathText) · \(route.statusText)")
    }

    private var endpoints: some View {
        HStack(spacing: 6) {
            Text(route.source.title).fixedSize()
            Spacer(minLength: 0)
            Text(route.valueText).monospacedDigit().fixedSize()
            Spacer(minLength: 0)
            Text(route.target.title).fixedSize()
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
}

private extension PowerFlowNode {
    var symbol: String {
        switch self {
        case .charger: "powerplug.fill"
        case .mac: "desktopcomputer"
        case .battery: "battery.75percent"
        case .system: "cpu"
        }
    }
}
