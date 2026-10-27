import AppKit
import Testing
@testable import Render

/// Text fields live outside the layer tree, so their mounting, focus and removal follow the nodes by hand.
@MainActor
@Suite struct InputTests {
    final class Flipped: NSView { override var isFlipped: Bool { true } }

    private func mount(_ node: Node) -> (window: NSWindow, view: NSView, root: RenderRoot) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: true)
        let view = Flipped(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.wantsLayer = true
        window.contentView = view
        let host = CALayer()
        view.layer?.addSublayer(host)
        let root = RenderRoot(node: node, hostLayer: host, size: CGSize(width: 400, height: 300), contentsScale: 1)
        root.attachView = { view.addSubview($0) }
        return (window, view, root)
    }

    private func isFocused(_ input: Input) -> Bool {
        input.field.currentEditor() != nil
    }

    @Test func aFieldUnderAnExitingParentLeavesWhenTheExitEnds() async throws {
        let input = Input(style: Style(width: .points(120), height: .points(24)))
        var box: Box? = Box(style: Style(width: .points(200), height: .points(100)), children: [input])
        box?.exit = Transition(values: [.opacity: .number(0)], timing: Timing(duration: 0.1))
        let (_, view, root) = mount(Box(children: [try #require(box)]))
        root.layoutNow()
        weak let freed = box

        // The JS side destroys the parent first (cleanups run in reverse), which frees it mid-exit.
        box?.remove()
        box = nil
        #expect(freed == nil)
        input.remove()
        #expect(input.field.superview != nil, "still shown while the exit plays")

        try await Task.sleep(for: .milliseconds(400))
        #expect(view.subviews.isEmpty, "gone once the exit ends")
    }

    @Test func focusBeforeTheFieldIsMountedAppliesOnMount() {
        let input = Input(style: Style(width: .points(120), height: .points(24)))
        let (_, _, root) = mount(Box(children: [input]))
        input.focus()
        #expect(!isFocused(input))
        root.layoutNow()
        #expect(isFocused(input))
    }

    @Test func movingAFieldKeepsItMountedAndFocused() {
        let input = Input(style: Style(width: .points(120), height: .points(24)))
        let first = Box(children: [input])
        let second = Box()
        let (_, _, root) = mount(Box(children: [first, second]))
        root.layoutNow()
        input.focus()
        #expect(isFocused(input))

        second.insert(input, at: 0)
        root.layoutNow()
        #expect(input.field.superview != nil)
        #expect(isFocused(input))
    }

    @Test func removingAFocusedFieldHandsKeysBackToTheSurface() {
        final class Surface: NSView {
            override var isFlipped: Bool { true }
            override var acceptsFirstResponder: Bool { true }
        }
        let input = Input(style: Style(width: .points(120), height: .points(24)))
        let (window, _, root) = mount(Box(children: [input]))
        let view = Surface(frame: window.contentView?.frame ?? .zero)
        view.wantsLayer = true
        window.contentView = view
        root.attachView = { view.addSubview($0) }
        root.layoutNow()
        input.focus()
        #expect(isFocused(input))

        input.remove()
        #expect(window.firstResponder === view)
    }

    @Test func anAncestorsFirstEnterReachesAFieldMountedInTheSamePass() {
        let input = Input(style: Style(width: .points(120), height: .points(24)))
        let box = Box(style: Style(width: .points(200), height: .points(100)), children: [input])
        box.enter = Transition(values: [.opacity: .number(0)], timing: Timing(duration: 0.3))
        let (_, _, root) = mount(Box(children: [box]))
        root.layoutNow()
        let wrapper = input.existingWrapper(for: box)
        #expect(wrapper?.layer?.animation(forKey: "mirror.enter.opacity") != nil)
    }
}
