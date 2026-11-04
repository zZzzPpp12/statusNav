import AppKit
import Combine
import SwiftUI

@main
enum StatusNavMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
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
    private let popover = NSPopover()
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
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PanelView(
            monitor: monitor, audio: monitor.audio,
            openSettings: { [weak self] in self?.showPreferences() },
            quit: { NSApp.terminate(nil) }
        ))
        Publishers.MergeMany([
            monitor.objectWillChange.eraseToAnyPublisher(),
            monitor.audio.objectWillChange.eraseToAnyPublisher(),
            settings.objectWillChange.eraseToAnyPublisher()
        ])
        .debounce(for: .milliseconds(40), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.render() }
        .store(in: &subscriptions)
        monitor.start()
        render()
        if CommandLine.arguments.contains("--smoke-test") {
            print("StatusNav ready: battery=\(monitor.battery.percentage != nil), audioOutputs=\(monitor.audio.devices.count), statusIcon=\(statusItem.button?.image != nil)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                if let index = CommandLine.arguments.firstIndex(of: "--preview-directory"),
                   CommandLine.arguments.indices.contains(index + 1) {
                    self?.exportPreviews(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
                }
                NSApp.terminate(nil)
            }
        }
    }

    private func exportPreviews(to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                let view = NSHostingView(rootView: PanelView(monitor: monitor, audio: monitor.audio,
                    openSettings: {}, quit: {}).environment(\.colorScheme, scheme)
                    .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.98)))
                view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                view.setFrameSize(view.fittingSize)
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: directory.appendingPathComponent("panel-\(name).png"))
                }
            }
            print("Previews exported to \(directory.path)")
        } catch {
            fputs("Preview export failed: \(error.localizedDescription)\n", stderr)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        appearanceObservation = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        togglePopover()
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
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            let menu = NSMenu()
            let preferences = NSMenuItem(title: "偏好设置…", action: #selector(showPreferences), keyEquivalent: ",")
            preferences.target = self
            menu.addItem(preferences)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "退出 StatusNav", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp
            menu.addItem(quit)
            if let button = statusItem.button { menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.height), in: button) }
        } else { togglePopover() }
    }

    private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        monitor.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func showPreferences() {
        popover.performClose(nil)
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
