import Foundation

/// A source map v3 decoder: maps positions in the bundle back to the config's own files.
public struct SourceMap: Sendable {
    public struct Location: Equatable, Sendable, CustomStringConvertible {
        public var source: String
        /// 1-based, like the positions in JS stack traces.
        public var line: Int
        public var column: Int

        public var description: String { "\(source):\(line):\(column)" }
    }

    private struct Segment {
        var column: Int
        var source: Int
        var line: Int
        var sourceColumn: Int
    }

    private var sources: [String]
    /// Segments per generated line (0-based), sorted by generated column.
    private let lines: [[Segment]]

    public init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let sources = object["sources"] as? [String],
              let mappings = object["mappings"] as? String
        else { return nil }
        self.sources = sources
        lines = Self.decode(mappings)
    }

    /// Extracts the inline `//# sourceMappingURL=data:…;base64,…` map esbuild appends to a bundle.
    public init?(inlineIn script: String) {
        guard let marker = script.range(of: "//# sourceMappingURL=data:application/json;base64,", options: .backwards) else {
            return nil
        }
        let encoded = script[marker.upperBound...].prefix { !$0.isNewline }
        guard let data = Data(base64Encoded: String(encoded)) else { return nil }
        self.init(json: data)
    }

    /// Replaces source paths for display (e.g. halo's own runtime files as `halo/<file>`).
    public func renamingSources(_ rename: (String) -> String) -> SourceMap {
        var copy = self
        copy.sources = sources.map(rename)
        return copy
    }

    /// `line` and `column` are 1-based positions in the bundle.
    public func original(line: Int, column: Int) -> Location? {
        guard line >= 1, line <= lines.count else { return nil }
        let segments = lines[line - 1]
        guard let segment = segments.last(where: { $0.column <= column - 1 }) ?? segments.first,
              sources.indices.contains(segment.source)
        else { return nil }
        return Location(source: sources[segment.source], line: segment.line + 1, column: segment.sourceColumn + 1)
    }

    /// Rewrites every `<anything>:line:column` that refers to the bundle (`bundleName`) in a stack or message.
    public func rewrite(_ text: String, bundleName: String) -> String {
        let pattern = NSRegularExpression.escapedPattern(for: bundleName) + #":(\d+):(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text),
                  let lineRange = Range(match.range(at: 1), in: text), let line = Int(text[lineRange]),
                  let columnRange = Range(match.range(at: 2), in: text), let column = Int(text[columnRange]),
                  let location = original(line: line, column: column)
            else { continue }
            result.replaceSubrange(whole, with: location.description)
        }
        return result
    }

    private static func decode(_ mappings: String) -> [[Segment]] {
        var lines: [[Segment]] = []
        var source = 0
        var originalLine = 0
        var originalColumn = 0
        for lineText in mappings.split(separator: ";", omittingEmptySubsequences: false) {
            var segments: [Segment] = []
            var column = 0
            for segmentText in lineText.split(separator: ",") {
                let fields = vlq(segmentText)
                guard !fields.isEmpty else { continue }
                column += fields[0]
                guard fields.count >= 4 else { continue }
                source += fields[1]
                originalLine += fields[2]
                originalColumn += fields[3]
                segments.append(Segment(column: column, source: source, line: originalLine, sourceColumn: originalColumn))
            }
            lines.append(segments)
        }
        return lines
    }

    private static let base64: [Character: Int] = Dictionary(
        uniqueKeysWithValues: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".enumerated().map { ($1, $0) }
    )

    static func vlq(_ text: Substring) -> [Int] {
        var values: [Int] = []
        var value = 0
        var shift = 0
        for character in text {
            guard let digit = base64[character] else { return [] }
            value += (digit & 31) << shift
            if digit & 32 != 0 {
                shift += 5
                continue
            }
            values.append(value & 1 == 1 ? -(value >> 1) : value >> 1)
            value = 0
            shift = 0
        }
        return values
    }
}
