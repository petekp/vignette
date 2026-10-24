import AppKit
import QuartzCore

/// The windows that have live ink marks, and the marks on them (docs/live-ink.md). A mark belongs to
/// the window it was drawn on and keeps its offset from the window's top-left, whatever the window's
/// content does and whatever size the window takes. Each such window has an overlay window of its
/// own, ordered just above it, so windows in front cover its marks. The marks move with their window
/// on every display frame, fade out as it minimises and back once it is on the screen again, and go
/// when it closes.
@MainActor
final class LiveWindows {
    /// Marks that went with their window when it closed.
    var onGone: ((Set<Mark.ID>) -> Void)?
    /// The rect a mark draws in, its stroke, edge and shadows included, in the mark's own coordinates.
    var drawnExtent: ((Mark) -> CGRect?)?

    private var windows: [CGWindowID: Tracked] = [:]
    private var link: CADisplayLink?
    private var monitors: [Any] = []
    private var observers: [(NotificationCenter, Any)] = []
    /// One per app with marked windows: says when one of them starts to move or resize, which
    /// the window list alone would see only at the next tick, a tenth of a second later at rest.
    private var watchers: [pid_t: AXObserver] = [:]
    /// Until when the tick runs at the display's rate: something may be moving a window.
    private var activeUntil: CFTimeInterval = 0
    private var lastIdleTick: CFTimeInterval = 0
    private var buttonDown = false

    /// How long a window back on the screen, from the Dock, another Space or a hidden app, is let land
    /// before its marks show. Not motion: the motion setting leaves it as it is.
    static let landing: CFTimeInterval = 0.2

    var isEmpty: Bool { windows.isEmpty }

    /// One window with marks.
    @MainActor
    private final class Tracked {
        let id: CGWindowID
        let pid: pid_t
        let app: String?
        /// From the window list, in global top-left points.
        var frame: CGRect
        let overlay: WindowOverlay
        var pins: [Pin] = []
        var onScreen = true
        /// When its hidden marks show again: the window is back on the screen and has landed.
        var showFrom: CFTimeInterval?
        /// Floated over normal windows while its app raises its windows over the overlay.
        var liftedAt: CFTimeInterval?
        /// Faded because the person asked to minimise it.
        var minimisingSince: CFTimeInterval?
        /// Accessibility calls for this window wait on its app, one at a time.
        let queue: DispatchQueue
        var reorders = 0

        init(id: CGWindowID, pid: pid_t, app: String?, frame: CGRect) {
            self.id = id
            self.pid = pid
            self.app = app
            self.frame = frame
            overlay = WindowOverlay(target: id)
            queue = DispatchQueue(label: "live-ink.window.\(id)", qos: .userInitiated)
        }
    }

    /// One mark on a window.
    private struct Pin {
        /// In points from the window's top-left.
        var mark: Mark
        /// Faded with its window as the window minimised or went away, until the window is back.
        var hidden = false
        /// Its point is past the window's edge, after the window shrank: hidden until the window grows
        /// over it again.
        var outside = false
        /// Its opacity while it shows: faint while the answer points elsewhere (`light`), so it comes
        /// back faint after it was hidden.
        var strength: Float = 1
        /// Kept on its window, drawn at no opacity and not counted as shown (`setAside`).
        var aside = false
        var visible: Bool { !hidden && !outside }
        var shows: Bool { visible && !aside }
        var opacity: Float { aside ? 0 : strength }
    }

    /// An app's window, from the window list.
    struct Target {
        let id: CGWindowID
        let pid: pid_t
        let app: String?
        /// In global top-left points.
        let frame: CGRect
    }

    // MARK: Marks

    /// The topmost window under `point`, in global top-left points, that is not Vignette's, below the
    /// Dock's level, as `LivePacket.window(under:)` finds it.
    static func window(under point: CGPoint) -> Target? {
        let own = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in windows {
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let level = info[kCGWindowLayer as String] as? Int, level < Int(CGWindowLevelForKey(.dockWindow)),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let frame = WindowList.bounds(info), frame.width > 40, frame.height > 40, frame.contains(point) else { continue }
            // Only an app's ordinary windows carry marks: a panel or a menu over them comes and goes.
            guard level == 0 else { return nil }
            return Target(id: id, pid: pid, app: info[kCGWindowOwnerName as String] as? String, frame: frame)
        }
        return nil
    }

