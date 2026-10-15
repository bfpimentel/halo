import QuartzCore
import Testing
@testable import Render

@MainActor
@Suite struct RenderTests {
    private func mount(_ node: Node, size: CGSize) -> RenderRoot {
        let root = RenderRoot(node: node, hostLayer: CALayer(), size: size, contentsScale: 2)
        root.layoutNow()
        return root
    }

    @Test func paintOnlyChangesSkipLayout() {
        let box = Box(style: Style(padding: Spacing(4)))
        let root = mount(box, size: CGSize(width: 100, height: 20))

        box.style.background = CGColor(gray: 0.5, alpha: 1)
        box.style.radius = 6
        box.style.opacity = 0.5
        #expect(!box.needsLayout)

        box.style.padding = Spacing(8)
        #expect(box.needsLayout)
        _ = root
    }

    @Test func textColorSkipsLayoutButContentDoesNot() {
        let label = Text("12:00")
        let root = mount(Box(children: [label]), size: CGSize(width: 200, height: 20))

        label.color = CGColor(gray: 0.2, alpha: 1)
        #expect(!label.needsLayout)

        label.text = "12:01 PM"
        #expect(label.needsLayout)
        _ = root
    }

    @Test func relayoutPushesFramesToLayers() {
        let left = Box(style: Style(width: .points(30), height: .points(10)))
        let right = Box(style: Style(width: .points(20), height: .points(10)))
        let row = Box(
            style: Style(flexDirection: .row, justify: .spaceBetween, align: .center, padding: Spacing(vertical: 0, horizontal: 10)),
            children: [left, right]
        )
        let root = mount(row, size: CGSize(width: 200, height: 32))

        #expect(row.layer.frame == CGRect(x: 0, y: 0, width: 200, height: 32))
        #expect(left.layer.frame == CGRect(x: 10, y: 11, width: 30, height: 10))
        #expect(right.layer.frame == CGRect(x: 170, y: 11, width: 20, height: 10))

        right.style.width = .points(40)
        root.size = CGSize(width: 300, height: 32)
        root.layoutNow()
        #expect(right.layer.frame == CGRect(x: 250, y: 11, width: 40, height: 10))
    }

    @Test func hitTestingReturnsTheDeepestNodeFirstAndUsesRootRelativeFrames() {
        let icon = Box(style: Style(width: .points(10), height: .points(10)))
        let button = Box(style: Style(padding: Spacing(5)), children: [icon])
        let overlapping = Box(style: Style(width: .points(30), height: .points(30)))
        let row = Box(style: Style(flexDirection: .row, padding: Spacing(left: 100)), children: [button, overlapping])
        let root = mount(row, size: CGSize(width: 300, height: 40))

        #expect(icon.frameInRoot == CGRect(x: 105, y: 5, width: 10, height: 10))
        #expect(root.hitPath(at: CGPoint(x: 107, y: 7)).map(ObjectIdentifier.init) == [icon, button, row].map(ObjectIdentifier.init))
        #expect(root.hitPath(at: CGPoint(x: 102, y: 2)).map(ObjectIdentifier.init) == [button, row].map(ObjectIdentifier.init))
        #expect(root.hitPath(at: CGPoint(x: 50, y: 10)).map(ObjectIdentifier.init) == [ObjectIdentifier(row)])
        #expect(root.hitPath(at: CGPoint(x: 500, y: 10)).isEmpty)

        overlapping.style.opacity = 0
        #expect(root.hitPath(at: CGPoint(x: 125, y: 10)).map(ObjectIdentifier.init) == [ObjectIdentifier(row)])
    }

    @Test func removingAChildDetachesItsLayer() {
        let child = Box()
        let parent = Box(children: [child])
        child.removeFromParent()
        #expect(parent.children.isEmpty)
        #expect(child.layer.superlayer == nil)
        #expect(parent.layer.sublayers?.isEmpty ?? true)
    }
}
