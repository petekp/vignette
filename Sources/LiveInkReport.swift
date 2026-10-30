import Foundation

extension LivePacket.Plan {
    /// What an ask's picture is of, for the log.
    var forLog: String {
        switch self {
        case .window(let id): id.map { "window \($0)" } ?? "screen"
        case .area(let rect, let windows, let alone):
            "area \(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height)) windows=\(windows.map(String.init).joined(separator: ","))"
                + " alone=\(alone.map { "\($0.window):covered=\($0.covered.count),outside=\($0.outside.count)" }.joined(separator: ";"))"
        }
    }
}

extension LivePacket {
    /// A picture of an area, its frame and its windows, for the log; empty for a picture of one window.
    var areaForLog: String {
        guard case .area = subject else { return "" }
        return " area=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height)) windows=\(windows.count)"
            + " alone=\(alone.count) aloneBytes=\(alone.map { String($0.picture.count) }.joined(separator: ","))"
    }
}

extension LiveAsks.Ask {
    /// The ask in `[state] liveInk.asks`.
    var stateJSON: [String: Any] {
        var json: [String: Any] = ["id": id, "phase": phase.rawValue, "about": about.count, "picture": picture, "toSession": toSession]
        if let reason { json["reason"] = reason }
        if let say, case .text(let text) = say.geometry { json["sayLength"] = text.text.count }
        return json
    }
}
