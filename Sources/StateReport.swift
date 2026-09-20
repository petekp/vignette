import AppKit

/// The `[state] {json}` line: every section is a plain JSON object, rendered as one line with
/// sorted keys, so an agent can parse it with any JSON reader. Frames are `[x, y, w, h]` in
/// global Core Graphics points: origin at the top-left of the primary display, y down, the same
/// convention as `scripts/input.sh`, so a frame from here can be clicked as is.
struct StateReport {
    var sections: [String: Any] = [:]

    /// Lays out `frame` (AppKit, origin bottom-left of the primary display) in global top-left points.
    static func topLeft(_ frame: NSRect, primaryHeight: CGFloat) -> [Int] {
        [Int(frame.minX.rounded()), Int((primaryHeight - frame.maxY).rounded()), Int(frame.width.rounded()), Int(frame.height.rounded())]
    }

    /// The inverse: a frame in global top-left points, back in AppKit's coordinates.
    static func fromTopLeft(_ frame: CGRect, primaryHeight: CGFloat) -> NSRect {
        NSRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// One line, or a line that says why it could not be rendered; never nil, so the caller always logs.
    func rendered() -> String {
        guard JSONSerialization.isValidJSONObject(sections),
              let data = try? JSONSerialization.data(withJSONObject: sections, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"error":"state not serializable"}"#
        }
        return Log.oneLine(text)
    }
}
