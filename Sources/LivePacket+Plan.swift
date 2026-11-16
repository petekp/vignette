import AppKit
import ScreenCaptureKit
import Vision

extension LivePacket {
    /// What an ask's picture is of, decided from the ink asked about and the windows on the screen
    /// when it is asked.
    enum Plan: Equatable {
        /// The ink is on one window, or with nil on none: that window alone, or the screen under the ink.
        case window(CGWindowID?)
        /// The ink is on several windows: the part of the screen their frames cover, on the newest
        /// ink's display, as the person sees it. `windows` hold the ink, front to back. A window holding
        /// ink that picture does not show, under a window in front or past it, goes alone as well.
        case area(CGRect, windows: [CGWindowID], alone: [Alone])

        struct Alone: Equatable {
            let window: CGWindowID
            /// The ink asked about on the window, oldest first.
            let ink: [Mark.ID]
            /// Of `ink`: under another app's window in front, and past the area's picture.
            let covered: [Mark.ID]
            let outside: [Mark.ID]
        }
    }

    /// A mark asked about: its box in global top-left points, and the window it is on, if any.
    struct Asked: Equatable {
        let id: Mark.ID
        let box: CGRect
        let window: CGWindowID?
    }

    /// An app's window on the screen, as the window server lists it.
    struct Listed: Equatable {
        let id: CGWindowID
        let pid: pid_t
        let layer: Int
        /// In global top-left points.
        let frame: CGRect
    }

    /// How far round ink on no window an area reaches, in points.
    static let screenInkMargin: CGFloat = 64
    /// The least width and height at which a window of the ink's own app covers it: smaller ones,
    /// such as a sheet or a title bar's window, sit over their own window.
    static let ownAppCoverSize: CGFloat = 200

    /// Windows above this level, the menu bar's items', are over every app's windows: an open menu, or a
    /// tooltip.
    static let menuBarLevel = Int(CGWindowLevelForKey(.statusWindow))

    /// The picture for `asked`, oldest first, from `windows`, the app windows on the screen front to
    /// back, and `screens`, the displays' frames, all in global top-left points.
    ///
    /// Ink drawn over a window above the menu bar, such as an open menu, is pinned to the window under
    /// it, and a capture of that window alone leaves the menu out. So the picture is then of the screen
    /// as the person sees it, round the menu and the ink's windows. A window as large as a screen is left
    /// out, since it covers every window and so tells nothing about this ink.
    static func plan(for asked: [Asked], windows: [Listed], screens: [CGRect]) -> Plan {
        var holders: [CGWindowID?] = []
        for mark in asked where !holders.contains(mark.window) { holders.append(mark.window) }
        let over = windows.filter { window in
            window.layer > menuBarLevel && !screens.contains { window.frame.contains($0) } && asked.contains { $0.box.intersects(window.frame) }
        }
        guard holders.count > 1 || !over.isEmpty, let newest = asked.last else { return .window(holders.first ?? nil) }
        let order = Dictionary(windows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: min)
        let screen = screens.first { $0.contains(CGPoint(x: newest.box.midX, y: newest.box.midY)) }
            ?? screens.first { $0.intersects(newest.box) }
        var area = CGRect.null
        for mark in asked {
            let frame = mark.window.flatMap { id in order[id].map { windows[$0].frame } }
            let part = frame ?? mark.box.insetBy(dx: -screenInkMargin, dy: -screenInkMargin)
            area = area.union(screen.map(part.intersection) ?? part)
        }
        for window in over { area = area.union(screen.map(window.frame.intersection) ?? window.frame) }
        guard !area.isNull else { return .window(newest.window) }
        func isCovered(_ mark: Asked) -> Bool {
            guard let id = mark.window, let index = order[id] else { return false }
            let owner = windows[index].pid
            return windows[..<index].contains { window in
                let isLarge = window.frame.width >= ownAppCoverSize && window.frame.height >= ownAppCoverSize
                return window.layer == 0 && (window.pid != owner || isLarge) && window.frame.intersects(mark.box)
            }
        }
        let alone = holders.compactMap { $0 }.compactMap { window -> Plan.Alone? in
            let ink = asked.filter { $0.window == window }
            let outside = ink.filter { !$0.box.intersects(area) }
            let covered = ink.filter { $0.box.intersects(area) && isCovered($0) }
            guard !outside.isEmpty || !covered.isEmpty else { return nil }
            return Plan.Alone(window: window, ink: ink.map(\.id), covered: covered.map(\.id), outside: outside.map(\.id))
        }
        let shown = holders.compactMap { $0 }.filter { id in order[id].map { windows[$0].frame.intersects(area) } ?? false }
            .sorted { (order[$0] ?? .max) < (order[$1] ?? .max) }
        return .area(area, windows: shown, alone: alone)
    }

    /// The app windows on the screen, front to back, but Vignette's, the Dock's, the menu bar's and
    /// its items', and macOS's own prompts. Ink is not drawn on those, and they never cover the ink's
    /// window.
    @MainActor
    static func listedWindows() -> [Listed] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return listed(windows, own: ProcessInfo.processInfo.processIdentifier)
    }

    /// `listedWindows()` from `windows`, the window list's entries front to back.
    static func listed(_ windows: [[String: Any]], own: pid_t) -> [Listed] {
        windows.filter { !SystemPrompts.isPrompt($0) }.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let layer = info[kCGWindowLayer as String] as? Int, layer < Int(CGWindowLevelForKey(.dockWindow)) || layer > menuBarLevel,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let frame = WindowList.bounds(info) else { return nil }
            return Listed(id: id, pid: pid, layer: layer, frame: frame)
        }
    }
}
