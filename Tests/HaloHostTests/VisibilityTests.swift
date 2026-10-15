import IPC
import Testing
@testable import HaloHost

@Suite struct VisibilityTests {
    private let mounted: Set<String?> = ["bar", "launcher", nil]

    @Test func toggleFlipsEachNamedSurfaceIndependently() throws {
        var visibility = Visibility()
        try visibility.apply(.hide, to: .names(["bar"]), mounted: mounted)
        try visibility.apply(.toggle, to: .names(["bar", "launcher"]), mounted: mounted)
        #expect(!visibility.isHidden(name: "bar"))
        #expect(visibility.isHidden(name: "launcher"))
        #expect(!visibility.isHidden(name: nil))
    }

    @Test func allIncludesUnnamedSurfaces() throws {
        var visibility = Visibility()
        try visibility.apply(.hide, to: .all, mounted: mounted)
        #expect(visibility.isHidden(name: nil) && visibility.isHidden(name: "bar"))
        try visibility.apply(.show, to: .all, mounted: mounted)
        #expect(visibility.hidden.isEmpty)
    }

    @Test func toggleAllHidesUnlessEverythingIsAlreadyHidden() throws {
        var visibility = Visibility()
        try visibility.apply(.hide, to: .names(["launcher"]), mounted: mounted)
        try visibility.apply(.toggle, to: .all, mounted: mounted)
        #expect(visibility.isHidden(name: "bar") && visibility.isHidden(name: "launcher") && visibility.isHidden(name: nil))
        try visibility.apply(.toggle, to: .all, mounted: mounted)
        #expect(visibility.hidden.isEmpty)
    }

    @Test func unknownNamesAreRejectedWithoutChangingAnything() {
        var visibility = Visibility()
        #expect(throws: Visibility.UnknownNames.self) {
            try visibility.apply(.hide, to: .names(["bar", "lancher"]), mounted: mounted)
        }
        #expect(visibility.hidden.isEmpty)
    }

    @Test func defaultHiddenOnlyAppliesTheFirstTimeANameAppears() throws {
        var visibility = Visibility()
        visibility.register(name: "launcher", defaultHidden: true)
        #expect(visibility.isHidden(name: "launcher"))
        try visibility.apply(.show, to: .names(["launcher"]), mounted: mounted)
        visibility.register(name: "launcher", defaultHidden: true)
        #expect(!visibility.isHidden(name: "launcher"))
    }
}
