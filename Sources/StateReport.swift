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

    static func residentBytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }

    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// Every screen's frame, in global top-left points.
    static var screenFrames: [CGRect] {
        let height = primaryHeight
        return NSScreen.screens.map { fromTopLeft($0.frame, primaryHeight: height) }
    }

    /// The screen holding `point`, in global top-left points.
    static func screen(at point: CGPoint) -> NSScreen? {
        let height = primaryHeight
        return NSScreen.screens.first { fromTopLeft($0.frame, primaryHeight: height).contains(point) }
    }

    /// `rect` between global top-left points and AppKit's screen coordinates, either way.
    static func flipped(_ rect: CGRect) -> CGRect { fromTopLeft(rect, primaryHeight: primaryHeight) }

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
