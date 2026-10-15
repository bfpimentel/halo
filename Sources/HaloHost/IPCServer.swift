import Darwin
import Foundation
import IPC

/// Serves one request per connection on the Unix socket. Requests are handled on main; I/O stays off it.
@MainActor
final class IPCServer {
    typealias Handler = @Sendable @MainActor (Request) -> Response

    private let path: String
    private let fd: Int32
    private let acceptSource: DispatchSourceRead

    init(path: String, handler: @escaping Handler) throws {
        if FileManager.default.fileExists(atPath: path) {
            if UnixSocket.isLive(path) {
                throw SocketError(description: "another halo host is already running (\(path))")
            }
            unlink(path)
        }
        let fd = try UnixSocket.listen(at: path)
        self.path = path
        self.fd = fd
        acceptSource = Self.acceptConnections(on: fd, handler: handler)
    }

    /// Nonisolated so the event handler isn't inferred as main-actor code: it runs on a background queue.
    private nonisolated static func acceptConnections(on fd: Int32, handler: @escaping Handler) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            DispatchQueue.global(qos: .utility).async { serve(client, handler) }
        }
        source.resume()
        return source
    }

    func stop() {
        acceptSource.cancel()
        close(fd)
        unlink(path)
    }

    private nonisolated static func serve(_ client: Int32, _ handler: @escaping Handler) {
        defer { close(client) }
        UnixSocket.disableSigpipe(client)
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let response: Response
        do {
            let request = try IPC.decode(Request.self, from: UnixSocket.readLine(client))
            response = DispatchQueue.main.sync { MainActor.assumeIsolated { handler(request) } }
        } catch {
            response = Response(ok: false, error: "bad request: \(error)")
        }
        if let data = try? IPC.encode(response) {
            try? UnixSocket.writeAll(client, data)
        }
    }
}
