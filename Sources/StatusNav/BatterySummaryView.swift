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
    let animationsEnabled: Bool
    @ObservedObject var navigation: PowerFlowNavigation

    private var power: PowerSnapshot { telemetry.power }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PowerFlowKind.allCases) { kind in
                metric(PowerFlowRoute.make(kind, power: power, battery: battery))
            }
        }
    }

    private func metric(_ route: PowerFlowRoute) -> some View {
        Button {
            navigation.open(route.kind)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 3) {
                    PowerFlowGlyph(route: route, enabled: animationsEnabled)
                    Text(route.kind.title).foregroundStyle(.secondary)
                }
                .font(.system(size: 9))
                .lineLimit(1)
                Text(route.valueText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 3) {
                    Text(route.statusText).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected(route.kind) ? "checkmark" : "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                }.font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(isSelected(route.kind) ? route.tint.opacity(0.08) : Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isSelected(route.kind) ? route.tint.opacity(0.45) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("点击查看\(route.kind.title)的输入／输出流程")
        .accessibilityLabel("\(route.kind.title)，\(route.valueText)，\(route.statusText)")
        .accessibilityValue(isSelected(route.kind) ? "正在查看流程" : "打开流程详情")
    }

    private func isSelected(_ kind: PowerFlowKind) -> Bool {
        navigation.state.isPresented && navigation.state.currentKind == kind
    }
}
