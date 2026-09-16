import Foundation

// Mirror of web/src/bridge.ts. Change both files together; nothing else crosses the boundary.
// `protocolVersion` goes up with any change to either side; a page built for another version is
// refused at `ready`, so a stale web/dist is an error line instead of silent no-ops.
let bridgeProtocolVersion = 3

/// Sent to the page as `window.shotnote.load(payload)`. `key` identifies the image's draft.
struct LoadPayload: Encodable, Equatable {
    /// The file path. Also the asset `src` the page resolves to a served URL.
    let key: String
    let mimeType: String
    let pixelWidth: Int
    let pixelHeight: Int
    let viewWidth: Double
    let viewHeight: Double
}

struct ToolInfo: Identifiable, Equatable {
    let id: String
    let label: String
    let key: String
    let symbol: String   // SF Symbol
}

struct ColorInfo: Identifiable, Equatable {
    let id: String
    let hex: String
}

/// Every call the host makes into the page, rendered as the JavaScript that makes it.
enum PageAPI: Equatable {
    /// `snapshot` is the stored draft's JSON, or nil for a fresh canvas.
    case load(LoadPayload, snapshot: Data?)
    case park
    case reset
    /// Each item's stored draft JSON, by key.
    case export([(key: String, snapshot: Data)])
    case setTool(String)
    case setColor(String)
    case finish

    /// `park` and `export` are async and return a value, so they run through `callAsyncJavaScript`;
    /// the rest are fire-and-forget. All guard on `window.shotnote` so a call that lands before
    /// the page's script runs is a no-op rather than an exception.
    var script: String {
        switch self {
        case .load(let payload, let snapshot):
            let json = PageAPI.json(payload)
            let text = snapshot.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
            return "window.shotnote && window.shotnote.load({\"snapshot\":\(text),\(json.dropFirst()));"
        case .park: return "return window.shotnote ? await window.shotnote.park() : null;"
        case .reset: return "window.shotnote && window.shotnote.reset();"
        case .export(let items):
            let list = items.map { "{\"key\":\(PageAPI.json($0.key)),\"snapshot\":\(String(data: $0.snapshot, encoding: .utf8) ?? "null")}" }
            return "return window.shotnote ? await window.shotnote.export([\(list.joined(separator: ","))]) : null;"
        case .setTool(let id): return "window.shotnote && window.shotnote.setTool(\(PageAPI.json(id)));"
        case .setColor(let id): return "window.shotnote && window.shotnote.setColor(\(PageAPI.json(id)));"
        case .finish: return "window.shotnote && window.shotnote.finish();"
        }
    }

    static func == (a: PageAPI, b: PageAPI) -> Bool { a.script == b.script }

    /// JSON is valid JavaScript for objects, arrays, and strings; `withoutEscapingSlashes` keeps paths readable.
    static func json<T: Encodable>(_ value: T) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        guard let data = try? enc.encode(value), let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
}

/// Received from the page via `window.webkit.messageHandlers.shotnote.postMessage(...)`.
enum WebMessage {
    /// The editor is mounted. Carries the page's protocol version and what the toolbar should offer.
    case ready(protocol: Int, tools: [ToolInfo], colors: [ColorInfo])
    /// The active tool or color changed.
    case tool(tool: String?, color: String)
    /// The image from `load` is on the canvas.
    case loaded(key: String)
    case done(png: Data)
    case cancel
    case log(String)
    /// The current image's annotations changed; a nil snapshot means they were all removed.
    case draft(key: String, snapshot: Any?)

    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready":
            let tools = (dict["tools"] as? [[String: Any]] ?? []).compactMap { t -> ToolInfo? in
                guard let id = t["id"] as? String, let label = t["label"] as? String, let key = t["key"] as? String, let symbol = t["symbol"] as? String else { return nil }
                return ToolInfo(id: id, label: label, key: key, symbol: symbol)
            }
            let colors = (dict["colors"] as? [[String: Any]] ?? []).compactMap { c -> ColorInfo? in
                guard let id = c["id"] as? String, let hex = c["hex"] as? String else { return nil }
                return ColorInfo(id: id, hex: hex)
            }
            self = .ready(protocol: dict["protocol"] as? Int ?? 0, tools: tools, colors: colors)
        case "tool":
            self = .tool(tool: dict["tool"] as? String, color: dict["color"] as? String ?? "")
        case "loaded":
            guard let key = dict["key"] as? String else { return nil }
            self = .loaded(key: key)
        case "cancel": self = .cancel
        case "log": self = .log(dict["message"] as? String ?? "")
        case "done":
            guard let text = dict["png"] as? String, let data = Self.pngData(text) else { return nil }
            self = .done(png: data)
        case "draft":
            guard let key = dict["key"] as? String, dict.keys.contains("snapshot") else { return nil }
            let snapshot = dict["snapshot"]
            self = .draft(key: key, snapshot: snapshot is NSNull ? nil : snapshot)
        default: return nil
        }
    }

    static func pngData(_ dataUrl: String) -> Data? {
        Data(base64Encoded: dataUrl.replacingOccurrences(of: "data:image/png;base64,", with: ""))
    }

    /// For the log when a body does not decode: its type and keys, never its content, which can be megabytes.
    static func describe(_ body: Any) -> String {
        guard let dict = body as? [String: Any] else { return "non-object \(type(of: body))" }
        return "type=\(dict["type"] as? String ?? "?") keys=\(dict.keys.sorted().joined(separator: ","))"
    }
}

/// What `PageAPI.park` returns: the draft to store (nil when the canvas has no annotations) and
/// a rendering when the user changed it since the host last saw one.
struct ParkResult {
    let snapshot: Any?
    let preview: Data?

    init?(body: Any?) {
        guard let dict = body as? [String: Any] else { return nil }
        let snapshot = dict["snapshot"]
        self.snapshot = snapshot is NSNull ? nil : snapshot
        self.preview = (dict["preview"] as? String).flatMap(WebMessage.pngData)
    }
}

/// What `PageAPI.export` returns: the renderings that succeeded, and the error that stopped the run.
struct ExportResult {
    let pngs: [String: Data]
    let error: String?

    init?(body: Any?) {
        guard let dict = body as? [String: Any] else { return nil }
        var pngs: [String: Data] = [:]
        for item in dict["items"] as? [[String: Any]] ?? [] {
            if let key = item["key"] as? String, let text = item["png"] as? String, let data = WebMessage.pngData(text) { pngs[key] = data }
        }
        self.pngs = pngs
        self.error = dict["error"] as? String
    }
}
