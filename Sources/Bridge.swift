import Foundation

// Mirror of web/src/bridge.ts. Change both files together; nothing else crosses the boundary.
// `protocolVersion` goes up with any change to either side; a page built for another version is
// refused at `ready`, so a stale web/dist is an error line instead of silent no-ops.
let bridgeProtocolVersion = 2

/// Sent to the page as `window.shotnote.load(payload)`. `key` identifies the image's draft.
struct LoadPayload: Encodable, Equatable {
    let key: String
    /// Same-origin URL of the image, served by LocalServer.
    let imageUrl: String
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
    case load(LoadPayload)
    case park
    case reset
    case forget([String])
    case export([String])
    case setTool(String)
    case setColor(String)
    case finish

    /// `park` is awaited by the host; the rest are fire-and-forget. All guard on `window.shotnote`
    /// so a call that lands before the page's script runs is a no-op rather than an exception.
    var script: String {
        switch self {
        case .load(let payload): return "window.shotnote && window.shotnote.load(\(PageAPI.json(payload)));"
        case .park: return "if (window.shotnote) await window.shotnote.park();"
        case .reset: return "window.shotnote && window.shotnote.reset();"
        case .forget(let keys): return "window.shotnote && window.shotnote.forget(\(PageAPI.json(keys)));"
        case .export(let keys): return "window.shotnote && window.shotnote.export(\(PageAPI.json(keys)));"
        case .setTool(let id): return "window.shotnote && window.shotnote.setTool(\(PageAPI.json(id)));"
        case .setColor(let id): return "window.shotnote && window.shotnote.setColor(\(PageAPI.json(id)));"
        case .finish: return "window.shotnote && window.shotnote.finish();"
        }
    }

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
    /// Keys of every image that currently has unsaved annotations.
    case drafts([String])
    /// A rendering of one image with its draft, sent when the draft is parked.
    case draft(key: String, preview: Data)
    /// Result of `window.shotnote.export(keys)`, in the order requested.
    case exported([(key: String, png: Data)])

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
        case "drafts":
            self = .drafts(dict["keys"] as? [String] ?? [])
        case "draft":
            guard let key = dict["key"] as? String, let text = dict["preview"] as? String, let data = Self.pngData(text) else { return nil }
            self = .draft(key: key, preview: data)
        case "exported":
            let items = (dict["items"] as? [[String: Any]] ?? []).compactMap { item -> (key: String, png: Data)? in
                guard let key = item["key"] as? String, let text = item["png"] as? String, let data = Self.pngData(text) else { return nil }
                return (key, data)
            }
            self = .exported(items)
        default: return nil
        }
    }

    private static func pngData(_ dataUrl: String) -> Data? {
        Data(base64Encoded: dataUrl.replacingOccurrences(of: "data:image/png;base64,", with: ""))
    }

    /// For the log when a body does not decode: its type and keys, never its content, which can be megabytes.
    static func describe(_ body: Any) -> String {
        guard let dict = body as? [String: Any] else { return "non-object \(type(of: body))" }
        return "type=\(dict["type"] as? String ?? "?") keys=\(dict.keys.sorted().joined(separator: ","))"
    }
}
