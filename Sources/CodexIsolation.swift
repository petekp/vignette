import Foundation
import Network

/// What holds Codex's responder to Vignette's prompt and no tools, and the check that it held. On
/// 0.165 a turn started plainly carries the shell, patch, image, search and goal tools, the skills
/// and the working folder's `AGENTS.md` (docs/codex-issues.md, 2026-10-30). These switches take
/// them out, and the warm-up proves it from the request Codex sends: before any screen content, the
/// warm-up runs on a thread whose model provider is `CodexCheckProvider`, and the real thread opens
/// only when `refusal(of:)` finds nothing in that request but the prompt and the warm-up.
enum CodexIsolation {
    /// The switches, in the order `codex app-server` takes them. A feature name a build does not
    /// know stops it at once ("Unknown feature flag"), which the responder reports.
    static let arguments: [String] = [
        "--disable", "shell_tool", "--disable", "unified_exec", "--disable", "view_image", "--disable", "goals",
        "--disable", "tool_search", "--disable", "skill_search", "--disable", "multi_agent", "--disable", "apps",
        "--disable", "plugins", "--disable", "memories", "--disable", "hooks", "--disable", "image_generation",
        "--disable", "browser_use", "--disable", "computer_use", "--disable", "tool_suggest", "--disable", "sleep_tool",
        "--disable", "shell_snapshot",
        "-c", #"web_search="disabled""#, "-c", "tools.experimental_request_user_input.enabled=false",
        "-c", "skills.include_instructions=false", "-c", "include_permissions_instructions=false",
        "-c", "include_environment_context=false", "-c", "include_apps_instructions=false",
        "-c", "include_collaboration_mode_instructions=false", "-c", "project_doc_max_bytes=0",
        "-c", "notify=[]", "-c", "mcp_servers={}", "-c", "analytics.enabled=false",
    ]

    /// `codex debug models` with what adds tools taken out of every model: the patch tool, the
    /// code-mode tools, the collaboration tools and the experimental ones, and the "lite" request
    /// that carries tools inside `input`. Nil when the catalog is not one.
    static func strippedCatalog(_ data: Data) -> Data? {
        guard var catalog = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let models = catalog["models"] as? [[String: Any]], !models.isEmpty else { return nil }
        catalog["models"] = models.map { model -> [String: Any] in
            var model = model
            model["apply_patch_tool_type"] = NSNull()
            model["tool_mode"] = NSNull()
            model["multi_agent_version"] = "disabled"
            model["experimental_supported_tools"] = [Any]()
            model["use_responses_lite"] = false
            return model
        }
        return try? JSONSerialization.data(withJSONObject: catalog, options: [.sortedKeys])
    }

    /// Why the warm-up's request to the model is not the request Vignette means to send, or nil
    /// when it is: no tools, no instructions of Codex's own, and nothing in its input but `prompt`
    /// as a developer message and `warmUp` as the one user message. Anything it cannot read counts
    /// against it.
    static func refusal(of body: Data, prompt: String, warmUp: String) -> String? {
        guard let request = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return "a request that is not JSON" }
        if let tools = request["tools"] {
            guard let list = tools as? [Any], list.isEmpty else { return "tools=\((tools as? [Any])?.count ?? -1)" }
        }
        if let instructions = request["instructions"] {
            guard let text = instructions as? String, text.isEmpty || text == prompt else { return "instructions of its own" }
        }
        guard let input = request["input"] as? [[String: Any]] else { return "no input" }
        var asks = 0
        for item in input {
            guard (item["type"] as? String ?? "message") == "message" else { return "an input item \(item["type"] as? String ?? "?")" }
            let parts = item["content"] as? [[String: Any]] ?? []
            guard parts.allSatisfy({ $0["type"] as? String == "input_text" }) else { return "an input part that is not text" }
            let text = parts.compactMap { $0["text"] as? String }.joined()
            switch item["role"] as? String {
            case "developer", "system":
                guard text == prompt else { return "a \(item["role"] as? String ?? "") message of its own" }
            case "user":
                guard text == warmUp else { return "a user message of its own" }
                asks += 1
            default:
                return "a message from \(item["role"] as? String ?? "?")"
            }
        }
        return asks == 1 ? nil : "\(asks) user messages"
    }
}

