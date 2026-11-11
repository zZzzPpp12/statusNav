import CoreGraphics
import Testing
@testable import StatusNavCore

@Test func fractionalStatusItemAnchorsProduceStableIntegralWindowOrigins() {
    let screen = CGRect(x: 0, y: 0, width: 2560, height: 1400)
    let frame = PanelPlacement.frame(anchor: CGRect(x: 1480, y: 1400, width: 31, height: 25),
                                     contentSize: CGSize(width: 336, height: 828), visibleFrame: screen)
    #expect(frame.minX == frame.minX.rounded(.down))
    #expect(frame.minY == frame.minY.rounded(.down))
    #expect(frame.size == CGSize(width: 336, height: 828))
    #expect(screen.contains(frame))
}

@Test func panelStaysBelowTheMenuBarAndInsideTheRightEdge() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let frame = PanelPlacement.frame(anchor: CGRect(x: 1410, y: 875, width: 30, height: 25),
                                     contentSize: CGSize(width: 340, height: 410), visibleFrame: screen)
    #expect(frame.width == 340)
    #expect(frame.height == 410)
    #expect(frame.maxX <= screen.maxX - 8)
    #expect(frame.maxY <= screen.maxY - 8)
    #expect(screen.contains(frame))
}

@Test func shortDisplaysLimitTheViewportRatherThanTheContentMeasurement() {
    let screen = CGRect(x: 0, y: 0, width: 1024, height: 300)
    let frame = PanelPlacement.frame(anchor: CGRect(x: 500, y: 300, width: 30, height: 25),
                                     contentSize: CGSize(width: 340, height: 600), visibleFrame: screen)
    #expect(frame.height == 284)
    #expect(screen.contains(frame))
}

@Test func secondaryDisplaysUseTheirOwnCoordinateOrigin() {
    let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1055)
    let frame = PanelPlacement.frame(anchor: CGRect(x: -1900, y: 855, width: 30, height: 25),
                                     contentSize: CGSize(width: 340, height: 410), visibleFrame: screen)
    #expect(frame.minX == screen.minX + 8)
    #expect(screen.contains(frame))
}

@Test func expandingContentPreservesTheTopAnchor() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let anchor = CGRect(x: 900, y: 875, width: 30, height: 25)
    let initial = PanelPlacement.frame(anchor: anchor, contentSize: CGSize(width: 340, height: 400), visibleFrame: screen)
    let expanded = PanelPlacement.frame(anchor: anchor, contentSize: CGSize(width: 340, height: 470), visibleFrame: screen)
    #expect(initial.maxY == expanded.maxY)
    #expect(expanded.height == 470)
}
