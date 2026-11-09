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
    private let hostingController: NSHostingController<PanelView>
    private var hostingView: NSView { hostingController.view }
    private let scrollView = NSScrollView()
    private let surfaceView: PanelSurfaceView
    private weak var anchorButton: NSButton?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var layoutRefreshScheduled = false
    private var measuredContentSize: CGSize?

    var isShown: Bool { panel.isVisible }

    init(content: PanelView) {
        hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = [.intrinsicContentSize]
        surfaceView = PanelSurfaceView(viewport: scrollView)
        panel = StatusPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
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

        let contentOwner = NSViewController()
        contentOwner.view = surfaceView
        contentOwner.addChild(hostingController)
        panel.contentViewController = contentOwner
        hostingController.rootView.contentSizeDidChange = { [weak self] size in
            guard let self, size.width > 0, size.height > 0 else { return }
            if let previous = self.measuredContentSize,
               abs(size.width - previous.width) < 0.5,
               abs(size.height - previous.height) < 0.5 { return }
            self.measuredContentSize = size
            guard !self.layoutRefreshScheduled else { return }
            self.layoutRefreshScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.layoutRefreshScheduled = false
                self.refreshLayout()
            }
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
        let ideal = idealContentSize
        let contentSize = CGSize(width: ceil(ideal.width), height: ceil(ideal.height))
        let frame = PanelPlacement.frame(anchor: anchor, contentSize: contentSize, visibleFrame: visibleFrame)
        panel.setFrame(frame, display: true)
        surfaceView.needsLayout = true
        surfaceView.layoutSubtreeIfNeeded()
        // Keep the document's natural height. If the display is too short, scroll rather than crop.
        hostingView.setFrameSize(CGSize(width: frame.width, height: contentSize.height))
        panel.invalidateShadow()
    }

    var layoutDescription: String {
        let ideal = idealContentSize
        return "window=\(Int(panel.frame.width))x\(Int(panel.frame.height)), content=\(Int(ideal.width))x\(Int(ideal.height)), document=\(hostingView.frame.size), scrollable=\(hostingView.frame.height > scrollView.contentSize.height + 1), transparentWindow=\(!panel.isOpaque), reduceTransparency=\(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency), backdrop=\(surfaceView.materialDescription), \(surfaceView.layoutDescription)"
    }

    var documentFits: Bool {
        abs(hostingView.frame.height - ceil(idealContentSize.height)) < 1
            && abs(hostingView.frame.width - ceil(idealContentSize.width)) < 1
            && surfaceView.viewportFits
    }

    // SwiftUI reports the laid-out document size, including padding. The initial
    // proposal is only needed before the first geometry report arrives.
    private var idealContentSize: CGSize {
        measuredContentSize ?? hostingController.sizeThatFits(
            in: CGSize(width: PanelView.width, height: .greatestFiniteMagnitude))
    }

    var contentHeight: CGFloat { idealContentSize.height }
    var frame: CGRect { panel.frame }

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