    /// The window under `point`, when it is one marks can be pinned to.
    func target(under point: CGPoint) -> Target? { Self.window(under: point) }

    /// The window `id`, while it is on screen.
    func target(id: CGWindowID) -> Target? {
        if let window = windows[id] { return Target(id: id, pid: window.pid, app: window.app, frame: window.frame) }
        guard let info = WindowList.describe([id]).first, info[kCGWindowIsOnscreen as String] as? Bool ?? false,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t, let frame = WindowList.bounds(info) else { return nil }
        return Target(id: id, pid: pid, app: info[kCGWindowOwnerName as String] as? String, frame: frame)
    }

    /// Puts `mark`, in global top-left points, on `target`, at its offset from the window's top-left.
    func pin(_ mark: Mark, to target: Target) {
        let window = tracked(target)
        let origin = window.frame.origin
        window.pins.removeAll { $0.mark.id == mark.id }
        let local = Self.translated(mark, by: CGVector(dx: -origin.x, dy: -origin.y))
        window.pins.append(Pin(mark: local, hidden: window.minimisingSince != nil || window.showFrom != nil,
                               outside: !Self.fits(local, in: window.frame.size)))
        // A note or a reply can hang past the window's edge, where no element answers.
        if mark.kind != .text {
            let point = Self.point(of: mark), pid = window.pid
            window.queue.async { WindowAccessibility.requestTree(pid: pid, at: point) }
        }
        fitOverlay(window)
        place(window)
        start()
    }

    func popover(of id: Mark.ID) -> ReplyPopover? {
        windows.values.lazy.compactMap { $0.overlay.marks.popover(of: id) }.first
    }

    /// Takes these marks off their windows.
    func remove(_ ids: Set<Mark.ID>) {
        guard !ids.isEmpty else { return }
        for window in windows.values { window.pins.removeAll { ids.contains($0.mark.id) } }
        dropEmpty()
    }

    /// Takes every mark off, fading.
    func removeAll() {
        for window in windows.values { retire(window.overlay) }
        windows = [:]
        stop()
    }