/// A model provider on localhost, inside Vignette, for the isolation check's warm-up: it keeps
/// the body of each request posted to it and answers "Ready." as a streamed response, so the turn
/// ends and the request can be read. It answers only on 127.0.0.1.
final class CodexCheckProvider: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "vignette.codex-check")
    private let lock = NSLock()
    private var posted: [Data] = []

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Starts listening, and answers its port, or nil when it could not listen, once.
    func start(_ ready: @escaping @Sendable (UInt16?) -> Void) {
        let once = Once(ready)
        listener.stateUpdateHandler = { [listener] state in
            switch state {
            case .ready: once.call(listener.port?.rawValue)
            case .failed, .cancelled: once.call(nil)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.start(queue: queue)
    }

    func stop() { listener.cancel() }

    /// The bodies of the requests posted to it so far, oldest first.
    var requests: [Data] { lock.withLock { posted } }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, after: Data())
    }

    private func receive(on connection: NWConnection, after buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self else { return connection.cancel() }
            let buffer = buffer + (data ?? Data())
            if let request = HTTPRequest(buffer) {
                return answer(request, on: connection)
            }
            if done || error != nil || buffer.count > 16 << 20 { return connection.cancel() }
            receive(on: connection, after: buffer)
        }
    }

    private func answer(_ request: HTTPRequest, on connection: NWConnection) {
        let reply: Data
        if request.method == "POST" {
            lock.withLock { posted.append(request.body) }
            reply = Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n".utf8)
                + Self.readyStream
        } else {
            let body = Data(#"{"models":[],"data":[]}"#.utf8)
            reply = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
        }
        connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// The Responses API's events for one finished message that says "Ready.".
    private static let readyStream: Data = {
        let text = #"{"say":"Ready.","marks":[],"steps":null,"actions":null}"#
        let item: [String: Any] = ["type": "message", "id": "msg_check", "role": "assistant", "status": "completed",
                                   "content": [["type": "output_text", "text": text, "annotations": [Any]()]]]
        var started = item
        started["status"] = "in_progress"
        started["content"] = [Any]()
        let usage: [String: Any] = ["input_tokens": 0, "output_tokens": 0, "total_tokens": 0,
                                    "input_tokens_details": ["cached_tokens": 0], "output_tokens_details": ["reasoning_tokens": 0]]
        let events: [(String, [String: Any])] = [
            ("response.created", ["type": "response.created", "response": ["id": "resp_check"]]),
            ("response.output_item.added", ["type": "response.output_item.added", "output_index": 0, "item": started]),
            ("response.output_text.delta", ["type": "response.output_text.delta", "item_id": "msg_check", "output_index": 0, "content_index": 0, "delta": text]),
            ("response.output_item.done", ["type": "response.output_item.done", "output_index": 0, "item": item]),
            ("response.completed", ["type": "response.completed", "response": ["id": "resp_check", "usage": usage]]),
        ]
        return events.reduce(into: Data()) { stream, event in
            let data = (try? JSONSerialization.data(withJSONObject: event.1)) ?? Data()
            stream += Data("event: \(event.0)\ndata: ".utf8) + data + Data("\n\n".utf8)
        }
    }()
}

/// One HTTP/1.1 request, once all of it has arrived: a body by its `Content-Length`, or by chunks.
struct HTTPRequest {
    let method: String
    let body: Data

    init?(_ data: Data) {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        guard let method = head.first?.split(separator: " ").first else { return nil }
        var fields: [String: String] = [:]
        for line in head.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            fields[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let rest = Data(data[end.upperBound...])
        if fields["transfer-encoding"]?.lowercased().contains("chunked") == true {
            guard let body = Self.unchunked(rest) else { return nil }
            self.body = body
        } else {
            let length = Int(fields["content-length"] ?? "0") ?? 0
            guard rest.count >= length else { return nil }
            body = rest.prefix(length)
        }
        self.method = String(method)
    }

    /// A chunked body, or nil until its last chunk has arrived.
    private static func unchunked(_ data: Data) -> Data? {
        var body = Data()
        var at = data.startIndex
        while let line = data[at...].firstRange(of: Data("\r\n".utf8)) {
            guard let size = Int(String(decoding: data[at..<line.lowerBound], as: UTF8.self).split(separator: ";").first ?? "", radix: 16) else { return nil }
            if size == 0 { return body }
            let start = line.upperBound
            guard data.distance(from: start, to: data.endIndex) >= size + 2 else { return nil }
            let stop = data.index(start, offsetBy: size)
            body += data[start..<stop]
            at = data.index(stop, offsetBy: 2)
        }
        return nil
    }
}

/// A callback called at most once, from any thread.
private final class Once<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: ((Value) -> Void)?
    init(_ callback: @escaping (Value) -> Void) { self.callback = callback }
    func call(_ value: Value) {
        let callback = lock.withLock { () -> ((Value) -> Void)? in
            defer { self.callback = nil }
            return self.callback
        }
        callback?(value)
    }
}
