import AppKit
import Compositor
import JavaScriptCore
import Render

/// File drag and drop: drops onto nodes (`onDragEnter`/`onDragLeave`/`onDrop`) and nodes as drag sources
/// (`draggable`). Only paths move around; nothing is read or copied.
extension Runtime {
    static let dropKinds: Set<String> = ["dragEnter", "dragLeave", "drop"]

    /// `draggable={{ files }}`; empty or missing files make the node an ordinary one again.
    func setDraggable(_ id: Int, _ value: JSValue) {
        let files = value.isObject ? (value.forProperty("files")?.toArray() ?? []).compactMap { $0 as? String } : []
        draggables[id] = files.isEmpty ? nil : files
    }

    func handleDrag(_ event: DragEvent, on entry: SurfaceEntry) -> Bool {
        switch event {
        case .over(let point, let files):
            let target = firstListener(Self.dropKinds, at: point, in: entry)
            if target != entry.dragTarget {
                if let old = entry.dragTarget { dispatch(old, "dragLeave", NSNull()) }
                if let target { dispatch(target, "dragEnter", ["files": files, "x": point.x, "y": point.y]) }
                entry.dragTarget = target
            }
            return firstListener(["drop"], at: point, in: entry) != nil
        case .exited:
            if let old = entry.dragTarget { dispatch(old, "dragLeave", NSNull()) }
            entry.dragTarget = nil
            return false
        case .drop(let point, let files):
            if let old = entry.dragTarget { dispatch(old, "dragLeave", NSNull()) }
            entry.dragTarget = nil
            guard let target = firstListener(["drop"], at: point, in: entry) else { return false }
            dispatch(target, "drop", ["files": files, "x": point.x, "y": point.y])
            return true
        }
    }

    /// Mouse-down on a draggable node arms a drag; moving 4 points starts it (and cancels the click).
    func armDrag(at point: CGPoint, in entry: SurfaceEntry) {
        let id = entry.root.hitPath(at: point).compactMap { nodeIDs[ObjectIdentifier($0)] }.first { draggables[$0] != nil }
        entry.dragOrigin = id.map { (point, $0) }
    }

    func continueDrag(at point: CGPoint, in entry: SurfaceEntry) {
        guard let (origin, id) = entry.dragOrigin, hypot(point.x - origin.x, point.y - origin.y) >= 4 else { return }
        entry.dragOrigin = nil
        entry.pressed = nil
        guard let files = draggables[id] else { return }
        entry.surface.beginDrag(files: files)
        followOwnDrag()
    }

    func firstListener(_ kinds: Set<String>, at point: CGPoint, in entry: SurfaceEntry) -> Int? {
        entry.root.hitPath(at: point)
            .compactMap { nodeIDs[ObjectIdentifier($0)] }
            .first { !(listeners[$0] ?? []).isDisjoint(with: kinds) }
    }

    /// A drag halo starts swallows the mouse events that normally keep click-through current, so follow the pointer
    /// on a timer until the button is released (drop zones shown mid-drag must catch it).
    func followOwnDrag() {
        ownDragTimer?.invalidate()
        ownDragTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard !self.disposed, NSEvent.pressedMouseButtons & 1 != 0 else {
                    self.ownDragTimer?.invalidate()
                    self.ownDragTimer = nil
                    return
                }
                self.pointerMoved()
            }
        }
    }
}