    /// Fades the overlay's marks out, then closes it.
    private func retire(_ overlay: WindowOverlay) {
        overlay.marks.removeAll()
        let fade = LiveMarksLayer.removalFade
        guard fade > 0 else { overlay.close(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + fade) { overlay.close() }
    }

    /// Every mark where it is drawn now, in global top-left points, with whether it shows.
    var marks: [(mark: Mark, shown: Bool, window: CGWindowID)] {
        windows.values.flatMap { window in
            window.pins.map { pin in
                let offset = CGVector(dx: window.frame.minX, dy: window.frame.minY)
                return (Self.translated(pin.mark, by: offset), pin.shows && window.onScreen, window.id)
            }
        }
    }

    /// The window a mark is on.
    func window(of id: Mark.ID) -> CGWindowID? {
        windows.values.first { $0.pins.contains { $0.mark.id == id } }?.id
    }

    /// Whether a mark that shows, on a window on the screen and not set aside, passes `test`.
    func containsShown(where test: (Mark.ID) -> Bool) -> Bool {
        windows.values.contains { window in window.onScreen && window.pins.contains { $0.shows && test($0.mark.id) } }
    }

    /// Hides these marks where they are, on their windows.
    func setAside(_ ids: Set<Mark.ID>) { changeAside(ids, to: true) }

    /// Shows set-aside marks again.
    func bringBack(_ ids: Set<Mark.ID>) { changeAside(ids, to: false) }

    private func changeAside(_ ids: Set<Mark.ID>, to aside: Bool) {
        for window in windows.values {
            for index in window.pins.indices where ids.contains(window.pins[index].mark.id) {
                window.pins[index].aside = aside
                guard window.pins[index].visible else { continue }
                window.overlay.marks.fade(window.pins[index].mark.id, to: window.pins[index].opacity,
                                          duration: aside ? Settings.shared.motionUI.liveInkHideFade : Settings.shared.motionUI.liveInkShowFade)
            }
        }
    }

    func preview(_ preview: LiveMarksLayer.Preview?) {
        for window in windows.values { window.overlay.marks.preview(preview) }
    }

    func show(markStyle: MarkStyle, textStyle: TextStyle, drawingOn: Set<Mark.ID>, pulsing: Set<Mark.ID>,
              finishing: [Mark.ID: LiveMarksLayer.Finish] = [:], overDark: Set<Mark.ID> = [], hands: [Mark.ID: InkHand] = [:]) {
        for window in windows.values {
            window.overlay.marks.show(window.pins.map(\.mark), markStyle: markStyle, textStyle: textStyle,
                                      drawingOn: drawingOn, pulsing: pulsing, finishing: finishing, overDark: overDark, hands: hands)
            place(window)
        }
    }

    var stateJSON: [[String: Any]] {
        windows.values.sorted { $0.id < $1.id }.map { window in
            [
                "id": Int(window.id),
                "app": window.app ?? NSNull(),
                "frame": [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height].map { Int($0.rounded()) },
                "onScreen": window.onScreen,
                "overlay": StateReport.topLeft(window.overlay.frame, primaryHeight: StateReport.primaryHeight),
                "reorders": window.reorders,
                "marks": window.pins.count,
            ]
        }
    }

    /// Draws the marks of `all` that are not `lit` faint, as an answer's action points at its own
    /// findings, and the rest at full strength. A hidden mark takes its strength when it shows again.
    func light(_ lit: Set<Mark.ID>, among all: Set<Mark.ID>) {
        for window in windows.values {
            for index in window.pins.indices where all.contains(window.pins[index].mark.id) {
                let strength: Float = lit.contains(window.pins[index].mark.id) ? 1 : Self.unlitOpacity
                window.pins[index].strength = strength
                guard window.pins[index].visible else { continue }
                window.overlay.marks.fade(window.pins[index].mark.id, to: window.pins[index].opacity, duration: 0.18 * Settings.shared.motionScale)
            }
        }
    }

    private static let unlitOpacity: Float = 0.2

    /// The point that says which window a mark goes on: a loop's or a box's centre, an arrow's head,
    /// a note's tag.
    nonisolated static func point(of mark: Mark) -> CGPoint {
        switch mark.geometry {
        case .rectangle(let frame), .ellipse(let frame): CGPoint(x: frame.midX, y: frame.midY)
        case .arrow(let arrow): arrow.end
        case .text(let text): text.origin
        }
    }

    /// Whether `mark`, in points from its window's top-left, has its point inside a window of `size`.
    /// A popover, the person's note or a reply, may hang past the window's edge, so it always fits.
    nonisolated static func fits(_ mark: Mark, in size: CGSize) -> Bool {
        mark.popover != nil || CGRect(origin: .zero, size: size).contains(point(of: mark))
    }

    // MARK: Hiding with the window

    private func hide(_ window: Tracked, duration: CFTimeInterval) {
        for index in window.pins.indices where !window.pins[index].hidden {
            window.pins[index].hidden = true
            window.overlay.marks.fade(window.pins[index].mark.id, shown: false, duration: duration)
        }
    }

    /// Shows the window's hidden marks again once it is on the screen, not minimising, and has landed.
    private func showAgain(_ window: Tracked, now: CFTimeInterval) {
        guard window.onScreen, window.minimisingSince == nil, let from = window.showFrom, now >= from else { return }
        window.showFrom = nil
        for index in window.pins.indices where window.pins[index].hidden {
            window.pins[index].hidden = false
            guard window.pins[index].visible else { continue }
            window.overlay.marks.fade(window.pins[index].mark.id, to: window.pins[index].opacity, duration: Settings.shared.motionUI.liveInkShowFade)
        }
        Log.write("[live-ink] window=\(window.id) marks back")
    }

    /// After a resize, hides the marks whose point the window no longer covers and shows those it
    /// covers again.
    private func fitMarks(_ window: Tracked) {
        var changed = (hid: 0, back: 0)
        for index in window.pins.indices {
            let outside = !Self.fits(window.pins[index].mark, in: window.frame.size)
            guard outside != window.pins[index].outside else { continue }
            window.pins[index].outside = outside
            if outside { changed.hid += 1 } else { changed.back += 1 }
            guard !window.pins[index].hidden else { continue }
            window.overlay.marks.fade(window.pins[index].mark.id, to: outside ? 0 : window.pins[index].opacity,
                                      duration: outside ? Settings.shared.motionUI.liveInkHideFade : Settings.shared.motionUI.liveInkShowFade)
        }
        guard changed.hid + changed.back > 0 else { return }
        Log.write("[live-ink] window=\(window.id) resized: marks outside=\(changed.hid) back=\(changed.back)")
    }

    // MARK: Windows

    private func tracked(_ target: Target) -> Tracked {
        if let window = windows[target.id] { return window }
        let window = Tracked(id: target.id, pid: target.pid, app: target.app, frame: target.frame)
        window.overlay.alphaValue = pickerClear ? 0 : 1
        windows[target.id] = window
        watch(window)
        window.overlay.place(over: target.frame, extent: target.frame)
        window.overlay.order(.above, relativeTo: Int(target.id))
        return window
    }

    /// Clears every overlay while macOS's window picker is up (`LiveInk.watchForWindowPicker`).
    var pickerClear = false {
        didSet { windows.values.forEach { $0.overlay.alphaValue = pickerClear ? 0 : 1 } }
    }

    /// The overlay covers the window and every mark that reaches past its edge.
    private func fitOverlay(_ window: Tracked) {
        var extent = window.frame
        for pin in window.pins {
            guard let drawn = drawnExtent?(pin.mark) else { continue }
            extent = extent.union(drawn.offsetBy(dx: window.frame.minX, dy: window.frame.minY))
        }
        // Nothing past the window's screen shows, so the overlay stops there.
        let centre = CGPoint(x: window.frame.midX, y: window.frame.midY)
        if let screen = StateReport.screenFrames.first(where: { $0.contains(centre) }) {
            extent = extent.intersection(screen.union(window.frame))
        }
        window.overlay.place(over: window.frame, extent: extent)
    }

    /// A mark first drawn while its window is away, or past its edge, starts hidden.
    private func place(_ window: Tracked) {
        for pin in window.pins where !pin.visible && window.overlay.marks.isShown(pin.mark.id) {
            window.overlay.marks.fade(pin.mark.id, shown: false, duration: 0)
        }
    }

    private func dropEmpty() {
        for (id, window) in windows where window.pins.isEmpty {
            retire(window.overlay)
            windows[id] = nil
        }
        for window in windows.values { fitOverlay(window) }
        if windows.isEmpty { stop() }
    }

    // MARK: The tick

    private func start() {
        guard link == nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
        activeUntil = CACurrentMediaTime() + 1
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .keyDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.input(event) }
            },
        ].compactMap { $0 }
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            (workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { self?.activated(pid) }
            }),
        ]
    }

    private func stop() {
        link?.invalidate()
        link = nil
        for observer in watchers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        watchers = [:]
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
    }

    /// Asks the window's app to say when the window moves or changes size. The notifications arrive
    /// on the main run loop; registering waits on the app, so it runs on the window's queue.
    private func watch(_ window: Tracked) {
        let pid = window.pid, id = window.id
        let observer: AXObserver
        if let existing = watchers[pid] {
            observer = existing
        } else {
            var created: AXObserver?
            let callback: AXObserverCallback = { _, _, _, refcon in
                guard let refcon else { return }
                let owner = Unmanaged<LiveWindows>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated { owner.activeUntil = max(owner.activeUntil, CACurrentMediaTime() + 0.6) }
            }
            guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
            watchers[pid] = created
            observer = created
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        nonisolated(unsafe) let box = observer
        window.queue.async {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.25)
            let elements = (WindowAccessibility.attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
            guard let element = elements.first(where: { WindowAccessibility.windowID($0) == id }) else { return }
            for name in [kAXMovedNotification, kAXResizedNotification] {
                AXObserverAddNotification(box, element, name as CFString, refcon)
            }
        }
    }

    private func input(_ event: NSEvent) {
        let now = CACurrentMediaTime()
        switch event.type {
        case .leftMouseDown: buttonDown = true
        case .leftMouseUp:
            buttonDown = false
            minimiseButtonReleased()
        case .keyDown:
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function, .numericPad])
            if event.keyCode == 46, modifiers == .command { minimising(NSWorkspace.shared.frontmostApplication?.processIdentifier) }
        default: break
        }
        activeUntil = max(activeUntil, now + 0.6)
    }

    /// The window's app is about to raise its windows over their overlays: they float until it has,
    /// so the marks are not missing for a frame.
    private func activated(_ pid: pid_t?) {
        activeUntil = CACurrentMediaTime() + 1
        for window in windows.values where window.pid == pid && window.onScreen {
            window.overlay.level = .floating
            window.liftedAt = CACurrentMediaTime()
        }
    }

    /// ⌘M: the frontmost app's front window goes to the Dock, and its marks fade at once rather than
    /// trail the genie.
    private func minimising(_ pid: pid_t?) {
        guard let pid else { return }
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        // Its frontmost window, passing over the small window macOS 15 puts over a titled window's title bar.
        guard let front = infos.first(where: {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
                && (WindowList.bounds($0).map { $0.width > 60 && $0.height > 60 } ?? false)
        }),
              let id = front[kCGWindowNumber as String] as? CGWindowID, let window = windows[id] else { return }
        fadeForMinimise(window)
    }

    /// A release on a window's minimise button, which Accessibility names.
    private func minimiseButtonReleased() {
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: StateReport.primaryHeight - mouse.y)
        guard let window = windows.values.first(where: { $0.onScreen && $0.frame.contains(point) && point.y - $0.frame.minY < 60 }) else { return }
        let pid = window.pid, id = window.id
        window.queue.async { [weak self] in
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.25)
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success, let element = hit,
                  WindowAccessibility.attribute(element, kAXSubroleAttribute) as? String == kAXMinimizeButtonSubrole as String else { return }
            let owner = self
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self = owner, let window = self.windows[id] else { return }
                    self.fadeForMinimise(window)
                }
            }
        }
    }

    private func fadeForMinimise(_ window: Tracked) {
        window.minimisingSince = CACurrentMediaTime()
        hide(window, duration: Settings.shared.motionUI.liveInkHideFade)
        Log.write("[live-ink] window=\(window.id) minimising")
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        // Marks waiting for their window to land are let back as soon as it has.
        if windows.values.contains(where: { $0.showFrom != nil || $0.minimisingSince != nil }) { activeUntil = max(activeUntil, now + 0.1) }
        let active = buttonDown || now < activeUntil
        // At rest the windows are looked at ten times a second, which still catches one moved by a
        // script or another app.
        guard active || now - lastIdleTick >= 0.1 else { return }
        lastIdleTick = now
        link.preferredFrameRateRange = active ? .default : CAFrameRateRange(minimum: 8, maximum: 15, preferred: 10)
        let infos = WindowList.describe(Array(windows.keys))
        var seen = Set<CGWindowID>()
        for info in infos {
            guard let id = info[kCGWindowNumber as String] as? CGWindowID, let window = windows[id] else { continue }
            seen.insert(id)
            update(window, info: info, now: now)
        }
        var gone = Set<Mark.ID>()
        for (id, window) in windows where !seen.contains(id) {
            gone.formUnion(window.pins.map(\.mark.id))
            window.overlay.close()
            windows[id] = nil
            Log.write("[live-ink] window=\(id) closed marks=\(window.pins.count)")
        }
        if !gone.isEmpty { onGone?(gone) }
        if windows.isEmpty { stop() }
    }

    private func update(_ window: Tracked, info: [String: Any], now: CFTimeInterval) {
        let onScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
        if onScreen != window.onScreen {
            window.onScreen = onScreen
            if onScreen {
                // Back from the Dock, another Space or a hidden app: the marks come back once the
                // window has landed.
                window.overlay.level = .normal
                window.overlay.order(.above, relativeTo: Int(window.id))
                window.minimisingSince = nil
                window.showFrom = now + Self.landing
                hide(window, duration: 0)
                activeUntil = max(activeUntil, now + 0.6)
            } else {
                window.overlay.orderOut(nil)
            }
            Log.write("[live-ink] window=\(window.id) \(onScreen ? "back" : "away")")
        }
        guard onScreen, let frame = WindowList.bounds(info) else { return }
        if frame != window.frame {
            let resized = frame.size != window.frame.size
            window.frame = frame
            if resized {
                activeUntil = max(activeUntil, now + 0.6)
                fitMarks(window)
                fitOverlay(window)
            } else {
                window.overlay.move(over: frame)
            }
        }
        keepInPlace(window, now: now)
        if let since = window.minimisingSince, now - since > 1 {
            // Still on screen a second after ⌘M: the app did not minimise it.
            window.minimisingSince = nil
            window.showFrom = now
        }
        showAgain(window, now: now)
    }

    /// Orders the overlay back above its window when another app's window, or the window's own app
    /// raising it, came between them. Only the window's own app's windows may sit between the two:
    /// a titled window has a small window of its own over its title bar, and a sheet is a window too.
    private func keepInPlace(_ window: Tracked, now: CFTimeInterval) {
        let above = WindowList.ids(above: window.id)
        let mine = CGWindowID(window.overlay.windowNumber)
        if let lifted = window.liftedAt {
            let covered = WindowList.describe(above.filter { $0 != mine }).contains {
                ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowOwnerPID as String] as? pid_t) != window.pid
            }
            guard !covered || now - lifted > 0.5 else { return }
            window.overlay.level = .normal
            window.overlay.order(.above, relativeTo: Int(window.id))
            window.liftedAt = nil
            return
        }
        var inPlace = false
        if let index = above.lastIndex(of: mine) {
            let between = Array(above[(index + 1)...])
            inPlace = between.isEmpty || WindowList.describe(between).allSatisfy { ($0[kCGWindowOwnerPID as String] as? pid_t) == window.pid }
        }
        guard !inPlace else { return }
        window.overlay.order(.above, relativeTo: Int(window.id))
        window.reorders += 1
    }

    static func translated(_ mark: Mark, by offset: CGVector) -> Mark {
        var moved = mark
        switch mark.geometry {
        case .rectangle(let frame): moved.geometry = .rectangle(frame.offsetBy(dx: offset.dx, dy: offset.dy))
        case .ellipse(let frame): moved.geometry = .ellipse(frame.offsetBy(dx: offset.dx, dy: offset.dy))
        case .arrow(var arrow):
            arrow.start = arrow.start.moved(by: offset)
            arrow.end = arrow.end.moved(by: offset)
            arrow.via = arrow.via.map { $0.moved(by: offset) }
            moved.geometry = .arrow(arrow)
        case .text(var text):
            text.origin = text.origin.moved(by: offset)
            moved.geometry = .text(text)
            moved.popover = mark.popover?.offsetBy(dx: offset.dx, dy: offset.dy)
        }
        moved.focus = mark.focus?.moved(by: offset)
        return moved
    }
}

