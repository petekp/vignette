import AppKit

/// The menus open on the screen when live ink's note is about to take the keys. An open menu holds
/// the keyboard, so the note's words would go to it and Return would choose its item, and inking
/// keeps a menu open (`LiveInkTap`). Accessibility's cancel action closes a menu as Esc does, without
/// a key. Esc itself is never posted: once the menu is gone it reaches the frontmost app, which may be
/// a terminal running an agent.
@MainActor
enum LiveMenus {
    struct Window {
        let id: CGWindowID
        let pid: pid_t
        /// In global top-left points.
        let frame: CGRect
    }

    /// The windows over every app's, above the menu bar's level, that are not Vignette's and not as
    /// large as a screen: open menus, and such windows as tooltips, which `close` leaves alone.
    static func open() -> [Window] {
        let screens = StateReport.screenFrames
        return LivePacket.listedWindows().filter { window in
            window.layer > LivePacket.menuBarLevel && !screens.contains { window.frame.contains($0) }
        }.map { Window(id: $0.id, pid: $0.pid, frame: $0.frame) }
    }

    /// How long `close` waits for a cancelled menu to leave the screen.
    private static let leaveLimit: TimeInterval = 0.5

    /// Cancels every menu among `windows`, a submenu with the menu it opened from, and calls `done`
    /// once each window a menu was cancelled in has left the screen, with true, or after `leaveLimit`
    /// or a refused cancel, with false. A window that holds no menu is passed over.
    static func close(_ windows: [Window], then done: @escaping (Bool) -> Void) {
        var menus: [AXUIElement] = []
        var waiting: Set<CGWindowID> = []
        for window in windows {
            guard let menu = outermostMenu(in: window) else { continue }
            waiting.insert(window.id)
            if !menus.contains(where: { CFEqual($0, menu) }) { menus.append(menu) }
        }
        let refused = menus.filter { AXUIElementPerformAction($0, kAXCancelAction as CFString) != .success }
        Log.write("[live-ink] menus closing count=\(menus.count) refused=\(refused.count)")
        guard refused.isEmpty else { return done(false) }
        guard !waiting.isEmpty else { return done(true) }
        waitForLeaving(waiting, until: Date().addingTimeInterval(leaveLimit), then: done)
    }

    private static func waitForLeaving(_ ids: Set<CGWindowID>, until deadline: Date, then done: @escaping (Bool) -> Void) {
        let left = ids.isDisjoint(with: open().map(\.id))
        guard left || Date() > deadline else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                MainActor.assumeIsolated { waitForLeaving(ids, until: deadline, then: done) }
            }
            return
        }
        Log.write(left ? "[live-ink] menus closed" : "[live-ink] menus still open after \(leaveLimit) s")
        done(left)
    }

    /// Vignette's own menus while they are open, heard from NSMenu's tracking notifications. Such a
    /// menu tracks on the main thread, where inking runs, and holds the keys the note would take, so
    /// the chord closes it before inking starts. Other apps' menus stay open under the ink.
    @MainActor
    final class Own {
        /// The outermost first.
        private var open: [NSMenu] = []
        private var observers: [Any] = []

        init() {
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated { if let menu = note.object as? NSMenu { self?.open.append(menu) } }
                },
                center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated { self?.open.removeAll { $0 === note.object as? NSMenu } }
                },
            ]
        }

        isolated deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }

        /// Ends the tracking of the outermost open menu, which closes its submenus too.
        func close() {
            guard let menu = open.first else { return }
            menu.cancelTracking()
            Log.write("[live-ink] closed Vignette's own menu")
        }
    }

    /// The menu at `window`'s middle, or the menu it opened from, all the way up, as Accessibility
    /// sees it in the window's app.
    private static func outermostMenu(in window: Window) -> AXUIElement? {
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(window.frame.midX), Float(window.frame.midY), &hit) == .success else { return nil }
        var menu: AXUIElement?
        var current = hit
        for _ in 0..<40 {
            guard let element = current else { break }
            AXUIElementSetMessagingTimeout(element, 0.25)
            if WindowAccessibility.attribute(element, kAXRoleAttribute) as? String == kAXMenuRole { menu = element }
            current = WindowAccessibility.attribute(element, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        return menu
    }
}
