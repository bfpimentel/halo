import Foundation

public enum Log {
    public enum Level: String, Sendable {
        case info, warn, error
    }

    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withTime, .withColonSeparatorInTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()

    nonisolated(unsafe) private static var file: FileHandle?

    /// Also append every line to `path`, truncating what a previous run left there.
    public static func mirror(to path: String) {
        FileManager.default.createFile(atPath: path, contents: nil)
        file = FileHandle(forWritingAtPath: path)
    }

    public static func write(_ level: Level, _ message: String) {
        let line = Data("\(formatter.string(from: Date())) [\(level.rawValue)] \(message)\n".utf8)
        FileHandle.standardError.write(line)
        file?.write(line)
    }

    public static func info(_ message: String) { write(.info, message) }
    public static func warn(_ message: String) { write(.warn, message) }
    public static func error(_ message: String) { write(.error, message) }
}
