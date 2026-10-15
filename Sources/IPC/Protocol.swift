import Foundation

/// One JSON object per line in each direction: the client sends a `Request`, the host answers with a `Response`.
public enum Request: Codable, Equatable, Sendable {
    case trigger(name: String, payload: [String: String])
    case reload
    case quit
}

public struct Response: Codable, Equatable, Sendable {
    public var ok: Bool
    public var error: String?

    public init(ok: Bool, error: String? = nil) {
        self.ok = ok
        self.error = error
    }

    public static let success = Response(ok: true)
}

public enum Command: Equatable, Sendable {
    case start(config: String?)
    case send(Request)
    case log
    case help
}

public struct UsageError: Error, Equatable, CustomStringConvertible {
    public let description: String
}

public enum IPC {
    public static let usage = """
    usage: halo <command>

      start [--config <dir>]           run the host in the foreground (default config: $XDG_CONFIG_HOME/halo)
      trigger <name> [key=value ...]   emit an external signal event
      reload                           rebuild and remount the config
      quit                             stop the host
      log                              follow the host log
    """

    /// `HALO_SOCKET` overrides the default `$TMPDIR/halo.sock` (the per-user temp dir, also under launchd).
    public static var socketPath: String {
        ProcessInfo.processInfo.environment["HALO_SOCKET"]
            ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("halo.sock")
    }

    public static var logPath: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("halo.log")
    }

    public static func parse(arguments: [String]) throws -> Command {
        guard let command = arguments.first else { return .help }
        let rest = Array(arguments.dropFirst())
        switch command {
        case "start":
            switch rest.count {
            case 0: return .start(config: nil)
            case 2 where rest[0] == "--config": return .start(config: rest[1])
            default: throw UsageError(description: "usage: halo start [--config <dir>]")
            }
        case "trigger":
            guard let name = rest.first, !name.contains("=") else {
                throw UsageError(description: "trigger needs an event name: halo trigger <name> [key=value ...]")
            }
            var payload: [String: String] = [:]
            for pair in rest.dropFirst() {
                guard let separator = pair.firstIndex(of: "="), separator != pair.startIndex else {
                    throw UsageError(description: "expected key=value, got \"\(pair)\"")
                }
                payload[String(pair[..<separator])] = String(pair[pair.index(after: separator)...])
            }
            return .send(.trigger(name: name, payload: payload))
        case "reload" where rest.isEmpty:
            return .send(.reload)
        case "quit" where rest.isEmpty:
            return .send(.quit)
        case "log" where rest.isEmpty:
            return .log
        case "help", "-h", "--help":
            return .help
        default:
            throw UsageError(description: "unknown command \"\(arguments.joined(separator: " "))\"\n\n\(usage)")
        }
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }
}
