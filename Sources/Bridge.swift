import Foundation

// Mirror of web/src/bridge.ts. Change both files together; nothing else crosses the boundary.
// `protocolVersion` goes up with any change to either side; a page built for another version is
// refused at `ready`, so a stale web/dist is an error line instead of silent no-ops.
let bridgeProtocolVersion = 8

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

/// The picture the page should draw when a zoom comes to rest: how far the image is magnified
/// inside the window (1 fits it), the middle of the visible part as a fraction of the image, and
/// the size the host has laid the window out at. The page waits for that size, applies the view,
/// and answers once it has painted it, which is when the stand-in may go.
struct ViewRequest: Encodable, Equatable {
    let ratio: Double
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// One annotation an agent supplied with `add?marks=`. Every number is a fraction of the image:
/// `x` and `y` from its top-left corner, `w` and `h` of its size, `x2` and `y2` where an arrow
/// points, so a mark does not depend on the screenshot's pixel size. `Commands.marks(from:)`
/// checks them; the page turns them into ordinary shapes the user then edits like their own.
struct Mark: Encodable, Equatable {
    enum Kind: String, Encodable, CaseIterable { case ellipse, rectangle, arrow, text }

    let type: Kind
    let x: Double
    let y: Double
    var w: Double?
    var h: Double?
    var x2: Double?
    var y2: Double?
    var text: String?
    /// A color id from web/src/config.ts; the page uses its first color when this is absent.
    var color: String?
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
    /// An agent's marks as a draft, with nothing shown: the answer is a `ParkResult` to store.
    /// `snapshot` is the image's existing draft, which the marks are added to.
    case build(LoadPayload, snapshot: Data?, marks: [Mark])
    /// Each item's stored draft JSON, by key.
    case export([(key: String, snapshot: Data)])
    /// The current image's annotations alone, on a transparent canvas, no larger than this on the
    /// longest side: what the zoom stand-in lays over the screenshot.
    case overlay(maxPixel: Int)
    case setTool(String)
    case setColor(String)
    /// The picture to draw at the end of a zoom, and the answer that says it has been painted.
    case setView(ViewRequest)
    case finish

    /// `park`, `build`, `export`, and `setView` are async and return a value, so they run through
    /// `callAsyncJavaScript`; the rest are fire-and-forget. All guard on `window.shotnote` so a
    /// call that lands before the page's script runs is a no-op rather than an exception.
    var script: String {
        switch self {
        case .load(let payload, let snapshot):
            return "window.shotnote && window.shotnote.load(\(PageAPI.payload(payload, snapshot)));"
        case .park: return "return window.shotnote ? await window.shotnote.park() : null;"
        case .reset: return "window.shotnote && window.shotnote.reset();"
        case .build(let payload, let snapshot, let marks):
            return "return window.shotnote ? await window.shotnote.build(\(PageAPI.payload(payload, snapshot)),\(PageAPI.json(marks))) : null;"
        case .export(let items):
            let list = items.map { "{\"key\":\(PageAPI.json($0.key)),\"snapshot\":\(String(data: $0.snapshot, encoding: .utf8) ?? "null")}" }
            return "return window.shotnote ? await window.shotnote.export([\(list.joined(separator: ","))]) : null;"
        case .overlay(let maxPixel):
            return "return window.shotnote ? await window.shotnote.overlay(\(maxPixel)) : null;"
        case .setTool(let id): return "window.shotnote && window.shotnote.setTool(\(PageAPI.json(id)));"
        case .setColor(let id): return "window.shotnote && window.shotnote.setColor(\(PageAPI.json(id)));"
        case .setView(let view): return "return window.shotnote ? await window.shotnote.setView(\(PageAPI.json(view))) : null;"
        case .finish: return "window.shotnote && window.shotnote.finish();"
        }
    }

    static func == (a: PageAPI, b: PageAPI) -> Bool { a.script == b.script }

    /// The `load` object: the payload with the stored draft's JSON spliced in, since a snapshot is
    /// JSON the host never decodes. `build` takes the same object.
    static func payload(_ payload: LoadPayload, _ snapshot: Data?) -> String {
        let text = snapshot.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        return "{\"snapshot\":\(text),\(json(payload).dropFirst())"
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
    /// The editor is mounted. Carries the page's protocol version, what the toolbar should offer
    /// (`colors` is empty while the palette is hidden), and every color a pushed mark may name.
    case ready(protocol: Int, tools: [ToolInfo], colors: [ColorInfo], markColors: [ColorInfo])
    /// The active tool or color changed.
    case tool(tool: String?, color: String)
    /// The image from `load` is on the canvas.
    case loaded(key: String)
    /// Finished; a nil PNG means nothing was drawn and the original is what gets copied.
    case done(png: Data?)
    case cancel
    case log(String)
    /// The current image's annotations changed; a nil snapshot means they were all removed.
    case draft(key: String, snapshot: Any?)
    /// Multiply the window size by `factor`; nil asks for the fitted size. `at` is the cursor, a
    /// fraction of the window with y from the top, whose point zoom keeps in place; nil (the
    /// keyboard) means the window's middle.
    case zoom(factor: Double?, at: CGPoint?)

    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready":
            let tools = (dict["tools"] as? [[String: Any]] ?? []).compactMap { t -> ToolInfo? in
                guard let id = t["id"] as? String, let label = t["label"] as? String, let key = t["key"] as? String, let symbol = t["symbol"] as? String else { return nil }
                return ToolInfo(id: id, label: label, key: key, symbol: symbol)
            }
            func colors(_ key: String) -> [ColorInfo] {
                (dict[key] as? [[String: Any]] ?? []).compactMap { c -> ColorInfo? in
                    guard let id = c["id"] as? String, let hex = c["hex"] as? String else { return nil }
                    return ColorInfo(id: id, hex: hex)
                }
            }
            self = .ready(protocol: dict["protocol"] as? Int ?? 0, tools: tools, colors: colors("colors"), markColors: colors("markColors"))
        case "tool":
            self = .tool(tool: dict["tool"] as? String, color: dict["color"] as? String ?? "")
        case "loaded":
            guard let key = dict["key"] as? String else { return nil }
            self = .loaded(key: key)
        case "cancel": self = .cancel
        case "log": self = .log(dict["message"] as? String ?? "")
        case "done":
            guard let raw = dict["png"] else { return nil }
            if raw is NSNull { self = .done(png: nil) }
            else if let text = raw as? String, let data = Self.pngData(text) { self = .done(png: data) }
            else { return nil }
        case "draft":
            guard let key = dict["key"] as? String, dict.keys.contains("snapshot") else { return nil }
            let snapshot = dict["snapshot"]
            self = .draft(key: key, snapshot: snapshot is NSNull ? nil : snapshot)
        case "zoom":
            guard let raw = dict["factor"] else { return nil }
            let at = Self.point(dict["at"])
            if raw is NSNull { self = .zoom(factor: nil, at: at) }
            else if let n = raw as? NSNumber, n.doubleValue.isFinite, n.doubleValue > 0 { self = .zoom(factor: n.doubleValue, at: at) }
            else { return nil }
        default: return nil
        }
    }

    /// A unit point the page sent, or nil when it sent none: a keyboard step names no cursor, and
    /// a half-written one must not move the window on its own.
    static func point(_ raw: Any?) -> CGPoint? {
        guard let dict = raw as? [String: Any],
              let x = (dict["x"] as? NSNumber)?.doubleValue, x.isFinite,
              let y = (dict["y"] as? NSNumber)?.doubleValue, y.isFinite else { return nil }
        return CGPoint(x: x, y: y)
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
