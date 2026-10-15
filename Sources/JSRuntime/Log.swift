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

    public static func write(_ level: Level, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level.rawValue)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    public static func info(_ message: String) { write(.info, message) }
    public static func warn(_ message: String) { write(.warn, message) }
    public static func error(_ message: String) { write(.error, message) }
}
