import AppKit
import Compositor

/// M1 stand-in for `<PerScreen>`: one static bar per display, reconciled on display changes.
@MainActor
final class Host {
    private let backend = PublicBackend()
    private var screens: Screens?
    private var bars: [ScreenID: Surface] = [:]

    func start() {
        let screens = Screens { [weak self] in self?.sync($0) }
        self.screens = screens
        sync(screens.all)
    }

    private func sync(_ infos: [ScreenInfo]) {
        backend.transaction {
            let ids = Set(infos.map(\.id))
            for (id, bar) in bars where !ids.contains(id) {
                bar.destroy()
                bars[id] = nil
            }
            for info in infos {
                if let bar = bars[info.id] {
                    bar.place(on: info)
                } else {
                    bars[info.id] = makeBar(on: info)
                }
            }
        }
    }

    private func makeBar(on screen: ScreenInfo) -> Surface {
        let config = SurfaceConfig(
            screen: screen.id,
            anchor: [.top, .left, .right],
            margins: Insets(top: 4, right: 8, left: 8),
            size: SurfaceSize(height: .fixed(32)),
            layer: .aboveMenu,
            spaces: .all,
            input: .passthrough,
            avoid: [.menuBar]
        )
        let bar = Surface(config: config, screen: screen, backend: backend)
        bar.rootLayer.backgroundColor = CGColor(srgbRed: 0.12, green: 0.12, blue: 0.18, alpha: 0.85)
        bar.rootLayer.cornerRadius = 8
        return bar
    }
}
