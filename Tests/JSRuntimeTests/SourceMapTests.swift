import Foundation
import Testing
@testable import JSRuntime

@Suite struct SourceMapTests {
    @Test func vlqDecodesSignedMultiDigitValues() {
        #expect(SourceMap.vlq("AAAA") == [0, 0, 0, 0])
        #expect(SourceMap.vlq("CAAC") == [1, 0, 0, 1])
        #expect(SourceMap.vlq("D") == [-1])
        #expect(SourceMap.vlq("gB") == [16])
        #expect(SourceMap.vlq("2HwrR") == [123, 8888])
    }

    /// Two sources. Line 1: (0 → main 1:1), (4 → main 1:5). Line 2 switches to load.tsx, line +5; the source
    /// column keeps accumulating across lines: (0 → load 6:5), (2 → load 6:7), (8 → load 6:13).
    private let map = SourceMap(json: Data("""
    {"version":3,"sources":["main.tsx","load.tsx"],"mappings":"AAAA,IAAI;ACKA,EAAE,MAAM"}
    """.utf8))

    @Test func looksUpTheClosestSegmentAtOrBeforeTheColumn() throws {
        let map = try #require(map)
        #expect(map.original(line: 1, column: 1) == .init(source: "main.tsx", line: 1, column: 1))
        #expect(map.original(line: 1, column: 7) == .init(source: "main.tsx", line: 1, column: 5))
        #expect(map.original(line: 2, column: 3) == .init(source: "load.tsx", line: 6, column: 7))
        #expect(map.original(line: 2, column: 20) == .init(source: "load.tsx", line: 6, column: 13))
        #expect(map.original(line: 9, column: 1) == nil)
    }

    @Test func rewritesBundlePositionsInStacksOnly() throws {
        let map = try #require(map)
        let stack = "boom@/cfg/main.tsx:2:3\nother@/usr/lib/x.js:2:3\nglobal code@/cfg/main.tsx:1:7"
        #expect(map.rewrite(stack, bundleName: "/cfg/main.tsx")
            == "boom@load.tsx:6:7\nother@/usr/lib/x.js:2:3\nglobal code@main.tsx:1:5")
    }

    @Test func extractsTheInlineMapEsbuildAppends() throws {
        let json = #"{"version":3,"sources":["main.tsx"],"mappings":"AAAA"}"#
        let script = "console.log(1);\n//# sourceMappingURL=data:application/json;base64,\(Data(json.utf8).base64EncodedString())\n"
        let map = try #require(SourceMap(inlineIn: script))
        #expect(map.original(line: 1, column: 1)?.source == "main.tsx")
    }
}
