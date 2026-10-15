import AppKit

@MainActor
public final class Screens {
    public private(set) var all: [ScreenInfo] = []
    private var observer: NSObjectProtocol?

    public init(onChange: @escaping @MainActor ([ScreenInfo]) -> Void) {
        all = Self.snapshot()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let current = Self.snapshot()
                guard current != self.all else { return }
                self.all = current
                onChange(current)
            }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public static func snapshot() -> [ScreenInfo] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.enumerated().compactMap { offset, screen in
            info(for: screen, index: offset + 1, primaryHeight: primaryHeight)
        }
    }

    private static func info(for screen: NSScreen, index: Int, primaryHeight: CGFloat) -> ScreenInfo? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        let frame = Geometry.appKitToTopLeft(screen.frame, primaryHeight: primaryHeight)
        let menuBarHeight = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)

        var notch: CGRect?
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let minX = frame.minX + left.width
            let maxX = frame.maxX - right.width
            notch = CGRect(x: minX, y: frame.minY, width: maxX - minX, height: screen.safeAreaInsets.top)
        }

        return ScreenInfo(
            id: id, name: screen.localizedName, frame: frame,
            menuBarHeight: menuBarHeight, notch: notch, scale: screen.backingScaleFactor, index: index
        )
    }
}
