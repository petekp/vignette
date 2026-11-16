import AppKit

extension LiveWindows {
    /// An app's window, from the window list.
    struct Target {
        let id: CGWindowID
        let pid: pid_t
        let app: String?
        /// In global top-left points.
        let frame: CGRect
    }

    /// The topmost window under `point`, in global top-left points, not Vignette's and below the Dock,
    /// whose window covers the screen. With `ordinary`, nil unless it is an app's ordinary window: a
    /// panel or menu over one comes and goes, so marks never go on it.
    static func window(under point: CGPoint, ordinary: Bool = true) -> Target? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return window(under: point, in: windows, own: ProcessInfo.processInfo.processIdentifier, ordinary: ordinary)
    }

    /// `window(under:ordinary:)` in `windows`, the window list's entries front to back. A prompt of
    /// macOS's own is passed over: it covers the window the person drew on until it is answered.
    nonisolated static func window(under point: CGPoint, in windows: [[String: Any]], own: pid_t, ordinary: Bool) -> Target? {
        for info in windows where !SystemPrompts.isPrompt(info) {
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let level = info[kCGWindowLayer as String] as? Int, level < Int(CGWindowLevelForKey(.dockWindow)),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let frame = WindowList.bounds(info), frame.width > 40, frame.height > 40, frame.contains(point) else { continue }
            guard level == 0 || !ordinary else { return nil }
            return Target(id: id, pid: pid, app: info[kCGWindowOwnerName as String] as? String, frame: frame)
        }
        return nil
    }
}
