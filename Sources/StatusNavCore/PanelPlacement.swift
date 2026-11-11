import CoreGraphics

public enum PanelPlacement {
    /// AppKit screen coordinates. Keep the complete panel inside the usable display.
    public static func frame(anchor: CGRect, contentSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let margin: CGFloat = 8
        let width = min(max(1, contentSize.width), max(1, visibleFrame.width - margin * 2))
        let height = min(max(1, contentSize.height), max(1, visibleFrame.height - margin * 2))
        let minX = visibleFrame.minX + margin
        let minY = visibleFrame.minY + margin
        let maxX = max(minX, visibleFrame.maxX - margin - width)
        let maxY = max(minY, visibleFrame.maxY - margin - height)
        return CGRect(
            // AppKit can quantize half-point screen coordinates on external displays.
            // Compare and apply the same integral origin instead of repeatedly moving by 0.5 pt.
            x: min(max(anchor.midX - width / 2, minX), maxX).rounded(.down),
            y: min(max(anchor.minY - margin - height, minY), maxY).rounded(.down),
            width: width, height: height
        )
    }
}

public enum PowerFlowPageLayout {
    public static let preferredHeight: CGFloat = 448

    /// All three routes share this viewport; the route's content never chooses the window height.
    public static func frame(anchor: CGRect, width: CGFloat, visibleFrame: CGRect,
                             maximumHeight: CGFloat? = nil) -> CGRect {
        let height = min(preferredHeight, max(1, maximumHeight ?? preferredHeight))
        return PanelPlacement.frame(anchor: anchor, contentSize: CGSize(width: width, height: height),
                                    visibleFrame: visibleFrame)
    }
}
