import AppKit
import Testing
@testable import Render

@MainActor
@Suite struct MirrorTests {
    /// A box at (100, 50) of 200×100 with a 120×24 input at (20, 30) inside it, mounted in a flipped view.
    private func mount() -> (box: Box, input: Input, root: RenderRoot) {
        final class Flipped: NSView { override var isFlipped: Bool { true } }
        let view = Flipped(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.wantsLayer = true
        let input = Input(style: Style(width: .points(120), height: .points(24)))
        let box = Box(style: Style(padding: Spacing(top: 30, right: 0, bottom: 0, left: 20), width: .points(200), height: .points(100)), children: [input])
        let container = Box(style: Style(padding: Spacing(top: 50, right: 0, bottom: 0, left: 100)), children: [box])
        let host = CALayer()
        view.layer?.addSublayer(host)
        let root = RenderRoot(node: container, hostLayer: host, size: CGSize(width: 400, height: 300), contentsScale: 1)
        root.attachView = { view.addSubview($0) }
        root.layoutNow()
        return (box, input, root)
    }

    /// Where a wrapper transform puts `point` (surface coordinates), applied around the wrapper's anchor.
    private func moved(_ point: CGPoint, by transform: CATransform3D, in wrapper: NSView) -> CGPoint {
        let layer = wrapper.layer!
        let frame = wrapper.frame
        let anchor = CGPoint(x: frame.minX + frame.width * layer.anchorPoint.x, y: frame.minY + frame.height * layer.anchorPoint.y)
        let local = CGPoint(x: point.x - anchor.x, y: point.y - anchor.y).applying(CATransform3DGetAffineTransform(transform))
        return CGPoint(x: anchor.x + local.x, y: anchor.y + local.y)
    }

    private func firstTransform(_ wrapper: NSView?, _ key: String) -> CATransform3D? {
        let track = wrapper?.layer?.animation(forKey: "\(key).transform") as? CAKeyframeAnimation
        return (track?.values?.first as? NSValue)?.caTransform3DValue
    }

    @Test func scaleAndRotationPivotAroundTheAnimatedNode() throws {
        let (box, input, _) = mount()
        let pivot = CGPoint(x: 200, y: 100)
        let fieldAnchor = CGPoint(x: input.field.frame.minX, y: input.field.frame.minY)
        #expect(fieldAnchor.x == 120)

        box.play(enter: Transition(values: [.scale: .number(0.5)], timing: Timing(duration: 0.3)))
        let wrapper = try #require(input.existingWrapper(for: box))
        let scaled = try #require(firstTransform(wrapper, "mirror.enter"))
        let expected = CGPoint(x: pivot.x + 0.5 * (fieldAnchor.x - pivot.x), y: pivot.y + 0.5 * (fieldAnchor.y - pivot.y))
        let scaledPoint = moved(fieldAnchor, by: scaled, in: wrapper)
        #expect(abs(scaledPoint.x - expected.x) < 0.01 && abs(scaledPoint.y - expected.y) < 0.01)

        box.play(enter: Transition(values: [.rotate: .number(90)], timing: Timing(duration: 0.3)))
        let rotated = try #require(firstTransform(wrapper, "mirror.enter"))
        let offset = CGPoint(x: fieldAnchor.x - pivot.x, y: fieldAnchor.y - pivot.y)
        let turned = CGPoint(x: pivot.x - offset.y, y: pivot.y + offset.x)
        let rotatedPoint = moved(fieldAnchor, by: rotated, in: wrapper)
        #expect(abs(rotatedPoint.x - turned.x) < 0.01 && abs(rotatedPoint.y - turned.y) < 0.01)
    }

    @Test func transitionsAndKeyframesReachTheField() {
        let (box, input, _) = mount()
        box.transitions = ["opacity": Timing(duration: 0.2)]
        box.style.opacity = 0.3
        let fade = input.existingWrapper(for: box)?.layer?.animation(forKey: "mirror.transition.opacity") as? CAKeyframeAnimation
        #expect((fade?.values?.first as? CGFloat) == 1)
        #expect((fade?.values?.last as? CGFloat).map { abs($0 - 0.3) < 0.001 } == true)

        let key = box.animate(Keyframes(tracks: [.translateX: [.number(0), .number(10), .number(0)]], timing: Timing(duration: 0.5), repeatCount: .infinity))
        let loop = input.existingWrapper(for: box)?.layer?.animation(forKey: "mirror.\(key).transform") as? CAKeyframeAnimation
        #expect(loop?.repeatCount == .infinity)
        box.cancelAnimation(key)
        #expect(input.existingWrapper(for: box)?.layer?.animation(forKey: "mirror.\(key).transform") == nil)
    }

    /// Two animating ancestors each get a wrapper, nested in tree order, so both reach the field.
    @Test func nestedAncestorsComposeAroundTheField() throws {
        let (box, input, root) = mount()
        let container = root.node
        container.play(enter: Transition(values: [.opacity: .number(0.5)], timing: Timing(duration: 0.3)))
        box.play(enter: Transition(values: [.opacity: .number(0.5)], timing: Timing(duration: 0.3)))
        let outer = try #require(input.existingWrapper(for: container))
        let inner = try #require(input.existingWrapper(for: box))
        #expect(inner.superview === outer)
        #expect(input.field.superview === inner)
        #expect(outer.layer?.animation(forKey: "mirror.enter.opacity") != nil)
        #expect(inner.layer?.animation(forKey: "mirror.enter.opacity") != nil)
    }

    @Test func layoutMovesSlideTheFieldFromItsOldPlace() throws {
        let (box, input, root) = mount()
        box.transitions = ["layout": Timing(duration: 0.3)]
        root.node.style.padding = Spacing(top: 50, right: 0, bottom: 0, left: 160)
        root.layoutNow()
        let wrapper = try #require(input.existingWrapper(for: box))
        let slide = wrapper.layer?.animation(forKey: "mirror.layout.x") as? CABasicAnimation
        #expect(slide?.isAdditive == true)
        #expect((slide?.fromValue as? CGFloat) == -60)
        #expect((slide?.toValue as? CGFloat) == 0)
    }

    @Test func progressCurvesStartAtZeroAndSettleAtOne() {
        let spring = Timing(curve: .spring(stiffness: 300, damping: 20, mass: 1))
        #expect(spring.progress(at: 0) == 0)
        #expect(abs(spring.progress(at: spring.length) - 1) < 0.01)
        let easeOut = Timing(duration: 1, curve: .easeOut)
        #expect(abs(easeOut.progress(at: 0.5) - 0.6847) < 0.005)
        #expect(easeOut.progress(at: 2) == 1)
    }
}
