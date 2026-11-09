import AppKit
import Combine
import SwiftUI

@main
enum StatusNavMain {
    @MainActor
    static func main() {
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
    private var statusItem: NSStatusItem!
    private var statusPanel: StatusPanelController!
    private var preferencesWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.render() }
            }
        }
        statusPanel = StatusPanelController(content: PanelView(
            monitor: monitor, audio: monitor.audio,
            openSettings: { [weak self] in self?.showPreferences() },
            quit: { NSApp.terminate(nil) },
            expandedDetails: CommandLine.arguments.contains("--preview-details")
        ), automaticDismissal: !CommandLine.arguments.contains("--smoke-test"),
           maximumViewportHeight: CommandLine.arguments.contains("--smoke-test")
               && CommandLine.arguments.contains("--preview-short") ? 400 : nil)
        Publishers.MergeMany([
            monitor.objectWillChange.eraseToAnyPublisher(),
            monitor.audio.objectWillChange.eraseToAnyPublisher(),
            monitor.inputAudio.objectWillChange.eraseToAnyPublisher(),
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
        try? await Task.sleep(for: .seconds(2))
        statusPanel.refreshLayout()
        await waitForPanelLayout { self.statusPanel.documentFits }
        precondition(statusPanel.isShown, "The panel must remain visible during the layout check")
        print("Panel layout: \(statusPanel.layoutDescription)")
        if CommandLine.arguments.contains("--preview-short") {
            precondition(statusPanel.frame.height <= 400, "The short viewport must stay bounded")
            precondition(statusPanel.contentHeight > statusPanel.frame.height, "Long content must be scrollable")
        }
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
        if let index = CommandLine.arguments.firstIndex(of: "--preview-directory"),
           CommandLine.arguments.indices.contains(index + 1) {
            exportPreviews(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
        }
        print("Panel smoke test passed")
        NSApp.terminate(nil)
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
                        let view = NSHostingView(rootView: PanelView(monitor: monitor, audio: monitor.audio,
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
        toggleStatusPanel()
        return false
    }

    private func render() {
        guard let button = statusItem?.button else { return }
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            button.image = IconRenderer.image(battery: monitor.battery, network: monitor.network,
                volume: monitor.audio.volume, muted: monitor.audio.muted,
                size: settings.iconSize, colorful: settings.colorful)
        }
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.title = settings.showPercentage ? monitor.battery.percentage.map { " \($0)%" } ?? "" : ""
        let batteryText = monitor.battery.percentage.map { "电量 \($0)%" } ?? "无内置电池"
        let description = "StatusNav · \(batteryText) · \(monitor.network.title) · \(monitor.audio.muted ? "已静音" : "音量 \(Int(monitor.audio.volume * 100))%")"
        button.toolTip = description
        button.setAccessibilityLabel(description)
        let desired: NSApplication.ActivationPolicy = settings.showDock ? .regular : .accessory
        if NSApp.activationPolicy() != desired { NSApp.setActivationPolicy(desired) }
        if settings.showDock {
            NSApp.applicationIconImage = IconRenderer.image(battery: monitor.battery, network: monitor.network,
                volume: monitor.audio.volume, muted: monitor.audio.muted,
                size: 26, colorful: settings.colorful, dock: true)
        }
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
            let quit = NSMenuItem(title: "退出 StatusNav", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp
            menu.addItem(quit)
            if let button = statusItem.button { menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.height), in: button) }
        } else { toggleStatusPanel() }
    }

    private func toggleStatusPanel() {
        if statusPanel.isShown { statusPanel.close(); return }
        guard let button = statusItem.button else { return }
        monitor.refresh()
        statusPanel.show(relativeTo: button)
    }

    @objc private func showPreferences() {
        statusPanel.close()
        if preferencesWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 360),
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
