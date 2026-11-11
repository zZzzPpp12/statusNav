import AppKit
import Combine
import SwiftUI
import StatusNavCore

@main
enum StatusNavMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--smoke-test"), CommandLine.arguments.contains("--preview-readouts") {
            var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            arguments["showBatteryPowerInMenuBar"] = true
            arguments["showNetworkRatesInMenuBar"] = true
            UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--replace"), let bundleID = Bundle.main.bundleIdentifier {
            for instance in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                where instance.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                instance.terminate()
            }
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = SystemMonitor()
    private let settings = SettingsStore()
    private let flowNavigation = PowerFlowNavigation()
    private var statusItem: NSStatusItem!
    private var statusPanel: StatusPanelController!
    private var preferencesWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    private var appearanceObservation: NSKeyValueObservation?
    private var lastIconState: IconState?
    private var dockIconVisible = false
    private var renderCount = 0

    private struct IconState: Equatable {
        let percentage: Int?
        let charging: Bool
        let low: Bool
        let networkSymbol: String
        let volumeDots: Int
        let size: Double
        let colorful: Bool
        let appearance: NSAppearance.Name?
    }

    private func appearanceMatch(_ button: NSButton) -> NSAppearance.Name? {
        button.effectiveAppearance.bestMatch(from: [.accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastAqua, .darkAqua, .aqua])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    guard let self, let button = self.statusItem?.button,
                          self.lastIconState?.appearance != self.appearanceMatch(button) else { return }
                    self.render()
                }
            }
        }
        statusPanel = StatusPanelController(content: PanelView(
            monitor: monitor, audio: monitor.audio, settings: settings, navigation: flowNavigation,
            openSettings: { [weak self] in self?.showPreferences() },
            quit: { NSApp.terminate(nil) },
            expandedDetails: CommandLine.arguments.contains("--preview-details")
        ), flowContent: PowerFlowPageView(monitor: monitor, navigation: flowNavigation),
           automaticDismissal: !CommandLine.arguments.contains("--smoke-test"),
           maximumViewportHeight: CommandLine.arguments.contains("--smoke-test")
               && CommandLine.arguments.contains("--preview-short") ? 400 : nil)
        statusPanel.visibilityDidChange = { [weak self] in self?.monitor.setPanelVisible($0) }
        monitor.configure(settings: settings)
        Publishers.MergeMany([
            monitor.objectWillChange.eraseToAnyPublisher(),
            monitor.audio.objectWillChange.eraseToAnyPublisher(),
            monitor.inputAudio.objectWillChange.eraseToAnyPublisher(),
            monitor.telemetry.objectWillChange.eraseToAnyPublisher(),
            monitor.bluetooth.objectWillChange.eraseToAnyPublisher(),
            settings.objectWillChange.eraseToAnyPublisher()
        ])
        .debounce(for: .milliseconds(40), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.render() }
        .store(in: &subscriptions)
        monitor.start()
        render()
        if CommandLine.arguments.contains("--show-panel"), let button = statusItem.button {
            statusPanel.show(relativeTo: button)
        }
        if CommandLine.arguments.contains("--smoke-test") {
            print("StatusNav ready: battery=\(monitor.battery.percentage != nil), audioOutputs=\(monitor.audio.devices.count), audioInputs=\(monitor.inputAudio.devices.count), statusIcon=\(statusItem.button?.image != nil)")
            if let button = statusItem.button { statusPanel.show(relativeTo: button) }
            Task { @MainActor [weak self] in await self?.runSmokeTest() }
        }
    }

    private func runSmokeTest() async {
        try? await Task.sleep(for: .seconds(6))
        for _ in 0..<80 {
            if !monitor.bluetooth.loading { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        monitor.stop(preserveReadings: true)
        print("Telemetry: Bluetooth devices=\(monitor.bluetooth.snapshot.devices.count), systemPower=\(monitor.telemetry.power.systemWatts != nil), displayPower=\(monitor.telemetry.power.displayWatts != nil), portChannels=\(monitor.telemetry.power.portWatts.count), batteryPower=\(monitor.telemetry.power.batteryNetWatts != nil), apps=\(monitor.telemetry.applications.count), traffic=\(monitor.telemetry.rates != nil)")
        let backlight = monitor.telemetry.power.backlight
        print("Backlight: source=\(backlight.powerSource ?? "none"), rejectedZero=\(backlight.rejectedZero), brightness=\(backlight.brightnessPercent.map { String(format: "%.0f%%", $0) } ?? "unknown"), nits=\(backlight.brightnessNits.map { String(format: "%.1f", $0) } ?? "unknown"), driveMilliamps=\(backlight.driveMilliamps.map { String(format: "%.3f", $0) } ?? "unknown")")
        statusPanel.refreshLayout()
        await waitForPanelLayout { self.statusPanel.documentFits }
        precondition(statusPanel.isShown, "The panel must remain visible during the layout check")
        render()
        let title = statusItem.button?.title ?? ""
        print("Menu readouts: power=\(settings.showBatteryPowerInMenuBar), traffic=\(settings.showNetworkRatesInMenuBar), title=\(title)")
        if CommandLine.arguments.contains("--preview-readouts") {
            precondition(title.contains("W") && title.contains("↓"), "Enabled readouts must reach the native status item")
        }
        print("Panel layout: \(statusPanel.layoutDescription)")
        if CommandLine.arguments.contains("--preview-short") {
            precondition(statusPanel.frame.height <= 400, "The short viewport must stay bounded")
            precondition(statusPanel.contentHeight > statusPanel.frame.height, "Long content must be scrollable")
        }
        await checkPinnedPowerFlows()
        let rendersBeforeIdle = renderCount
        try? await Task.sleep(for: .milliseconds(400))
        precondition(renderCount - rendersBeforeIdle <= 3, "Paused sampling must not cause an appearance redraw loop")
        print("Idle redraw check passed: \(renderCount - rendersBeforeIdle) renders")
        let initialHeight = statusPanel.contentHeight
        let initialFrame = statusPanel.frame

        monitor.audio.error = String(repeating: "设备状态暂时不可用，请稍后重试。", count: 5)
        await waitForPanelLayout {
            self.statusPanel.contentHeight > initialHeight && self.statusPanel.documentFits
        }
        print("Expanded panel: \(statusPanel.layoutDescription)")
        precondition(abs(statusPanel.frame.maxY - initialFrame.maxY) < 1,
                     "Growing content must preserve the menu-bar anchor")

        monitor.audio.error = nil
        await waitForPanelLayout {
            abs(self.statusPanel.contentHeight - initialHeight) < 1 && self.statusPanel.documentFits
        }
        precondition(abs(statusPanel.frame.maxY - initialFrame.maxY) < 1,
                     "Shrinking content must preserve the menu-bar anchor")
        statusPanel.close()
        precondition(!statusPanel.isShown)
        if let button = statusItem.button { statusPanel.show(relativeTo: button) }
        precondition(statusPanel.isShown)
        if let kind = previewPowerFlow {
            flowNavigation.open(kind)
            await waitForPanelLayout { self.statusPanel.presentedPowerFlow == kind && self.statusPanel.documentFits }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--preview-directory"),
           CommandLine.arguments.indices.contains(index + 1) {
            exportPreviews(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
        }
        FileHandle.standardOutput.write(Data("Panel smoke test passed\n".utf8))
        if !CommandLine.arguments.contains("--hold-after-test") { NSApp.terminate(nil) }
    }

    private var previewPowerFlow: PowerFlowKind? {
        guard CommandLine.arguments.contains("--smoke-test"),
              let index = CommandLine.arguments.firstIndex(of: "--preview-power-flow"),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return PowerFlowKind(rawValue: CommandLine.arguments[index + 1])
    }

    private func checkPinnedPowerFlows() async {
        let originalFrame = statusPanel.frame
        let frameChanges = statusPanel.frameUpdateCount
        for _ in 0..<3 {
            for kind in PowerFlowKind.allCases {
                flowNavigation.open(kind)
                await waitForPanelLayout { self.statusPanel.presentedPowerFlow == kind && self.statusPanel.documentFits }
                try? await Task.sleep(for: .milliseconds(50))
                precondition(statusPanel.frame == originalFrame, "Switching flow pages must keep the window fixed")
                precondition(statusPanel.frameUpdateCount == frameChanges, "Flow pages must not resize the native window")
                precondition(statusPanel.isShown, "Flow navigation must not hide the window")
            }
        }
        flowNavigation.open(.charger)
        flowNavigation.close()
        flowNavigation.open(.battery)
        flowNavigation.open(.system)
        await waitForPanelLayout { self.statusPanel.presentedPowerFlow == .system && self.statusPanel.documentFits }
        let originalTitle = statusItem.button?.title ?? ""
        statusItem.button?.title = originalTitle + "      "
        try? await Task.sleep(for: .milliseconds(200))
        flowNavigation.close()
        await waitForPanelLayout { self.statusPanel.presentedPowerFlow == nil && self.statusPanel.documentFits }
        statusItem.button?.title = originalTitle
        try? await Task.sleep(for: .milliseconds(100))
        statusPanel.refreshLayout()
        precondition(statusPanel.frame == originalFrame, "Returning to the overview must preserve its frame")
        precondition(statusPanel.frameUpdateCount == frameChanges, "Returning must not trigger intermediate native resizes")
        FileHandle.standardOutput.write(Data("Pinned power flow checks passed: repeated/rapid switches and status-item width changes, zero native frame changes\n".utf8))
    }

    private func waitForPanelLayout(_ condition: () -> Bool) async {
        // Observe natural layout convergence instead of forcing a layout that
        // could hide a missing resize notification in the real application.
        for _ in 0..<40 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if !condition() {
            let message = "Panel layout did not settle: \(statusPanel.layoutDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            preconditionFailure(message)
        }
    }

    private func exportPreviews(to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                for (layout, expanded) in [("summary", false), ("details", true)] {
                    for (surface, background) in [("content", Color.clear),
                        ("layout", scheme == .dark ? Color(white: 0.13) : Color(white: 0.98))] {
                        let view = NSHostingView(rootView: PanelView(monitor: monitor, audio: monitor.audio, settings: settings,
                            navigation: PowerFlowNavigation(),
                            openSettings: {}, quit: {}, expandedDetails: expanded)
                            .environment(\.colorScheme, scheme).background(background))
                        view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                        view.setFrameSize(view.fittingSize)
                        view.layoutSubtreeIfNeeded()
                        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        if let png = bitmap.representation(using: .png, properties: [:]) {
                            try png.write(to: directory.appendingPathComponent("panel-\(surface)-\(layout)-\(name).png"))
                        }
                    }
                }
            }
            for kind in PowerFlowKind.allCases {
                for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                    let view = NSHostingView(rootView: PowerFlowPageView(
                        monitor: monitor, navigation: PowerFlowNavigation(selection: kind), animates: false)
                        .frame(width: PanelView.width, height: 500)
                        .environment(\.colorScheme, scheme)
                        .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.98)))
                    view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                    view.setFrameSize(view.fittingSize)
                    view.layoutSubtreeIfNeeded()
                    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        try png.write(to: directory.appendingPathComponent("power-flow-\(kind.rawValue)-\(name).png"))
                    }
                }
            }
            print("Previews exported to \(directory.path); content is transparent, layout adds a QA canvas, neither captures live glass")
        } catch {
            fputs("Preview export failed: \(error.localizedDescription)\n", stderr)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        statusPanel?.stop()
        appearanceObservation = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if CommandLine.arguments.contains("--smoke-test"), let button = statusItem.button {
            statusPanel.show(relativeTo: button)
            return false
        }
        toggleStatusPanel()
        return false
    }

    private func render() {
        renderCount += 1
        monitor.configure(settings: settings)
        guard let button = statusItem?.button else { return }
        let iconState = IconState(percentage: monitor.battery.percentage, charging: monitor.battery.charging,
            low: monitor.battery.isLow, networkSymbol: monitor.network.symbol,
            volumeDots: VolumeScale.activeDots(volume: monitor.audio.volume, muted: monitor.audio.muted),
            size: settings.iconSize, colorful: settings.colorful, appearance: appearanceMatch(button))
        let iconChanged = iconState != lastIconState
        if iconChanged {
            lastIconState = iconState
            button.effectiveAppearance.performAsCurrentDrawingAppearance {
                button.image = IconRenderer.image(battery: monitor.battery, network: monitor.network,
                    volume: monitor.audio.volume, muted: monitor.audio.muted,
                    size: settings.iconSize, colorful: settings.colorful)
            }
        }
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let title = MenuReadout.text(percentage: monitor.battery.percentage, showPercentage: settings.showPercentage,
            batteryNetWatts: monitor.telemetry.power.batteryNetWatts, showPower: settings.showBatteryPowerInMenuBar,
            rates: monitor.telemetry.rates, showRates: settings.showNetworkRatesInMenuBar)
        if button.title != title { button.title = title }
        let batteryText = monitor.battery.percentage.map { "电量 \($0)%" } ?? "无内置电池"
        let readouts = MenuReadout.text(percentage: nil, showPercentage: false,
            batteryNetWatts: monitor.telemetry.power.batteryNetWatts, showPower: settings.showBatteryPowerInMenuBar,
            rates: monitor.telemetry.rates, showRates: settings.showNetworkRatesInMenuBar)
        let description = "StatusNav · \(batteryText) · \(monitor.network.title) · \(monitor.audio.muted ? "已静音" : "音量 \(Int(monitor.audio.volume * 100))%")"
        button.toolTip = description + readouts
        button.setAccessibilityLabel(description + readouts)
        let desired: NSApplication.ActivationPolicy = settings.showDock ? .regular : .accessory
        if NSApp.activationPolicy() != desired { NSApp.setActivationPolicy(desired) }
        if settings.showDock && (iconChanged || !dockIconVisible) {
            NSApp.applicationIconImage = IconRenderer.image(battery: monitor.battery, network: monitor.network,
                volume: monitor.audio.volume, muted: monitor.audio.muted,
                size: 26, colorful: settings.colorful, dock: true)
        }
        dockIconVisible = settings.showDock
        statusPanel?.refreshLayout()
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusPanel.close()
            let menu = NSMenu()
            let preferences = NSMenuItem(title: "偏好设置…", action: #selector(showPreferences), keyEquivalent: ",")
            preferences.target = self
            menu.addItem(preferences)
            menu.addItem(.separator())
            let power = NSMenuItem(title: "显示电池功耗", action: #selector(togglePowerReadout), keyEquivalent: "")
            power.target = self; power.state = settings.showBatteryPowerInMenuBar ? .on : .off
            menu.addItem(power)
            let traffic = NSMenuItem(title: "显示网络上下行速率", action: #selector(toggleTrafficReadout), keyEquivalent: "")
            traffic.target = self; traffic.state = settings.showNetworkRatesInMenuBar ? .on : .off
            menu.addItem(traffic)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "退出 StatusNav", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp
            menu.addItem(quit)
            if let button = statusItem.button { menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.height), in: button) }
        } else { toggleStatusPanel() }
    }

    @objc private func togglePowerReadout() { settings.showBatteryPowerInMenuBar.toggle() }
    @objc private func toggleTrafficReadout() { settings.showNetworkRatesInMenuBar.toggle() }

    private func toggleStatusPanel() {
        if statusPanel.isShown { statusPanel.close(); return }
        guard let button = statusItem.button else { return }
        monitor.refresh()
        statusPanel.show(relativeTo: button)
    }

    @objc private func showPreferences() {
        statusPanel.close()
        if preferencesWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 440, height: 500),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "StatusNav 偏好设置"
            window.contentViewController = NSHostingController(rootView: PreferencesView(settings: settings))
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
}
