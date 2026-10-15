import Darwin
import Foundation

public struct SocketError: Error, CustomStringConvertible {
    public let description: String

    public init(description: String) {
        self.description = description
    }

    static func system(_ call: String) -> SocketError {
        SocketError(description: "\(call): \(String(cString: strerror(errno)))")
    }
}

public enum UnixSocket {
    public static func listen(at path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket") }
        var address = try makeAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, Darwin.listen(fd, 16) == 0 else {
            let error = SocketError.system("bind/listen \(path)")
            close(fd)
            throw error
        }
        chmod(path, 0o600)
        return fd
    }

    public static func connect(to path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket") }
        var address = try makeAddress(path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            let error = SocketError.system("connect \(path)")
            close(fd)
            throw error
        }
        disableSigpipe(fd)
        return fd
    }

    /// A write to a peer that already hung up returns EPIPE instead of killing the process with SIGPIPE.
    public static func disableSigpipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// True when something is accepting connections at `path`.
    public static func isLive(_ path: String) -> Bool {
        guard let fd = try? connect(to: path) else { return false }
        close(fd)
        return true
    }

    public static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, base + offset, buffer.count - offset)
                guard written > 0 else { throw SocketError.system("write") }
                offset += written
            }
        }
    }

    /// Reads until the first newline (excluded) or EOF.
    public static func readLine(_ fd: Int32, limit: Int = 1 << 20) throws -> Data {
        var line = Data()
        var byte: UInt8 = 0
        while line.count < limit {
            let count = read(fd, &byte, 1)
            if count == 0 || byte == UInt8(ascii: "\n") { break }
            guard count > 0 else { throw SocketError.system("read") }
            line.append(byte)
        }
        return line
    }

    private static func makeAddress(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw SocketError(description: "socket path too long: \(path)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            bytes.withUnsafeBytes { destination.copyMemory(from: $0) }
        }
        return address
    }
}
