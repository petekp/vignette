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

/// Received from the page via `window.webkit.messageHandlers.shotnote.postMessage(...)`.
enum WebMessage {
    case ready
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
        case "ready": self = .ready
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
