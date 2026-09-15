import Foundation
import Network

/// Serves web/dist on 127.0.0.1 at a random port. tldraw's license manager only runs unlicensed
/// on http origins, so the editor page must come from a real loopback server rather than file://
/// or a custom scheme.
final class LocalServer {
    private let root: URL
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private let queue = DispatchQueue(label: "shotnote.server")

    init(root: URL) { self.root = root }

    var indexURL: URL { URL(string: "http://127.0.0.1:\(port)/index.html")! }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: params)
        // Captured by value so the callbacks below never need to cross back to `self`.
        let queue = self.queue
        let root = self.root
        listener.newConnectionHandler = { conn in LocalServer.handle(conn, queue: queue, root: root) }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed(let err) = state { Log.write("[server] failed: \(err)"); ready.signal() }
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 2)
        // Safe to read now: `wait()` only returns after the `.ready`/`.failed` callback above signaled it.
        self.port = listener.port?.rawValue ?? 0
        self.listener = listener
        Log.write("[server] port \(port)")
    }

    private static func handle(_ conn: NWConnection, queue: DispatchQueue, root: URL) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8) else { conn.cancel(); return }
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let response = LocalServer.response(for: path, root: root)
            conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    private static func response(for rawPath: String, root: URL) -> Data {
        var path = rawPath.split(separator: "?").first.map(String.init) ?? "/"
        if path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root.standardizedFileURL.path), let body = try? Data(contentsOf: file) else {
            return Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        }
        let head = "HTTP/1.1 200 OK\r\nContent-Type: \(mimeType(for: file.pathExtension))\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        default: return "application/octet-stream"
        }
    }
}
