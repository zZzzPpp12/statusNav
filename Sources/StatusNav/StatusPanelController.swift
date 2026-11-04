import AppKit
import SwiftUI
import StatusNavCore

@MainActor
private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A clear window owns the native backdrop; the SwiftUI document keeps its full height.
@MainActor
final class StatusPanelController {
    private let panel: NSPanel
    private let hostingView: NSHostingView<PanelView>
    private let scrollView = NSScrollView()
    private weak var anchorButton: NSButton?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    var isShown: Bool { panel.isVisible }

    init(content: PanelView) {
        hostingView = NSHostingView(rootView: content)
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel = StatusPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = hostingView

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 22
            glass.contentView = scrollView
            panel.contentView = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .popover
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 22
            blur.layer?.masksToBounds = true
            scrollView.autoresizingMask = [.width, .height]
            blur.addSubview(scrollView)
            panel.contentView = blur
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refreshLayout() } }
    }

    func show(relativeTo button: NSButton) {
        anchorButton = button
        refreshLayout(force: true)
        panel.makeKeyAndOrderFront(nil)
        // Start at the header every time, including after a previously scrolled small display.
        let top = hostingView.isFlipped ? 0 : max(0, hostingView.frame.height - scrollView.contentSize.height)
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        installEventMonitors()
    }

    func close() {
        panel.orderOut(nil)
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    func stop() {
        close()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    func refreshLayout(force: Bool = false) {
        guard force || isShown, let button = anchorButton, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        hostingView.layoutSubtreeIfNeeded()
        let ideal = hostingView.fittingSize
        let contentSize = CGSize(width: ceil(ideal.width), height: ceil(ideal.height))
        let frame = PanelPlacement.frame(anchor: anchor, contentSize: contentSize, visibleFrame: visibleFrame)
        panel.setFrame(frame, display: true)
        scrollView.frame = CGRect(origin: .zero, size: frame.size)
        // Keep the document's natural height. If the display is too short, scroll rather than crop.
        hostingView.setFrameSize(CGSize(width: frame.width, height: contentSize.height))
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    var layoutDescription: String {
        let ideal = hostingView.fittingSize
        return "window=\(Int(panel.frame.width))x\(Int(panel.frame.height)), content=\(Int(ideal.width))x\(Int(ideal.height)), scrollable=\(hostingView.frame.height > scrollView.contentSize.height + 1), transparent=\(!panel.isOpaque)"
    }

    var documentFits: Bool {
        hostingView.frame.height + 1 >= hostingView.fittingSize.height
            && hostingView.frame.width + 1 >= hostingView.fittingSize.width
    }

    var contentHeight: CGFloat { hostingView.fittingSize.height }

    private func installEventMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consume = MainActor.assumeIsolated {
                guard let self, self.isShown else { return false }
                if event.type == .keyDown, event.keyCode == 53 {
                    self.close()
                    return true
                }
                // A status-item click is handled by its own toggle. Native picker menus stay open.
                if event.type != .keyDown, let window = event.window,
                   window !== self.panel, window.level == .normal {
                    self.close()
                }
                return false
            }
            return consume ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }
}
