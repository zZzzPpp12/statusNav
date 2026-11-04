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
            x: min(max(anchor.midX - width / 2, minX), maxX),
            y: min(max(anchor.minY - margin - height, minY), maxY),
            width: width, height: height
        )
    }
}
