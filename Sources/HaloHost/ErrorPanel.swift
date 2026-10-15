import AppKit
import Compositor
import Render

/// Shows the latest build failure or config error on screen, drawn natively so it works when the config doesn't.
/// Click to dismiss; a successful reload clears it.
@MainActor
final class ErrorPanel {
    private static let maxLines = 12
    private static let width: CGFloat = 560
    private static let red = CGColor(srgbRed: 0.95, green: 0.55, blue: 0.66, alpha: 1)

    private let backend: CompositorBackend
    private var surface: Surface?
    private var root: RenderRoot?
    private var count = 0

    init(backend: CompositorBackend) {
        self.backend = backend
    }

    func show(title: String, message: String, on screen: ScreenInfo) {
        dismiss(resettingCount: false)
        count += 1

        let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .filter { !$0.contains("@halo/") && !$0.contains("@halo-entry.ts") && !$0.contains("@halo-bundle.js") }
        var shown = Array(lines.prefix(Self.maxLines))
        if lines.count > Self.maxLines { shown.append("… \(lines.count - Self.maxLines) more lines in `halo log`") }

        let heading = count > 1 ? "\(title) (\(count) errors)" : title
        let content = Box(
            style: Style(
                padding: Spacing(vertical: 12, horizontal: 14), gap: 3,
                background: CGColor(srgbRed: 0.13, green: 0.07, blue: 0.09, alpha: 0.96),
                borderColor: Self.red, borderWidth: 1, radius: 12
            ),
            children: [Text(heading, font: Font(size: 13, weight: .bold), color: Self.red, style: Style(padding: Spacing(top: 0, right: 0, bottom: 4, left: 0)))]
                + shown.map { Text($0.isEmpty ? " " : $0, font: Font(family: "Menlo", size: 11), color: CGColor(gray: 0.88, alpha: 1)) }
                + [Text("click to dismiss · full output: halo log", font: Font(size: 10), color: CGColor(gray: 0.55, alpha: 1), style: Style(padding: Spacing(top: 4, right: 0, bottom: 0, left: 0)))]
        )

        let height = 24 + 21 + CGFloat(shown.count) * 16 + 20
        let config = SurfaceConfig(
            screen: screen.id, anchor: [.bottom, .right], margins: Insets(right: 16, bottom: 16),
            size: SurfaceSize(width: .fixed(Self.width), height: .fixed(height)), layer: .overlay, input: .interactive
        )
        let surface = Surface(config: config, screen: screen, backend: backend)
        root = RenderRoot(node: content, hostLayer: surface.rootLayer, size: surface.frame.size, contentsScale: screen.scale)
        surface.onEvent = { [weak self] event in
            if case .mouseUp = event { self?.dismiss() }
        }
        self.surface = surface
    }

    func dismiss(resettingCount: Bool = true) {
        root?.detach()
        surface?.destroy()
        root = nil
        surface = nil
        if resettingCount { count = 0 }
    }
}
