import Foundation
import Network

/// Serves the editor page and the screenshots it annotates on 127.0.0.1, so the page has an http
/// origin (tldraw's license manager needs one) and the image is same-origin with the page
/// (`render` draws it on a canvas, which a cross-origin image would taint). Every path carries a
/// per-launch token, so another local process cannot read screenshots through the port; the page
/// builds `/<token>/file?p=<path>` from its own location. Only GET, only the loopback Host, only
/// the bundle and files the `access` rule allows.
final class LocalServer {
    private let root: URL
    private let token: String
    private let access: FileAccess
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private let queue = DispatchQueue(label: "vignette.server")

    /// Which files outside the bundle may be served. Read on the server queue, written from the
    /// main thread when settings change, so it carries its own lock.
    final class FileAccess: @unchecked Sendable {
        private let lock = NSLock()
        private var folder: URL?
        private var unrestricted = false

        func update(folder: URL, unrestricted: Bool) {
            lock.lock(); defer { lock.unlock() }
            self.folder = folder; self.unrestricted = unrestricted
        }

        func allows(_ file: URL) -> Bool {
            lock.lock(); defer { lock.unlock() }
            if unrestricted { return true }
            guard let folder else { return false }
            return Commands.policyError(for: file, watchFolder: folder, debug: false) == nil
        }
    }

    init(root: URL, access: FileAccess, token: String = UUID().uuidString) {
        self.root = root
        self.access = access
        self.token = token
    }

    var indexURL: URL { URL(string: "http://127.0.0.1:\(port)/\(token)/index.html")! }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: params)
        // Captured by value so the callbacks below never need to cross back to `self`.
        let queue = self.queue, root = self.root, token = self.token, access = self.access
        // The listener refuses to start without a connection handler, and the routes need the port
        // the listener only has once it is ready; so the handler reads the routes through a box
        // filled in below. No request can arrive before that: nobody knows the port yet.
        let routes = RouteBox()
        listener.newConnectionHandler = { conn in
            guard let routes = routes.value else { conn.cancel(); return }
            conn.start(queue: queue)
            LocalServer.receive(conn, buffer: Data(), routes: routes)
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed(let err) = state { Log.write("[server] failed: \(err)"); ready.signal() }
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 2)
        // Safe to read now: `wait()` only returns after the `.ready`/`.failed` callback above signaled it.
        port = listener.port?.rawValue ?? 0
        routes.value = Routes(root: root, token: token, port: port, access: access)
        self.listener = listener
        Log.write("[server] port \(port)")
    }

    private final class RouteBox: @unchecked Sendable {
        private let lock = NSLock()
        private var routes: Routes?
        var value: Routes? {
            get { lock.lock(); defer { lock.unlock() }; return routes }
            set { lock.lock(); defer { lock.unlock() }; routes = newValue }
        }
    }

    /// Reads until the header terminator, or gives up past 64 KB.
    private static func receive(_ conn: NWConnection, buffer: Data, routes: Routes) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, _ in
            var buffer = buffer
            if let data { buffer += data }
            if let request = HTTPRequest.parse(buffer) {
                let response = routes.response(for: request)
                conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
            } else if isComplete || buffer.count >= 64 * 1024 || data == nil {
                conn.cancel()
            } else {
                receive(conn, buffer: buffer, routes: routes)
            }
        }
    }

    /// The pure part: which bytes answer which request. Testable without a socket.
    struct Routes: Sendable {
        let root: URL
        let token: String
        let port: UInt16
        let access: FileAccess

        func response(for request: HTTPRequest) -> Data {
            guard request.method == "GET" else { return status(405, "Method Not Allowed") }
            // A browser reaching a rebinding domain sends that domain as Host; only the loopback name is served.
            guard request.host == "127.0.0.1:\(port)" else { return status(400, "Bad Request") }
            let parts = request.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard parts.first == token, parts.count >= 2 else { return status(404, "Not Found") }
            if parts[1] == "file", parts.count == 2 {
                guard let p = request.query["p"] else { return status(404, "Not Found") }
                let file = URL(fileURLWithPath: p).standardizedFileURL
                guard access.allows(file), let body = try? Data(contentsOf: file) else { return status(404, "Not Found") }
                return ok(body, type: LocalServer.mimeType(for: file.pathExtension))
            }
            let file = root.appendingPathComponent(parts.dropFirst().joined(separator: "/")).standardizedFileURL
            guard file.path.hasPrefix(root.standardizedFileURL.path + "/"), let body = try? Data(contentsOf: file) else {
                return status(404, "Not Found")
            }
            return ok(body, type: LocalServer.mimeType(for: file.pathExtension))
        }

        private func ok(_ body: Data, type: String) -> Data {
            Data("HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8) + body
        }

        private func status(_ code: Int, _ reason: String) -> Data {
            Data("HTTP/1.1 \(code) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        }
    }

    /// The URL for a log line: the token is replaced, since the log is readable by any local process.
    /// The same for a line the page sent back: an error message can quote the URL it failed on.
    func redacted(_ text: String) -> String { text.replacingOccurrences(of: token, with: "token") }

    static func redacted(_ url: URL) -> String {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var parts = url.pathComponents.filter { $0 != "/" }
        if !parts.isEmpty { parts[0] = "token" }
        c?.path = "/" + parts.joined(separator: "/")
        return c?.string ?? "?"
    }

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "map": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "heic": return "image/heic"
        case "ico": return "image/x-icon"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "txt", "md": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}

/// The request line and headers of one HTTP/1.1 request. `parse` returns nil until the header
/// terminator has arrived, so a request split across packets is read whole.
struct HTTPRequest: Equatable {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]   // lowercase names

    var host: String? { headers["host"] }

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count >= 2 else { return nil }
        let target = String(requestLine[1])
        let components = URLComponents(string: target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let path = components?.percentEncodedPath.removingPercentEncoding ?? target
        return HTTPRequest(method: String(requestLine[0]), path: path, query: query, headers: headers)
    }
}
