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

    @Test func absoluteChildrenLeaveTheFlowAndPlaceByTheirEdges() {
        let first = Box(style: Style(width: .points(40), height: .points(20)))
        let badge = Box(style: Style(width: .points(10), height: .points(10), position: .absolute, top: .points(-4), right: .points(-4)))
        let label = Box(style: Style(height: .points(12), position: .absolute, top: .percent(50), right: .points(0), left: .points(0)))
        let second = Box(style: Style(width: .points(40), height: .points(20)))
        let column = Box(
            style: Style(padding: Spacing(10), width: .points(100)), children: [first, badge, label, second]
        )
        _ = mount(Box(style: Style(align: .start), children: [Box(style: Style(flexDirection: .row, align: .start), children: [column])]), size: CGSize(width: 300, height: 300))

        #expect(second.layoutFrame.origin == CGPoint(x: 10, y: 30), "absolute siblings take no space")
        #expect(column.layoutFrame.height == 60)
        #expect(badge.layoutFrame == CGRect(x: 94, y: -4, width: 10, height: 10), "edges measure from the border, past padding")
        #expect(label.layoutFrame == CGRect(x: 0, y: 30, width: 100, height: 12), "left + right stretch it; % of the parent")
    }

    @Test func overlaysAreHitOnTopIncludingOutsideTheirParent() {
        let icon = Box(style: Style(width: .points(30), height: .points(30)))
        let badge = Box(style: Style(width: .points(10), height: .points(10), position: .absolute, top: .points(-5), right: .points(-5)))
        let wrapper = Box(style: Style(width: .points(30), height: .points(30)), children: [icon, badge])
        let row = Box(style: Style(flexDirection: .row, padding: Spacing(20)), children: [wrapper])
        let root = mount(row, size: CGSize(width: 200, height: 200))

        let ids = { (nodes: [Node]) in nodes.map(ObjectIdentifier.init) }
        #expect(ids(root.hitPath(at: CGPoint(x: 47, y: 18))) == ids([badge, wrapper, row]), "over the icon's corner")
        #expect(ids(root.hitPath(at: CGPoint(x: 53, y: 16))) == ids([badge, wrapper, row]), "the overhang outside the wrapper")
        #expect(ids(root.hitPath(at: CGPoint(x: 30, y: 30))) == ids([icon, wrapper, row]))
    }

    @Test func clippedChildrenAreOnlyHitInsideTheRoundedShape() {
        let fill = Box(style: Style(width: .points(40), height: .points(40)))
        let badge = Box(style: Style(width: .points(10), height: .points(10), position: .absolute, top: .points(-5), right: .points(-5)))
        let card = Box(style: Style(width: .points(40), height: .points(40), radius: 10, clip: true), children: [fill, badge])
        let row = Box(style: Style(flexDirection: .row, padding: Spacing(20)), children: [card])
        let root = mount(row, size: CGSize(width: 200, height: 200))

        let ids = { (nodes: [Node]) in nodes.map(ObjectIdentifier.init) }
        #expect(ids(root.hitPath(at: CGPoint(x: 40, y: 40))) == ids([fill, card, row]))
        #expect(ids(root.hitPath(at: CGPoint(x: 62, y: 17))) == ids([row]), "the overhang is clipped away")
        #expect(ids(root.hitPath(at: CGPoint(x: 21, y: 21))) == ids([row]), "outside the rounded corner")
        #expect(ids(root.hitPath(at: CGPoint(x: 21, y: 40))) == ids([fill, card, row]), "inside, along the straight edge")

        card.style.corners = [.bottomLeft, .bottomRight]
        #expect(ids(root.hitPath(at: CGPoint(x: 21, y: 21))) == ids([fill, card, row]), "a square top corner")
        #expect(ids(root.hitPath(at: CGPoint(x: 21, y: 59))) == ids([row]), "still outside a rounded bottom corner")

        card.style.clip = false
        #expect(ids(root.hitPath(at: CGPoint(x: 62, y: 17))) == ids([badge, card, row]))
    }

    @Test func hitTestingFollowsTransforms() {
        let target = Box(style: Style(width: .points(20), height: .points(20)))
        let row = Box(style: Style(flexDirection: .row, padding: Spacing(left: 40)), children: [target])
        let root = mount(row, size: CGSize(width: 200, height: 40))
        let id = ObjectIdentifier(target)

        #expect(root.hitPath(at: CGPoint(x: 45, y: 10)).first.map(ObjectIdentifier.init) == id)
        #expect(root.hitPath(at: CGPoint(x: 35, y: 10)).first.map(ObjectIdentifier.init) != id)

        target.style.scale = 2
        #expect(root.hitPath(at: CGPoint(x: 35, y: 10)).first.map(ObjectIdentifier.init) == id)

        target.style.scale = 1
        target.style.translateX = 100
        #expect(root.hitPath(at: CGPoint(x: 45, y: 10)).first.map(ObjectIdentifier.init) != id)
        #expect(root.hitPath(at: CGPoint(x: 145, y: 10)).first.map(ObjectIdentifier.init) == id)
    }

    @Test func multiLineTextWrapsToItsBoxAndStopsAtMaxLines() {
        let long = "halo wraps long sentences across lines when it is allowed to do so"
        let single = Text(long)
        let wrapped = Text(long)
        wrapped.maxLines = 0
        let capped = Text(long)
        capped.maxLines = 2
        let column = Box(style: Style(width: .points(120)), children: [single, wrapped, capped])
        _ = mount(column, size: CGSize(width: 400, height: 400))

        let lineHeight = single.layoutFrame.height
        #expect(single.layoutFrame.width == 120)
        #expect(wrapped.layoutFrame.height >= lineHeight * 4)
        #expect(capped.layoutFrame.height == lineHeight * 2)
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
