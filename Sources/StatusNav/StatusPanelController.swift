import AppKit
import Combine
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
    private let flowHostingController: NSHostingController<PowerFlowPageView>
    private let navigation: PowerFlowNavigation
    private var navigationSubscription: AnyCancellable?
    private var hostingView: NSView { hostingController.view }
    private let scrollView = NSScrollView()
    private let surfaceView: PanelSurfaceView
    private let automaticDismissal: Bool
    private let maximumViewportHeight: CGFloat?
    private weak var anchorButton: NSButton?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var layoutRefreshScheduled = false
    private var measuredContentSize: CGSize?
    private var frozenFlowFrame: CGRect?
    private var overviewAnchor: CGRect?
    private var navigationGeneration = 0
    private var returningToOverview = false
    private(set) var frameUpdateCount = 0

    var isShown: Bool { panel.isVisible }
    var visibilityDidChange: ((Bool) -> Void)?

    init(content: PanelView, flowContent: PowerFlowPageView,
         automaticDismissal: Bool = true, maximumViewportHeight: CGFloat? = nil) {
        self.automaticDismissal = automaticDismissal
        self.maximumViewportHeight = maximumViewportHeight
        hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = [.intrinsicContentSize]
        navigation = content.navigation
        flowHostingController = NSHostingController(rootView: flowContent)
        flowHostingController.sizingOptions = []
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
        contentOwner.addChild(flowHostingController)
        surfaceView.installOverlay(flowHostingController.view)
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
        ) { [weak self] _ in Task { @MainActor in self?.screenChanged() } }
        navigationSubscription = navigation.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self, self.navigation.state == state else { return }
                self.presentNavigation(state)
            }
    }

    func show(relativeTo button: NSButton) {
        if !isShown { overviewAnchor = nil }
        anchorButton = button
        refreshLayout(force: true)
        panel.makeKeyAndOrderFront(nil)
        visibilityDidChange?(true)
        // Start at the header every time, including after a previously scrolled small display.
        let top = hostingView.isFlipped ? 0 : max(0, hostingView.frame.height - scrollView.contentSize.height)
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        if automaticDismissal { installEventMonitors() }
    }

    func close() {
        let wasVisible = isShown
        panel.orderOut(nil)
        navigation.close()
        presentNavigation(navigation.state)
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        if wasVisible { visibilityDidChange?(false) }
        overviewAnchor = nil
    }

    func stop() {
        close()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        navigationSubscription?.cancel()
    }

    func refreshLayout(force: Bool = false) {
        guard force || isShown else { return }
        if surfaceView.overlayPresented {
            surfaceView.needsLayout = true
            surfaceView.layoutSubtreeIfNeeded()
            return
        }
        layoutOverview(display: true)
    }

    private func layoutOverview(display: Bool) {
        guard let button = anchorButton, let window = button.window else { return }
        let anchor = overviewAnchor ?? window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        hostingView.layoutSubtreeIfNeeded()
        let ideal = idealContentSize
        let contentSize = CGSize(width: ceil(ideal.width), height: ceil(ideal.height))
        var viewportSize = contentSize
        if let maximumViewportHeight { viewportSize.height = min(viewportSize.height, max(1, maximumViewportHeight)) }
        let frame = PanelPlacement.frame(anchor: anchor, contentSize: viewportSize, visibleFrame: visibleFrame)
        setWindowFrame(frame)
        surfaceView.needsLayout = true
        surfaceView.layoutSubtreeIfNeeded()
        // Keep the document's natural height. If the display is too short, scroll rather than crop.
        hostingView.setFrameSize(CGSize(width: frame.width, height: contentSize.height))
        if display { panel.displayIfNeeded() }
    }

    private func setWindowFrame(_ frame: CGRect) {
        guard panel.frame != frame else { return }
        if CommandLine.arguments.contains("--smoke-test") {
            FileHandle.standardError.write(Data("Panel frame: \(panel.frame) -> \(frame)\n".utf8))
        }
        // Resize and lay out both retained surfaces before drawing, so no half-built frame is shown.
        panel.setFrame(frame, display: false)
        frameUpdateCount += 1
        panel.invalidateShadow()
    }

    var layoutDescription: String {
        let ideal = idealContentSize
        return "visible=\(isShown), window=\(Int(panel.frame.width))x\(Int(panel.frame.height)), content=\(Int(ideal.width))x\(Int(ideal.height)), document=\(hostingView.frame.size), scrollable=\(hostingView.frame.height > scrollView.contentSize.height + 1), transparentWindow=\(!panel.isOpaque), reduceTransparency=\(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency), backdrop=\(surfaceView.materialDescription), \(surfaceView.layoutDescription)"
    }

    var documentFits: Bool {
        if surfaceView.overlayPresented { return surfaceView.viewportFits && surfaceView.overlayFits }
        return abs(hostingView.frame.height - ceil(idealContentSize.height)) < 1
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
    var presentedPowerFlow: PowerFlowKind? {
        surfaceView.overlayPresented ? navigation.state.currentKind : nil
    }

    private func presentNavigation(_ state: PowerFlowNavigationState) {
        if state.isPresented {
            navigationGeneration += 1
            returningToOverview = false
            if surfaceView.overlayPresented {
                surfaceView.keepOverlayPresented()
                return
            }
            overviewAnchor = stableAnchor(for: panel.frame)
            guard let screen = panel.screen ?? anchorButton?.window?.screen ?? NSScreen.main,
                  let overviewAnchor else { return }
            let compact = PowerFlowPageLayout.frame(anchor: overviewAnchor, width: panel.frame.width,
                                                    visibleFrame: screen.visibleFrame,
                                                    maximumHeight: maximumViewportHeight)
            frozenFlowFrame = compact
            setWindowFrame(compact)
            surfaceView.presentOverlay(true)
            flowHostingController.view.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
        } else {
            guard surfaceView.overlayPresented else { return }
            if !isShown {
                navigationGeneration += 1
                returningToOverview = false
                surfaceView.presentOverlay(false)
                frozenFlowFrame = nil
                return
            }
            guard !returningToOverview else { return }
            returningToOverview = true
            navigationGeneration += 1
            let generation = navigationGeneration
            // Complete the retained overview's layout behind the visible page,
            // then swap the two content layers in a single display pass.
            surfaceView.prepareOverview()
            hostingView.layoutSubtreeIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.navigationGeneration == generation,
                      !self.navigation.state.isPresented else { return }
                self.hostingView.layoutSubtreeIfNeeded()
                if self.isShown { self.layoutOverview(display: false) }
                self.surfaceView.presentOverlay(false)
                self.returningToOverview = false
                self.frozenFlowFrame = nil
                if self.isShown { self.panel.displayIfNeeded() }
            }
        }
    }

    private func screenChanged() {
        guard isShown else { return }
        if let frozenFlowFrame, let button = anchorButton, let window = button.window,
           let screen = window.screen ?? NSScreen.main {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            let frame = PowerFlowPageLayout.frame(anchor: anchor, width: frozenFlowFrame.width,
                                                  visibleFrame: screen.visibleFrame,
                                                  maximumHeight: maximumViewportHeight)
            setWindowFrame(frame)
            self.frozenFlowFrame = frame
            overviewAnchor = stableAnchor(for: frame)
            surfaceView.needsLayout = true
            surfaceView.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
        } else {
            overviewAnchor = nil
            refreshLayout()
        }
    }

    private func stableAnchor(for frame: CGRect) -> CGRect {
        CGRect(x: frame.midX, y: frame.maxY + 8, width: 0, height: 0)
    }

    private func installEventMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consume = MainActor.assumeIsolated {
                guard let self, self.isShown else { return false }
                if event.type == .keyDown, event.keyCode == 53 {
                    if self.navigation.state.isPresented { self.navigation.close() }
                    else { self.close() }
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
