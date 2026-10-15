import IPC

/// Which surfaces the CLI (or config code) has hidden, by name. `""` stands for unnamed surfaces, reachable only
/// through `--all`. Lives in the host, so it survives reloads.
struct Visibility {
    struct UnknownNames: Error, CustomStringConvertible {
        let names: [String]
        let available: [String]

        var description: String {
            let list = available.isEmpty ? "none" : available.joined(separator: ", ")
            return "no surface named \(names.joined(separator: ", ")) (available: \(list))"
        }
    }

    private(set) var hidden: Set<String> = []
    private var known: Set<String> = []

    func isHidden(name: String?) -> Bool {
        hidden.contains(name ?? "")
    }

    /// The first time a name shows up, `defaultHidden` decides its state; after that the user's choice sticks.
    mutating func register(name: String, defaultHidden: Bool) {
        guard known.insert(name).inserted, defaultHidden else { return }
        hidden.insert(name)
    }

    /// `mounted` are the names currently on screen, with `nil` for unnamed surfaces.
    mutating func apply(_ action: VisibilityAction, to target: VisibilityTarget, mounted: Set<String?>) throws {
        let present = Set(mounted.map { $0 ?? "" })
        let names: Set<String>
        switch target {
        case .all:
            names = present
        case .names(let requested):
            let unknown = requested.filter { !present.contains($0) || $0.isEmpty }
            guard unknown.isEmpty else {
                throw UnknownNames(names: unknown, available: present.filter { !$0.isEmpty }.sorted())
            }
            names = Set(requested)
        }

        switch (action, target) {
        case (.show, _):
            hidden.subtract(names)
        case (.hide, _):
            hidden.formUnion(names)
        case (.toggle, .all):
            if names.isSubset(of: hidden) { hidden.subtract(names) } else { hidden.formUnion(names) }
        case (.toggle, .names):
            for name in names where hidden.remove(name) == nil { hidden.insert(name) }
        }
    }
}
