import Foundation

// Mirror of web/src/bridge.ts. Change both files together; nothing else crosses the boundary.

/// Sent to the page as `window.shotnote.load(payload)`.
struct LoadPayload: Encodable {
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

    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready": self = .ready
        case "cancel": self = .cancel
        case "log": self = .log(dict["message"] as? String ?? "")
        case "done":
            guard let text = dict["png"] as? String else { return nil }
            let base64 = text.replacingOccurrences(of: "data:image/png;base64,", with: "")
            guard let data = Data(base64Encoded: base64) else { return nil }
            self = .done(png: data)
        default: return nil
        }
    }
}
