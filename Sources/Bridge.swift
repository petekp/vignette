import Foundation

// Mirror of web/src/bridge.ts. Change both files together; nothing else crosses the boundary.

/// Sent to the page as `window.shotnote.load(payload)`. `key` identifies the image's draft.
struct LoadPayload: Encodable {
    let key: String
    let dataUrl: String
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

/// Received from the page via `window.webkit.messageHandlers.shotnote.postMessage(...)`.
enum WebMessage {
    /// The editor is mounted. Carries what the toolbar should offer.
    case ready(tools: [ToolInfo], colors: [ColorInfo])
    /// The active tool or color changed.
    case tool(tool: String?, color: String)
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
            self = .ready(tools: tools, colors: colors)
        case "tool":
            self = .tool(tool: dict["tool"] as? String, color: dict["color"] as? String ?? "")
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
}
