import Foundation

/// A config directory's `halo.json`: the widget instances to mount, each with its screens and props.
public struct WidgetConfig: Equatable, Sendable {
    public enum Screens: Equatable, Sendable {
        case all
        case main
        case indices([Int])
    }

    public struct Instance: Equatable, Sendable {
        public var name: String
        public var widget: String
        public var screens: Screens
        /// The instance's `props` as JSON text, written into the entry as an object literal.
        public var props: String

        public init(name: String, widget: String, screens: Screens = .all, props: String = "{}") {
            self.name = name
            self.widget = widget
            self.screens = screens
            self.props = props
        }
    }

    public struct Failure: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    public static let fileName = "halo.json"

    public var instances: [Instance]

    public static func load(configDirectory: URL) throws -> WidgetConfig {
        let file = configDirectory.appendingPathComponent(fileName)
        guard let data = FileManager.default.contents(atPath: file.path) else {
            throw Failure(description: "no \(fileName) in \(configDirectory.path); run `halo init` to create one")
        }
        return try parse(data)
    }

    public static func parse(_ data: Data) throws -> WidgetConfig {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw Failure(description: "\(fileName) is not valid JSON: \((error as NSError).userInfo[NSDebugDescriptionErrorKey] ?? error)")
        }
        guard let object = root as? [String: Any] else { throw Failure(description: "\(fileName) must be an object") }
        try rejectUnknown(Set(object.keys), allowed: ["widgets"], in: fileName)
        guard let widgets = object["widgets"] as? [String: Any], !widgets.isEmpty else {
            throw Failure(description: "\(fileName) has no widgets: add one under \"widgets\", e.g. \"clock\": { \"widget\": \"clock\" }")
        }
        let instances = try widgets.keys.sorted().map { name in
            guard let fields = widgets[name] as? [String: Any] else { throw Failure(description: "widgets.\(name) must be an object") }
            return try instance(name: name, fields)
        }
        return WidgetConfig(instances: instances)
    }

    private static func instance(name: String, _ fields: [String: Any]) throws -> Instance {
        let path = "widgets.\(name)"
        try rejectUnknown(Set(fields.keys), allowed: ["widget", "screens", "props"], in: path)
        guard let widget = fields["widget"] as? String, !widget.isEmpty else {
            throw Failure(description: "\(path) needs \"widget\": the file in widgets/ to mount (e.g. \"widget\": \"clock\" for widgets/clock.tsx)")
        }
        guard !widget.contains("/"), widget != ".", widget != ".." else {
            throw Failure(description: "\(path).widget must be a name in widgets/, got \"\(widget)\"")
        }
        let screens: Screens
        switch fields["screens"] {
        case nil, "all" as String: screens = .all
        case "main" as String: screens = .main
        case let list as [Any]:
            let indices = list.compactMap { item -> Int? in
                guard let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
                return Int(exactly: number.doubleValue)
            }
            guard indices.count == list.count, indices.allSatisfy({ $0 >= 1 }) else {
                throw Failure(description: "\(path).screens must list 1-based display indices, e.g. [1, 2]")
            }
            screens = .indices(indices)
        default:
            throw Failure(description: "\(path).screens must be \"all\", \"main\" or a list of display indices")
        }
        var props = "{}"
        if let value = fields["props"] {
            guard value is [String: Any] else { throw Failure(description: "\(path).props must be an object") }
            props = String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        }
        return Instance(name: name, widget: widget, screens: screens, props: props)
    }

    private static func rejectUnknown(_ keys: Set<String>, allowed: Set<String>, in path: String) throws {
        let unknown = keys.subtracting(allowed).sorted()
        guard unknown.isEmpty else {
            throw Failure(description: "\(path): unknown field\(unknown.count == 1 ? "" : "s") \(unknown.map { "\"\($0)\"" }.joined(separator: ", ")) (expected \(allowed.sorted().joined(separator: ", ")))")
        }
    }

    /// `widgets/<name>.tsx`, then `widgets/<name>/index.tsx`.
    public static func candidates(widget: String, configDirectory: URL) -> [URL] {
        let widgets = configDirectory.appendingPathComponent("widgets")
        return [
            widgets.appendingPathComponent("\(widget).tsx"),
            widgets.appendingPathComponent(widget).appendingPathComponent("index.tsx"),
        ]
    }

    public func resolve(_ instance: Instance, configDirectory: URL) throws -> URL {
        let candidates = Self.candidates(widget: instance.widget, configDirectory: configDirectory)
        guard let file = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw Failure(description: "widgets.\(instance.name): widget \"\(instance.widget)\" not found (looked for \(candidates.map { $0.path }.joined(separator: " and ")))")
        }
        return file
    }

    /// The esbuild entry: `require` keeps each widget module lazy, so `mount` evaluates them one by one and a widget
    /// that throws at its top level only takes down its own instances.
    public func entrySource(configDirectory: URL) throws -> String {
        Self.entrySource(try instances.map { ($0, try resolve($0, configDirectory: configDirectory)) })
    }

    public static func entrySource(_ mounts: [(instance: Instance, file: URL)]) -> String {
        let lines = mounts.map { instance, file in
            let screens: String
            switch instance.screens {
            case .all: screens = "\"all\""
            case .main: screens = "\"main\""
            case .indices(let list): screens = "[\(list.map(String.init).joined(separator: ", "))]"
            }
            return "  { name: \(quote(instance.name)), widget: \(quote(instance.widget)), load: () => require(\(quote(file.path))).default, screens: \(screens), props: \(instance.props) },"
        }
        return """
        import { mount } from "halo/internal";
        mount([
        \(lines.joined(separator: "\n"))
        ]);

        """
    }

    static func quote(_ string: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return String(decoding: (try? encoder.encode(string)) ?? Data("\"\"".utf8), as: UTF8.self)
    }
}
