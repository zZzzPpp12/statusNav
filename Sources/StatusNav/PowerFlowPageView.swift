import Combine
import SwiftUI
import StatusNavCore

@MainActor
final class PowerFlowNavigation: ObservableObject {
    @Published private(set) var state: PowerFlowNavigationState

    init(selection: PowerFlowKind? = nil) { state = PowerFlowNavigationState(selection: selection) }

    func open(_ kind: PowerFlowKind) {
        var next = state
        next.open(kind)
        if next != state { state = next }
    }

    func close() {
        guard state.isPresented else { return }
        state.close()
    }
}

/// This page is hosted above the overview's scroll view, inside the existing glass window.
struct PowerFlowPageView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var navigation: PowerFlowNavigation
    @ObservedObject private var telemetry: TelemetryMonitor
    var animates: Bool

    init(monitor: SystemMonitor, navigation: PowerFlowNavigation, animates: Bool = true) {
        self.monitor = monitor
        self.navigation = navigation
        telemetry = monitor.telemetry
        self.animates = animates
    }

    private var animationsEnabled: Bool {
        animates && monitor.panelVisible && navigation.state.isPresented
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: navigation.close) { Label("返回", systemImage: "chevron.left") }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    .accessibilityLabel("返回状态面板")
                Spacer()
                Text("功率流程").font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "bolt.horizontal").foregroundStyle(.secondary)
                    .frame(width: 40).accessibilityHidden(true)
            }
            BatteryPowerSummaryView(telemetry: telemetry, battery: monitor.battery,
                                    animationsEnabled: animationsEnabled, navigation: navigation)
            Divider()
            ScrollViewReader { scroll in
                ScrollView(.vertical) {
                    PowerFlowDetailView(kind: navigation.state.currentKind, power: telemetry.power,
                                        battery: monitor.battery, animationsEnabled: animationsEnabled,
                                        close: navigation.close)
                        .padding(.bottom, 2)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .id("power-flow-top")
                }
                .onChange(of: navigation.state.currentKind) { _ in
                    scroll.scrollTo("power-flow-top", anchor: .top)
                }
                .onChange(of: navigation.state.isPresented) { presented in
                    if presented { scroll.scrollTo("power-flow-top", anchor: .top) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Text("实时功率 · 约每 4 秒更新")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}
