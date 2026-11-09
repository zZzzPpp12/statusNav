import AppKit

/// Owns the material and the viewport without exposing the document's intrinsic size to the window.
@MainActor
final class PanelSurfaceView: NSView {
    private let material: NSView
    private let contentContainer = NSView()
    private let viewport: NSView
    static let cornerRadius: CGFloat = 16

    init(viewport: NSView) {
        self.viewport = viewport
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = contentContainer
            material = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .popover
            blur.blendingMode = .behindWindow
            blur.state = .active
            material = blur
        }
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true
        material.autoresizingMask = [.width, .height]
        contentContainer.autoresizingMask = [.width, .height]
        addSubview(material)

        // The classic material sits behind its content; Liquid Glass owns its content container.
        if material is NSVisualEffectView {
            addSubview(contentContainer)
        }
        viewport.autoresizingMask = [.width, .height]
        contentContainer.addSubview(viewport)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        material.frame = bounds
        material.layoutSubtreeIfNeeded()
        // Set the viewport geometry in the same pass as the surface resize. Relying
        // only on autoresizing can leave the old height until the next AppKit pass.
        contentContainer.frame = bounds
        viewport.frame = contentContainer.bounds
    }

    var materialDescription: String {
        if #available(macOS 26.0, *), material is NSGlassEffectView { return "Liquid Glass (regular)" }
        return "Popover material (behind window)"
    }

    var viewportFits: Bool {
        abs(viewport.frame.width - bounds.width) < 1
            && abs(viewport.frame.height - bounds.height) < 1
    }

    var layoutDescription: String {
        "surface=\(bounds.size), container=\(contentContainer.frame), viewport=\(viewport.frame)"
    }
}