/// The Accessibility calls live ink makes on a marked window's app. Each blocks on that app, so none
/// runs on the main thread.
enum WindowAccessibility {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    /// `_AXUIElementGetWindow`, which every window manager uses to match an element to the window
    /// list. Private, so looked up rather than linked.
    private static let getWindow: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    }()

    static func windowID(_ window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let getWindow, getWindow(window, &id) == .success else { return nil }
        return id
    }

    /// An Electron app builds its page's tree only when asked, and keeps it until it quits, at a cost
    /// in memory and CPU. The note's URL and the page an answer keeps to come from that tree, so the
    /// app is asked when a mark lands at `point`, in global top-left points, where it has no page yet.
    /// No other app is.
    static func requestTree(pid: pid_t, at point: CGPoint) {
        guard AXIsProcessTrusted(), let bundle = NSRunningApplication(processIdentifier: pid)?.bundleURL,
              FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path) else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) != .success { hit = nil }
        if let hit {
            AXUIElementSetMessagingTimeout(hit, 0.25)
            guard !isInWebArea(hit) else { return }
        }
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        Log.write("[live-ink] accessibility tree requested app=\(bundle.deletingPathExtension().lastPathComponent)")
    }

    private static func isInWebArea(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<40 {
            guard let element = current else { return false }
            if attribute(element, kAXRoleAttribute) as? String == "AXWebArea" { return true }
            current = attribute(element, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        return false
    }
}

/// The window list, read the cheap way: a description of the listed windows only, and the ids of the
/// windows above one, which `CGWindowListCreate` gives without describing them.
enum WindowList {
    private typealias Create = @convention(c) (UInt32, UInt32) -> Unmanaged<CFArray>?
    /// Swift marks `CGWindowListCreate` unavailable, so it is looked up.
    private static let create: Create? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreate")
        .map { unsafeBitCast($0, to: Create.self) }

    /// The windows above `id`, front to back, as the window server lists them.
    static func ids(above id: CGWindowID) -> [CGWindowID] {
        guard let array = create?(CGWindowListOption.optionOnScreenAboveWindow.rawValue, id)?.takeRetainedValue() else { return [] }
        return (0..<CFArrayGetCount(array)).map { CGWindowID(UInt(bitPattern: CFArrayGetValueAtIndex(array, $0))) }
    }

    /// The window list's entries for `ids`. The array holds the ids themselves, not numbers.
    static func describe(_ ids: [CGWindowID]) -> [[String: Any]] {
        guard !ids.isEmpty else { return [] }
        var values = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let array = CFArrayCreate(nil, &values, values.count, nil) else { return [] }
        return CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] ?? []
    }

    static func bounds(_ info: [String: Any]) -> CGRect? {
        (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
    }
}

/// The overlay of one window with marks: clear, borderless, at the normal level, ordered just above
/// its window, never taking a press, and left out of captures as the screen's overlay is.
@MainActor
final class WindowOverlay: NSPanel {
    let marks: LiveMarksLayer
    private let content: FlippedView
    /// The window's top-left in the overlay, where the marks' coordinates start.
    private var windowOffset = CGVector.zero

    init(target: CGWindowID) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        marks = LiveMarksLayer(scale: scale)
        content = FlippedView(frame: .zero)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .normal
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        sharingType = LiveInkOverlay.sharedWithCaptures ? .readOnly : .none
        content.wantsLayer = true
        contentView = content
        content.layer?.addSublayer(marks)
        marks.host = content
        marks.sharing = sharingType
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The marks are laid out from the frame `place` asks for, so the overlay takes it as asked. AppKit
    /// would move a frame that reaches above the menu bar down below it, and the marks with it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Covers `extent`, in global top-left points, with the marks' coordinates starting at the
    /// window's top-left, `window`.
    func place(over window: CGRect, extent: CGRect) {
        let scale = screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        if marks.contentsScale != scale { marks.contentsScale = scale }
        windowOffset = CGVector(dx: window.minX - extent.minX, dy: window.minY - extent.minY)
        setFrame(StateReport.fromTopLeft(extent, primaryHeight: StateReport.primaryHeight), display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        marks.position = CGPoint(x: windowOffset.dx, y: windowOffset.dy)
        CATransaction.commit()
    }

    /// Moves with the window, keeping its size and the marks where they are in it.
    func move(over window: CGRect) {
        let origin = CGPoint(x: window.minX - windowOffset.dx, y: window.minY - windowOffset.dy)
        let appKit = StateReport.fromTopLeft(CGRect(origin: origin, size: frame.size), primaryHeight: StateReport.primaryHeight)
        setFrameOrigin(appKit.origin)
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}
