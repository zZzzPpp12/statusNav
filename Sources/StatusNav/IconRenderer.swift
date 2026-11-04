import AppKit
import StatusNavCore

@MainActor
enum IconRenderer {
    static func image(battery: BatteryState, network: NetworkState, volume: Double,
                      muted: Bool, size: CGFloat, colorful: Bool, dock: Bool = false) -> NSImage {
        let canvas = dock ? CGSize(width: 256, height: 256) : CGSize(width: size + 2, height: 24)
        let image = NSImage(size: canvas)
        image.lockFocus()
        if dock {
            let background = NSBezierPath(roundedRect: CGRect(x: 12, y: 12, width: 232, height: 232), xRadius: 54, yRadius: 54)
            NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.17, alpha: 1).setFill()
            background.fill()
        }
        let scale = dock ? CGFloat(7.5) : min(size / 32, 1)
        let center = CGPoint(x: canvas.width / 2, y: dock ? 140 : 13)
        let foreground: NSColor = dock ? .white : .labelColor
        let tint: NSColor = !colorful ? foreground : battery.isLow ? .systemOrange
            : battery.charging ? .systemGreen : foreground
        let radius = 10 * scale
        let track = NSBezierPath()
        track.lineWidth = 2.1 * scale
        track.lineCapStyle = .round
        track.appendArc(withCenter: center, radius: radius, startAngle: -35, endAngle: 215, clockwise: false)
        foreground.withAlphaComponent(0.18).setStroke()
        track.stroke()
        let progress = battery.percentage == nil ? 1 : battery.progress
        if progress > 0 {
            let arc = NSBezierPath()
            arc.lineWidth = 2.1 * scale
            arc.lineCapStyle = .round
            arc.appendArc(withCenter: center, radius: radius, startAngle: 215,
                          endAngle: 215 - 250 * progress, clockwise: true)
            tint.setStroke()
            arc.stroke()
        }
        let symbolName = battery.charging ? "bolt.fill" : network.symbol
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 10 * scale, weight: .semibold)
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) {
            let rect = CGRect(x: center.x - 6 * scale, y: center.y - 4.3 * scale, width: 12 * scale, height: 9 * scale)
            let tinted = NSImage(size: rect.size)
            tinted.lockFocus()
            foreground.setFill()
            CGRect(origin: .zero, size: rect.size).fill()
            symbol.draw(in: CGRect(origin: .zero, size: rect.size), from: .zero, operation: .destinationIn, fraction: 1)
            tinted.unlockFocus()
            tinted.draw(in: rect)
        }
        let dots = VolumeScale.activeDots(volume: volume, muted: muted)
        for index in 0..<4 {
            let x = center.x + (CGFloat(index) - 1.5) * 4 * scale
            let rect = CGRect(x: x - 1.05 * scale, y: center.y - 11.3 * scale, width: 2.1 * scale, height: 2.1 * scale)
            foreground.withAlphaComponent(index < dots ? 1 : 0.22).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
        image.unlockFocus()
        image.isTemplate = !dock && !colorful
        return image
    }
}
