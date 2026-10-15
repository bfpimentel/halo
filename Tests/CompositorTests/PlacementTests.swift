import CoreGraphics
import Testing
@testable import Compositor

private let laptop = ScreenInfo(
    id: 1,
    name: "Built-in",
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    menuBarHeight: 37,
    notch: CGRect(x: 656, y: 0, width: 200, height: 37)
)

private func place(_ config: SurfaceConfig, on screen: ScreenInfo = laptop) -> CGRect {
    Placement.frame(for: config, on: screen)
}

@Suite struct PlacementTests {
    @Test func topBarFillsWidth() {
        let config = SurfaceConfig(screen: 1, anchor: [.top, .left, .right], size: SurfaceSize(height: .fixed(32)))
        #expect(place(config) == CGRect(x: 0, y: 0, width: 1512, height: 32))
    }

    @Test func marginsInsetAnchoredEdges() {
        let config = SurfaceConfig(
            screen: 1, anchor: [.top, .left, .right],
            margins: Insets(top: 4, right: 8, left: 8),
            size: SurfaceSize(height: .fixed(32))
        )
        #expect(place(config) == CGRect(x: 8, y: 4, width: 1496, height: 32))
    }

    @Test func singleAnchorsPinToTheirEdge() {
        let topRight = SurfaceConfig(
            screen: 1, anchor: [.top, .right], margins: Insets(right: 10),
            size: SurfaceSize(width: .fixed(200), height: .fixed(30))
        )
        #expect(place(topRight) == CGRect(x: 1302, y: 0, width: 200, height: 30))

        let bottom = SurfaceConfig(screen: 1, anchor: [.bottom, .left, .right], size: SurfaceSize(height: .fixed(40)))
        #expect(place(bottom) == CGRect(x: 0, y: 942, width: 1512, height: 40))
    }

    @Test func noAnchorCenters() {
        let config = SurfaceConfig(screen: 1, size: SurfaceSize(width: .fixed(400), height: .fixed(200)))
        #expect(place(config) == CGRect(x: 556, y: 391, width: 400, height: 200))
    }

    @Test func fixedSizeIsClampedToAvailableSpace() {
        let config = SurfaceConfig(
            screen: 1, anchor: [.left], margins: Insets(right: 12, left: 12),
            size: SurfaceSize(width: .fixed(5000), height: .fixed(10))
        )
        #expect(place(config).width == 1488)
    }

    @Test func avoidMenuBarStartsBelowIt() {
        let config = SurfaceConfig(
            screen: 1, anchor: [.top, .left, .right],
            size: SurfaceSize(height: .fixed(32)), avoid: .menuBar
        )
        #expect(place(config) == CGRect(x: 0, y: 37, width: 1512, height: 32))
    }

    @Test func avoidMenuBarIsNoopWhenItAutoHides() {
        var screen = laptop
        screen.menuBarHeight = 0
        let config = SurfaceConfig(
            screen: 1, anchor: [.top, .left, .right],
            size: SurfaceSize(height: .fixed(32)), avoid: .menuBar
        )
        #expect(place(config, on: screen).minY == 0)
    }

    @Test func avoidNotchMovesFullWidthBarBelowIt() {
        let config = SurfaceConfig(
            screen: 1, anchor: [.top, .left, .right],
            size: SurfaceSize(height: .fixed(32)), avoid: .notch
        )
        #expect(place(config) == CGRect(x: 0, y: 37, width: 1512, height: 32))
    }

    @Test func avoidNotchShrinksSingleSidedSurfaces() {
        let left = SurfaceConfig(
            screen: 1, anchor: [.top, .left],
            size: SurfaceSize(width: .fixed(1000), height: .fixed(32)), avoid: .notch
        )
        #expect(place(left) == CGRect(x: 0, y: 0, width: 656, height: 32))

        let right = SurfaceConfig(
            screen: 1, anchor: [.top, .right],
            size: SurfaceSize(width: .fixed(1000), height: .fixed(32)), avoid: .notch
        )
        #expect(place(right) == CGRect(x: 856, y: 0, width: 656, height: 32))
    }

    @Test func avoidNotchIgnoresSurfacesThatDontTouchIt() {
        let config = SurfaceConfig(
            screen: 1, anchor: [.top, .left],
            size: SurfaceSize(width: .fixed(300), height: .fixed(32)), avoid: .notch
        )
        #expect(place(config) == CGRect(x: 0, y: 0, width: 300, height: 32))
    }

    @Test func secondaryScreenUsesItsOwnOrigin() {
        let external = ScreenInfo(id: 2, name: "External", frame: CGRect(x: 1512, y: -200, width: 1920, height: 1080))
        let config = SurfaceConfig(screen: 2, anchor: [.top, .left, .right], size: SurfaceSize(height: .fixed(32)))
        #expect(place(config, on: external) == CGRect(x: 1512, y: -200, width: 1920, height: 32))
    }
}

@Suite struct GeometryTests {
    @Test func flipsBetweenAppKitAndTopLeft() {
        let appKitBottomBar = CGRect(x: 0, y: 0, width: 1512, height: 32)
        let topLeft = Geometry.appKitToTopLeft(appKitBottomBar, primaryHeight: 982)
        #expect(topLeft == CGRect(x: 0, y: 950, width: 1512, height: 32))
        #expect(Geometry.topLeftToAppKit(topLeft, primaryHeight: 982) == appKitBottomBar)
    }

    @Test func screenAbovePrimaryHasNegativeTopLeftY() {
        let appKitAbove = CGRect(x: 0, y: 982, width: 1920, height: 1080)
        #expect(Geometry.appKitToTopLeft(appKitAbove, primaryHeight: 982).minY == -1080)
    }
}
