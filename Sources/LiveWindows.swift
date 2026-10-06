import AppKit
import QuartzCore

/// The windows that have live ink marks, and the marks on them (docs/live-ink-step3-2026-10-05.md).
/// A mark belongs to the window it was drawn on. Each such window has an overlay window of its own,
/// ordered just above it, so windows in front cover its marks. The marks move with their window on
/// every display frame. While the window's content scrolls or the window is resized, they fade out,
/// and once the content has been still for a moment they come back on the content they point at,
/// found again through their anchors. A mark whose content cannot be found stays hidden.
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
    /// The window last found under the pointer for a scroll, and when, so a gesture's events do not
    /// each list the windows.
    private var scrollTarget: (point: CGPoint, id: CGWindowID?, at: CFTimeInterval)?

    /// How long the content must be still before marks come back: the scroll, the window's size, and
    /// every anchor. Not motion: the motion setting leaves them as they are.
    static let scrollQuiet: CFTimeInterval = 0.15
    static let resizeQuiet: CFTimeInterval = 0.2
    static let anchorQuiet: CFTimeInterval = 0.1
    /// The same for a window whose app reports positions late, as Chromium does while it finishes a
    /// smooth scroll after the trackpad has stopped: a mark shown at the last position it reported
    /// would hide and come back again a moment later.
    static let lateScrollQuiet: CFTimeInterval = 0.3
    static let lateAnchorQuiet: CFTimeInterval = 0.25
    /// A scroll this far without an anchor moving means the app has not reported the new positions
    /// yet, as Chromium does only once a scroll is over; the marks wait for them this long.
    static let staleScroll: CGFloat = 24
    static let staleWait: CFTimeInterval = 0.6
    /// How often anchors are read while their window is on screen.
    static let pollInterval: CFTimeInterval = 0.05

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
        var lastResize: CFTimeInterval = 0
        /// Nothing comes back before this: a window back from the Dock or another Space is let land.
        var settleFrom: CFTimeInterval = 0
        /// Floated over normal windows while its app raises its windows over the overlay.
        var liftedAt: CFTimeInterval?
        /// Faded because the person asked to minimise it.
        var minimisingSince: CFTimeInterval?
        /// Accessibility calls for this window wait on its app, one at a time.
        let queue: DispatchQueue
        var polling = false
        var lastPoll: CFTimeInterval = 0
        var capturing = false
        var reorders = 0
        /// Its app has reported a position late: its marks wait longer before they come back.
        var late = false
        /// After a key or a click that may have scrolled the window with no scroll event, when to look
        /// at the marks found by their pixels next, and until when to keep looking.
        var checkAt: CFTimeInterval?
        var checkUntil: CFTimeInterval = 0
        var lastRelocate: CFTimeInterval = 0

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
        /// In points from the window's top-left when it was pinned.
        var mark: Mark
        var anchor: Anchoring
        /// How far the content under it has moved since it was pinned.
        var shift = CGVector.zero
        /// The trackpad's scroll since the mark started fading, which it rides along with as it goes.
        var ride = CGVector.zero
        var phase: Phase = .shown
        /// When the content under it last moved: a scroll over it, or its anchor's reading changing.
        var lastScroll: CFTimeInterval = 0
        /// When its anchor stopped being readable while it glides, as a page does while it reloads.
        var unreadSince: CFTimeInterval?
        var lastChange: CFTimeInterval = 0
        /// The trackpad's scroll since it hid, and whether its anchor has moved since then.
        var scrolledSinceHide = CGVector.zero
        var changedSinceHide = false
        var hiddenAt: CFTimeInterval = 0
        /// The window's size when it last showed, which a mark with no anchor needs to show again.
        var windowSize: CGSize
        /// The newest reading, and the start of the poll that took it.
        var reading: LiveAnchor.Reading?
        var readAt: CFTimeInterval = 0
        var shownAt: CFTimeInterval = 0
        /// Drawn inside its scroll area, so it is cut off at the area's edge as the content is.
        var clipped = false
        /// For an element's anchor, the pixels round the mark, which decide where it shows: Chromium
        /// moves an element's position late, and only to the nearest run of text.
        var patch: LivePatch?
        let pinnedAt: CFTimeInterval
        /// Hidden because a look at the window's pixels found its content moving, and where the last
        /// look found it: it comes back once two looks agree.
        var checking = false
        var seen: (shift: CGVector?, at: CFTimeInterval)?
        /// Where the last look by its pixels found a gliding mark whose anchor went unread
        /// (`relocate`): it glides there once the next look agrees.
        var relocated: CGVector?

        enum Phase: String { case shown, moving, lost }
    }

    private enum Anchoring {
        /// Being found.
        case pending
        case accessibility(LiveAnchor)
        case pixels(LivePatch)
        /// Moves as another mark does, from the shift that mark had when this one was pinned.
        case follows(Mark.ID, base: CGVector)
        /// Nothing to find it by: it stays with the window, and hides for good once the content moves.
        case window

        var name: String {
            switch self {
            case .pending: "pending"
            case .accessibility(let anchor): anchor.name
            case .pixels: "pixels"
            case .follows: "follows"
            case .window: "window"
            }
        }
    }

    /// How a new mark is anchored.
    enum Anchor {
        /// To the content at this point, in global top-left points.
        case at(CGPoint)
        /// To another mark on the same window, as an answer's note follows the ink it answers.
        case follows(Mark.ID)
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

    /// Puts `mark`, in global top-left points, on `target`, anchored as `anchor` says.
    func pin(_ mark: Mark, to target: Target, anchor: Anchor) {
        let window = tracked(target)
        let origin = window.frame.origin
        var pin = Pin(mark: Self.translated(mark, by: CGVector(dx: -origin.x, dy: -origin.y)), anchor: .pending,
                      windowSize: window.frame.size, pinnedAt: CACurrentMediaTime())
        switch anchor {
        case .follows(let id):
            if let leader = window.pins.first(where: { $0.mark.id == id }) {
                pin.anchor = .follows(id, base: leader.shift)
                pin.phase = leader.phase
            } else {
                pin.anchor = .window
            }
            window.pins.append(pin)
        case .at(let point):
            window.pins.append(pin)
            find(anchorAt: point, for: mark.id, in: window)
        }
        window.pins.removeAll { $0.mark.id == mark.id && $0.pinnedAt != pin.pinnedAt }
        fitOverlay(window)
        place(window)
        start()
    }

    /// Takes these marks off their windows.
    func remove(_ ids: Set<Mark.ID>) {
        guard !ids.isEmpty else { return }
        for window in windows.values {
            window.pins.removeAll { ids.contains($0.mark.id) }
            for index in window.pins.indices {
                if case .follows(let leader, _) = window.pins[index].anchor, ids.contains(leader) { window.pins[index].anchor = .window }
            }
        }
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
                let offset = CGVector(dx: window.frame.minX + pin.shift.dx, dy: window.frame.minY + pin.shift.dy)
                return (Self.translated(pin.mark, by: offset), pin.phase == .shown && window.onScreen, window.id)
            }
        }
    }

    /// The window a mark is on.
    func window(of id: Mark.ID) -> CGWindowID? {
        windows.values.first { $0.pins.contains { $0.mark.id == id } }?.id
    }

    /// How far the content under a mark had moved since it was pinned, when it last showed; nil for a
    /// mark not on a window.
    func shift(of id: Mark.ID) -> CGVector? {
        windows.values.lazy.compactMap { $0.pins.first { $0.mark.id == id }?.shift }.first
    }

    func isShown(_ id: Mark.ID) -> Bool {
        windows.values.contains { window in window.onScreen && window.pins.contains { $0.mark.id == id && $0.phase == .shown } }
    }

    func preview(_ preview: LiveMarksLayer.Preview?) {
        for window in windows.values { window.overlay.marks.preview(preview) }
    }

    func show(markStyle: MarkStyle, textStyle: TextStyle, drawingOn: Set<Mark.ID>, pulsing: Set<Mark.ID>,
              finishing: [Mark.ID: LiveMarksLayer.Finish] = [:]) {
        // A mark playing its done animation keeps gliding, so a late move does not fade it mid-way.
        gliding = pulsing.union(finishing.keys)
        for window in windows.values {
            window.overlay.marks.show(window.pins.map(\.mark), markStyle: markStyle, textStyle: textStyle,
                                      drawingOn: drawingOn, pulsing: pulsing, finishing: finishing)
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
                "pins": window.pins.map { pin -> [String: Any] in
                    ["anchor": pin.anchor.name, "phase": pin.phase.rawValue, "shift": [pin.shift.dx, pin.shift.dy].map { Int($0.rounded()) },
                     "clip": pin.clipped ? pin.reading?.clip.map { [$0.minX, $0.minY, $0.width, $0.height].map { Int($0.rounded()) } } ?? NSNull() : NSNull(),
                     "pixels": pin.patch != nil]
                },
            ]
        }
    }

    // MARK: Anchors

    /// Finds the anchor for the content at `point` off the main thread. Accessibility first; when it
    /// gives nothing, a patch of the window's pixels. A scroll or a resize before the answer means the
    /// point no longer shows what the mark was drawn on, so the mark then keeps to the window.
    private func find(anchorAt point: CGPoint, for id: Mark.ID, in window: Tracked) {
        let windowID = window.id, pid = window.pid, origin = window.frame.origin
        let asked = CACurrentMediaTime()
        window.queue.async { [weak self] in
            let anchor = LiveAnchor.find(at: point, pid: pid, windowID: windowID, windowOrigin: origin)
            let reading = anchor?.read(windowOrigin: origin)
            let owner = self
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self = owner, let window = self.windows[windowID], let index = window.pins.firstIndex(where: { $0.mark.id == id }) else { return }
                    guard !self.moved(window, since: asked, pin: window.pins[index]) else {
                        window.pins[index].anchor = .window
                        Log.write("[live-ink] anchor window=\(windowID) kind=window reason=moved-while-finding")
                        return
                    }
                    if let anchor {
                        window.pins[index].anchor = .accessibility(anchor)
                        window.pins[index].reading = reading
                        window.pins[index].readAt = asked
                        if let clip = reading?.clip, let drawn = self.drawnExtent?(window.pins[index].mark) {
                            window.pins[index].clipped = clip.insetBy(dx: -4, dy: -4).contains(drawn)
                        }
                        // Chromium gives a run of text as an element, and moves it late.
                        if case .element = anchor.kind {
                            window.late = true
                            self.findPatch(at: point, for: id, in: window, beside: anchor)
                        }
                        Log.write("[live-ink] anchor window=\(windowID) app=\(window.app ?? "?") kind=\(anchor.name) clip=\(anchor.scrollArea != nil)")
                    } else {
                        self.findPatch(at: point, for: id, in: window)
                    }
                }
            }
        }
    }

    /// The pixels round the mark, as its anchor or, `beside` an element's anchor, as what decides
    /// where it shows.
    private func findPatch(at point: CGPoint, for id: Mark.ID, in window: Tracked, beside anchor: LiveAnchor? = nil) {
        let windowID = window.id
        let local = CGPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
        let size = window.frame.size
        let asked = CACurrentMediaTime()
        Task { [weak self] in
            let image = await WindowImage.capture(windowID, size: size)
            let patch = await Task.detached(priority: .userInitiated) { image.flatMap { LivePatch($0, around: local) } }.value
            guard let self, let window = self.windows[windowID], let index = window.pins.firstIndex(where: { $0.mark.id == id }) else { return }
            if anchor != nil {
                if !self.moved(window, since: asked, pin: window.pins[index]) { window.pins[index].patch = patch }
                return
            }
            if let patch, !self.moved(window, since: asked, pin: window.pins[index]) {
                window.pins[index].anchor = .pixels(patch)
                Log.write("[live-ink] anchor window=\(windowID) app=\(window.app ?? "?") kind=pixels")
            } else {
                window.pins[index].anchor = .window
                Log.write("[live-ink] anchor window=\(windowID) app=\(window.app ?? "?") kind=window reason=\(patch == nil ? "no-patch" : "moved-while-finding")")
            }
        }
    }

    /// The window's content moved after `time`, or it is moving now.
    private func moved(_ window: Tracked, since time: CFTimeInterval, pin: Pin) -> Bool {
        pin.phase != .shown || pin.lastScroll > time || window.lastResize > time || pin.lastChange > time
    }

    /// Reads every Accessibility anchor on `window` off the main thread.
    private func poll(_ window: Tracked) {
        let anchors = window.pins.compactMap { pin -> (Mark.ID, LiveAnchor)? in
            if case .accessibility(let anchor) = pin.anchor { return (pin.mark.id, anchor) }
            return nil
        }
        guard !anchors.isEmpty, !window.polling else { return }
        window.polling = true
        let started = CACurrentMediaTime()
        window.lastPoll = started
        let origin = window.frame.origin, id = window.id
        window.queue.async { [weak self] in
            let readings = anchors.map { ($0.0, $0.1.read(windowOrigin: origin)) }
            let owner = self
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self = owner, let window = self.windows[id] else { return }
                    window.polling = false
                    self.took(readings, started: started, in: window)
                }
            }
        }
    }

    /// A poll's readings: an anchor that moved under a mark that shows hides it until the content is
    /// still, and one that comes back under a lost mark brings it back the same way.
    private func took(_ readings: [(Mark.ID, LiveAnchor.Reading)], started: CFTimeInterval, in window: Tracked) {
        let now = CACurrentMediaTime()
        for (id, reading) in readings {
            guard let index = window.pins.firstIndex(where: { $0.mark.id == id }),
                  case .accessibility(let anchor) = window.pins[index].anchor else { continue }
            let before = window.pins[index].reading.flatMap { $0.shift(from: anchor.pinned, focus: anchor.focus) }
            let after = reading.shift(from: anchor.pinned, focus: anchor.focus)
            window.pins[index].reading = reading
            window.pins[index].readAt = started
            if after != nil { window.pins[index].unreadSince = nil }
            // While the session works the mark stays, so its turn ends with the mark on screen.
            if let since = window.pins[index].unreadSince, now - since > Self.unreadLimit, window.pins[index].phase == .shown,
               !gliding.contains(id) {
                window.pins[index].unreadSince = nil
                hide(index, in: window, because: "unread")
                continue
            }
            guard !Self.same(before, after) else { continue }
            window.pins[index].lastChange = now
            window.pins[index].changedSinceHide = true
            switch window.pins[index].phase {
            case .shown:
                // Moved with nothing on the trackpad: a key, a click or the page itself scrolled it.
                if let after, Self.same(after, window.pins[index].shift) { continue }
                // A scroll of the person's hid it already (`scrolled`), so this move is the page's own.
                if gliding.contains(id) {
                    if let after {
                        glide(index, in: window, to: after)
                    } else if window.pins[index].unreadSince == nil {
                        window.pins[index].unreadSince = now
                    }
                    continue
                }
                let pin = window.pins[index]
                if !window.late, now - pin.shownAt < 0.6, pin.lastScroll < pin.shownAt, pin.shownAt > pin.pinnedAt + 0.01 {
                    window.late = true
                    Log.write("[live-ink] window=\(window.id) app=\(window.app ?? "?") reports positions late")
                }
                hide(index, in: window, because: "anchor-moved")
            case .lost:
                window.pins[index].phase = .moving
                window.pins[index].hiddenAt = now
            case .moving:
                break
            }
        }
        if window.pins.contains(where: { $0.phase == .shown && $0.unreadSince != nil && $0.patch != nil }) { relocate(window) }
    }

    private static func same(_ a: CGVector?, _ b: CGVector?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): abs(a.dx - b.dx) < 0.75 && abs(a.dy - b.dy) < 0.75
        default: false
        }
    }

    // MARK: Motion

    /// Fades a mark out as its content starts to move. A scroll that starts it also moves it along
    /// with the content for the length of the fade (`scrolled`).
    private func hide(_ index: Int, in window: Tracked, because reason: String) {
        let now = CACurrentMediaTime()
        if window.pins[index].phase == .shown { Log.write("[live-ink] hide window=\(window.id) because=\(reason)") }
        window.pins[index].phase = .moving
        window.pins[index].hiddenAt = now
        window.pins[index].ride = .zero
        window.pins[index].scrolledSinceHide = .zero
        window.pins[index].changedSinceHide = false
        window.overlay.marks.fade(window.pins[index].mark.id, shown: false, duration: Settings.shared.motionUI.liveInkHideFade)
        syncFollowers(of: window.pins[index].mark.id, in: window)
    }

    /// The marks of an ask a session is working on. The session's edits are what moves their content
    /// then, and the person is watching for them, so these glide to where it went rather than fade
    /// out and back in.
    private var gliding = Set<Mark.ID>()
    private static let glideDuration: CFTimeInterval = 0.3
    /// How long a mark that stopped gliding stays where it is while its anchor cannot be read, before
    /// it hides.
    private static let unreadLimit: CFTimeInterval = 2

    /// How often `relocate` looks: often at first, as a page reloads, then seldom, as for content the
    /// session took off the page.
    private static let relocateInterval: CFTimeInterval = 0.15
    private static let relocateSlowly: CFTimeInterval = 1

    /// Looks for the gliding marks whose anchors went unread by their pixels, while they still show.
    /// A page that reloads makes new elements, so the old ones read nothing. Once two looks in a row
    /// agree, the mark glides there and takes the element now under it as its anchor.
    private func relocate(_ window: Tracked) {
        let now = CACurrentMediaTime()
        let since = window.pins.compactMap(\.unreadSince).min() ?? now
        let interval = now - since > Self.unreadLimit ? Self.relocateSlowly : Self.relocateInterval
        guard !window.capturing, now - window.lastRelocate >= interval else { return }
        window.capturing = true
        window.lastRelocate = now
        let id = window.id, size = window.frame.size
        let wanted = window.pins.compactMap { pin -> (Mark.ID, LivePatch, CGVector)? in
            guard pin.phase == .shown, pin.unreadSince != nil, let patch = pin.patch else { return nil }
            return (pin.mark.id, patch, pin.relocated ?? pin.shift)
        }
        Task { [weak self] in
            let image = await WindowImage.capture(id, size: size)
            let found = await Task.detached(priority: .userInitiated) {
                wanted.map { id, patch, expected in (id, image.flatMap { patch.shift(in: $0, expected: expected) }) }
            }.value
            guard let self, let window = self.windows[id] else { return }
            window.capturing = false
            for (markID, shift) in found {
                guard let index = window.pins.firstIndex(where: { $0.mark.id == markID }), window.pins[index].phase == .shown,
                      window.pins[index].unreadSince != nil, window.lastResize < now else { continue }
                let steady = shift != nil && Self.same(window.pins[index].relocated, shift)
                window.pins[index].relocated = shift
                guard steady, let shift else { continue }
                window.pins[index].relocated = nil
                window.pins[index].unreadSince = nil
                if !Self.same(shift, window.pins[index].shift) { self.glide(index, in: window, to: shift) }
                self.reanchor(index, in: window)
            }
        }
    }

    /// Anchors a mark that shows to the element now under it, as a mark pinned there would be, with
    /// its readings counted from where the mark was first pinned.
    private func reanchor(_ index: Int, in window: Tracked) {
        guard case .accessibility(let old) = window.pins[index].anchor else { return }
        let pin = window.pins[index]
        let local = old.focus ?? Self.anchorPoint(of: pin.mark)
        let point = CGPoint(x: window.frame.minX + local.x + pin.shift.dx, y: window.frame.minY + local.y + pin.shift.dy)
        let shift = pin.shift, markID = pin.mark.id, windowID = window.id, pid = window.pid, origin = window.frame.origin
        let asked = CACurrentMediaTime()
        window.queue.async { [weak self] in
            let anchor = LiveAnchor.find(at: point, pid: pid, windowID: windowID, windowOrigin: origin)?.rebased(by: shift)
            let reading = anchor?.read(windowOrigin: origin)
            let owner = self
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self = owner, let window = self.windows[windowID],
                          let index = window.pins.firstIndex(where: { $0.mark.id == markID }), let anchor else { return }
                    let pin = window.pins[index]
                    guard pin.phase == .shown, Self.same(pin.shift, shift), pin.lastScroll < asked, window.lastResize < asked else { return }
                    window.pins[index].anchor = .accessibility(anchor)
                    window.pins[index].reading = reading
                    window.pins[index].readAt = asked
                    Log.write("[live-ink] anchor window=\(windowID) kind=\(anchor.name) again")
                }
            }
        }
    }

    /// Moves a mark that shows, and the marks that follow it, to where its content is now.
    private func glide(_ index: Int, in window: Tracked, to shift: CGVector) {
        let id = window.pins[index].mark.id
        Log.write("[live-ink] glide window=\(window.id) shift=\(Int(shift.dx)),\(Int(shift.dy))")
        window.pins[index].shift = shift
        let duration = Self.glideDuration * Settings.shared.motionScale
        window.overlay.marks.move(id, by: shift, duration: duration)
        for follower in window.pins.indices {
            guard case .follows(let leader, let base) = window.pins[follower].anchor, leader == id, window.pins[follower].phase == .shown else { continue }
            let moved = CGVector(dx: shift.dx - base.dx, dy: shift.dy - base.dy)
            window.pins[follower].shift = moved
            window.overlay.marks.move(window.pins[follower].mark.id, by: moved, duration: duration)
        }
        fitOverlay(window)
    }

    /// Shows a mark where its content is now.
    private func reveal(_ index: Int, in window: Tracked, at shift: CGVector) {
        let pin = window.pins[index]
        if case .follows = pin.anchor {} else {
            let still = max(pin.lastScroll, pin.lastChange, window.lastResize, pin.hiddenAt)
            Log.write("[live-ink] back window=\(window.id) anchor=\(pin.anchor.name) shift=\(Int(shift.dx)),\(Int(shift.dy)) after=\(Int((CACurrentMediaTime() - still) * 1000))ms")
        }
        window.pins[index].shift = shift
        window.pins[index].ride = .zero
        window.pins[index].phase = .shown
        window.pins[index].shownAt = CACurrentMediaTime()
        window.pins[index].windowSize = window.frame.size
        window.overlay.marks.move(window.pins[index].mark.id, by: shift)
        window.overlay.marks.clip(window.pins[index].mark.id, to: pin.clipped ? pin.reading?.clip : nil)
        window.overlay.marks.fade(window.pins[index].mark.id, shown: true, duration: Settings.shared.motionUI.liveInkShowFade)
        syncFollowers(of: window.pins[index].mark.id, in: window)
        fitOverlay(window)
    }

    private func lose(_ index: Int, in window: Tracked) {
        guard window.pins[index].phase != .lost else { return }
        window.pins[index].phase = .lost
        window.overlay.marks.fade(window.pins[index].mark.id, shown: false, duration: Settings.shared.motionUI.liveInkHideFade)
        syncFollowers(of: window.pins[index].mark.id, in: window)
    }

    /// Marks that follow `leader` take its phase and its movement.
    private func syncFollowers(of leader: Mark.ID, in window: Tracked) {
        guard let lead = window.pins.first(where: { $0.mark.id == leader }) else { return }
        for index in window.pins.indices {
            guard case .follows(let id, let base) = window.pins[index].anchor, id == leader else { continue }
            let shift = CGVector(dx: lead.shift.dx - base.dx, dy: lead.shift.dy - base.dy)
            switch lead.phase {
            case .shown where window.pins[index].phase != .shown: reveal(index, in: window, at: shift)
            case .moving where window.pins[index].phase == .shown: hide(index, in: window, because: "leader")
            case .lost: lose(index, in: window)
            default: break
            }
        }
    }

    /// A scroll over a window with marks: the marks in the scroll area under the pointer fade out and
    /// ride along with the content as they go.
    private func scrolled(_ event: NSEvent) {
        // A finger resting on the trackpad, and the end of a gesture, carry no movement.
        guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return }
        let now = CACurrentMediaTime()
        activeUntil = now + 0.5
        let mouse = NSEvent.mouseLocation
        let point = event.cgEvent?.location ?? CGPoint(x: mouse.x, y: StateReport.primaryHeight - mouse.y)
        let id: CGWindowID?
        if let last = scrollTarget, last.point == point, now - last.at < 0.3 {
            id = last.id
        } else {
            id = Self.window(under: point)?.id
        }
        scrollTarget = (point, id, now)
        guard let id, let window = windows[id] else { return }
        let local = CGPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
        // A trackpad's deltas are in points and move the content 1:1; a wheel's are in lines.
        let delta = event.hasPreciseScrollingDeltas ? CGVector(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
            : CGVector(dx: event.scrollingDeltaX * 10, dy: event.scrollingDeltaY * 10)
        let fade = Settings.shared.motionUI.liveInkHideFade
        for index in window.pins.indices {
            switch window.pins[index].anchor {
            case .follows: continue
            // Outside every scroll area, as a toolbar is: its own readings say if it moves.
            case .accessibility where window.pins[index].reading?.clip == nil: continue
            default: break
            }
            if let clip = window.pins[index].reading?.clip, !clip.contains(local) { continue }
            window.pins[index].lastScroll = now
            window.pins[index].checking = false
            window.pins[index].scrolledSinceHide.dx += delta.dx
            window.pins[index].scrolledSinceHide.dy += delta.dy
            switch window.pins[index].phase {
            case .shown:
                hide(index, in: window, because: "scroll")
                window.pins[index].scrolledSinceHide = delta
            case .lost:
                window.pins[index].phase = .moving
                window.pins[index].hiddenAt = now
            case .moving:
                break
            }
            if now - window.pins[index].hiddenAt < fade {
                window.pins[index].ride.dx += delta.dx
                window.pins[index].ride.dy += delta.dy
            }
        }
        place(window)
    }

    /// Brings back the marks whose content has been still long enough, where their anchors say it is.
    private func settle(_ window: Tracked, now: CFTimeInterval) {
        guard window.onScreen, window.minimisingSince == nil, now >= window.settleFrom, now - window.lastResize >= Self.resizeQuiet else { return }
        var needsPixels = false
        for index in window.pins.indices where window.pins[index].phase == .moving {
            let pin = window.pins[index]
            guard now - pin.lastScroll >= (window.late ? Self.lateScrollQuiet : Self.scrollQuiet),
                  now - pin.lastChange >= (window.late ? Self.lateAnchorQuiet : Self.anchorQuiet) else { continue }
            let still = max(pin.lastScroll, pin.lastChange, window.lastResize, pin.hiddenAt)
            switch pin.anchor {
            case .accessibility(let anchor):
                // A reading from a poll that began once the content was still.
                guard pin.readAt > still, let reading = pin.reading else { continue }
                let scrolled = max(abs(pin.scrolledSinceHide.dx), abs(pin.scrolledSinceHide.dy))
                if scrolled > Self.staleScroll, !pin.changedSinceHide, now - still < Self.staleWait { continue }
                if pin.patch != nil { needsPixels = true; continue }
                if let shift = reading.shift(from: anchor.pinned, focus: anchor.focus), shows(pin.mark, shifted: shift, in: reading.clip) {
                    reveal(index, in: window, at: shift)
                } else {
                    lose(index, in: window)
                }
            case .pixels:
                if !pin.checking { needsPixels = true }
            case .window, .pending:
                // Without an anchor, a mark shows again only on a window of the same size whose content
                // was not scrolled: one that was moved, or came back from the Dock or another Space.
                if pin.lastScroll < pin.hiddenAt, window.frame.size == pin.windowSize {
                    reveal(index, in: window, at: pin.shift)
                } else {
                    lose(index, in: window)
                }
            case .follows:
                break
            }
        }
        if needsPixels { locatePatches(in: window) }
    }

    /// One capture of the window, in which every mark anchored by its pixels looks for its patch.
    private func locatePatches(in window: Tracked) {
        guard !window.capturing else { return }
        window.capturing = true
        let id = window.id, size = window.frame.size
        let started = CACurrentMediaTime()
        let wanted = window.pins.compactMap { pin -> (Mark.ID, LivePatch, CGVector)? in
            guard pin.phase == .moving else { return nil }
            switch pin.anchor {
            case .pixels(let patch):
                return (pin.mark.id, patch, CGVector(dx: pin.shift.dx + pin.scrolledSinceHide.dx, dy: pin.shift.dy + pin.scrolledSinceHide.dy))
            case .accessibility(let anchor):
                // Where the element is said to be is a hint for where to look.
                guard let patch = pin.patch else { return nil }
                let said = pin.reading?.shift(from: anchor.pinned, focus: anchor.focus)
                return (pin.mark.id, patch, said ?? CGVector(dx: pin.shift.dx + pin.scrolledSinceHide.dx, dy: pin.shift.dy + pin.scrolledSinceHide.dy))
            default:
                return nil
            }
        }
        Task { [weak self] in
            let image = await WindowImage.capture(id, size: size)
            let captured = CACurrentMediaTime()
            let found = await Task.detached(priority: .userInitiated) {
                wanted.map { id, patch, expected in (id, image.flatMap { patch.shift(in: $0, expected: expected) }) }
            }.value
            guard let self, let window = self.windows[id] else { return }
            window.capturing = false
            let ms = "\(Int((captured - started) * 1000))+\(Int((CACurrentMediaTime() - captured) * 1000))"
            for (markID, shift) in found {
                // Moved again while the capture ran: the next settle looks again.
                guard let index = window.pins.firstIndex(where: { $0.mark.id == markID }), window.pins[index].phase == .moving,
                      window.pins[index].lastScroll < started, window.lastResize < started else { continue }
                let pin = window.pins[index]
                if let shift, self.shows(pin.mark, shifted: shift, in: pin.clipped ? pin.reading?.clip : nil) {
                    self.reveal(index, in: window, at: shift)
                } else {
                    self.lose(index, in: window)
                }
            }
            Log.write("[live-ink] pixels window=\(id) ms=\(ms) found=\(found.filter { $0.1 != nil }.count) of \(found.count)")
        }
    }

    /// Whether a mark moved by `shift` still has its anchor point inside its scroll area.
    private func shows(_ mark: Mark, shifted shift: CGVector, in clip: CGRect?) -> Bool {
        guard let clip else { return true }
        let point = Self.anchorPoint(of: mark)
        return clip.insetBy(dx: -2, dy: -2).contains(CGPoint(x: point.x + shift.dx, y: point.y + shift.dy))
    }

    /// Where a mark is anchored: a loop or a box at its centre, an arrow at its head, a note at the
    /// middle of its tag.
    static func anchorPoint(of mark: Mark) -> CGPoint {
        switch mark.geometry {
        case .rectangle(let frame), .ellipse(let frame): CGPoint(x: frame.midX, y: frame.midY)
        case .arrow(let arrow): arrow.end
        case .text(let text): text.origin
        }
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
            extent = extent.union(drawn.offsetBy(dx: window.frame.minX + pin.shift.dx, dy: window.frame.minY + pin.shift.dy))
        }
        // A mark far outside its window is not worth a window the size of the screen.
        extent = extent.intersection(window.frame.insetBy(dx: -240, dy: -240))
        window.overlay.place(over: window.frame, extent: extent)
    }

    /// Every mark at its shift, and the ride of those fading out.
    private func place(_ window: Tracked) {
        for pin in window.pins {
            window.overlay.marks.move(pin.mark.id, by: CGVector(dx: pin.shift.dx + pin.ride.dx, dy: pin.shift.dy + pin.ride.dy))
            // A mark first drawn while its content moves starts hidden.
            if pin.phase != .shown, window.overlay.marks.isShown(pin.mark.id) {
                window.overlay.marks.fade(pin.mark.id, shown: false, duration: 0)
            }
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
            NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated { self?.scrolled(event) }
            },
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
            let elements = (LiveAnchor.attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
            guard let element = elements.first(where: { LiveAnchor.windowID($0) == id }) else { return }
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
            mayHaveScrolled(NSWorkspace.shared.frontmostApplication?.processIdentifier)
        case .keyDown:
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function, .numericPad])
            if event.keyCode == 46, modifiers == .command { minimising(NSWorkspace.shared.frontmostApplication?.processIdentifier) }
            if Self.navigationKeys.contains(event.keyCode) { mayHaveScrolled(NSWorkspace.shared.frontmostApplication?.processIdentifier) }
        default: break
        }
        activeUntil = max(activeUntil, now + 0.6)
    }

    /// Space, the arrows, Page Up and Down, Home and End: the keys that scroll a page.
    private static let navigationKeys: Set<UInt16> = [49, 123, 124, 125, 126, 116, 121, 115, 119]

    /// A key or a click in `pid`'s app may have scrolled one of its windows with no scroll event. Marks
    /// found through Accessibility see that in their readings; those found by their pixels are looked
    /// for every `checkInterval` until the content has been still for `checkFor`.
    private func mayHaveScrolled(_ pid: pid_t?) {
        let now = CACurrentMediaTime()
        for window in windows.values where window.pid == pid && window.onScreen {
            guard window.pins.contains(where: { pin in
                if case .pixels = pin.anchor { return true }
                return false
            }) else { continue }
            if window.checkAt == nil { window.checkAt = now + Self.checkDelay }
            window.checkUntil = now + Self.checkFor
            activeUntil = max(activeUntil, window.checkUntil + 0.1)
        }
    }

    /// The first look comes a moment after the key, once the page has had a frame to start moving.
    private static let checkDelay: CFTimeInterval = 0.04
    private static let checkInterval: CFTimeInterval = 0.08
    private static let checkFor: CFTimeInterval = 0.6
    /// A mark whose content is still moving this long after it hid is let go.
    private static let checkGiveUp: CFTimeInterval = 2

    /// One look at the window for the marks found by their pixels. A mark that shows hides as soon as
    /// its content has moved; a hidden or lost one shows once two looks in a row find its content in
    /// the same place, and one whose content is gone is let go.
    private func check(_ window: Tracked) {
        guard !window.capturing else { window.checkAt = CACurrentMediaTime() + Self.checkInterval; return }
        window.capturing = true
        let id = window.id, size = window.frame.size
        let started = CACurrentMediaTime()
        let gliding = gliding
        let wanted = window.pins.compactMap { pin -> (Mark.ID, LivePatch, CGVector, Bool)? in
            guard case .pixels(let patch) = pin.anchor, pin.phase != .moving || pin.checking else { return nil }
            return (pin.mark.id, patch, pin.seen?.shift ?? pin.shift, pin.phase == .shown && !gliding.contains(pin.mark.id))
        }
        Task { [weak self] in
            let image = await WindowImage.capture(id, size: size)
            guard let image else {
                // A capture that failed says nothing about the content, so nothing changes.
                if let window = self?.windows[id] { window.capturing = false }
                return
            }
            // A mark that shows only needs to know whether its content is still under it, which one
            // comparison answers; the search waits for the next look, after it has hidden.
            let found = await Task.detached(priority: .userInitiated) {
                wanted.map { id, patch, expected, shown -> (Mark.ID, CGVector?) in
                    if patch.isAt(expected, in: image) { return (id, expected) }
                    return (id, shown ? nil : patch.shift(in: image, expected: expected))
                }
            }.value
            guard let self, let window = self.windows[id] else { return }
            window.capturing = false
            let now = CACurrentMediaTime()
            var watching = false
            for (markID, shift) in found {
                guard let index = window.pins.firstIndex(where: { $0.mark.id == markID }),
                      window.pins[index].lastScroll < started, window.lastResize < started else { continue }
                let pin = window.pins[index]
                let steady = pin.seen.map { Self.same($0.shift, shift) } ?? false
                window.pins[index].seen = (shift, now)
                switch pin.phase {
                case .shown:
                    guard !Self.same(shift, pin.shift) else { continue }
                    if let shift, gliding.contains(markID) {
                        self.glide(index, in: window, to: shift)
                        continue
                    }
                    Log.write("[live-ink] window=\(id) moved with no scroll")
                    self.hide(index, in: window, because: "pixels-moved")
                    window.pins[index].checking = true
                    window.pins[index].seen = nil
                    watching = true
                case .moving:
                    if !steady, now - pin.hiddenAt < Self.checkGiveUp {
                        watching = true
                    } else if let shift, self.shows(pin.mark, shifted: shift, in: nil) {
                        window.pins[index].checking = false
                        self.reveal(index, in: window, at: shift)
                    } else {
                        window.pins[index].checking = false
                        self.lose(index, in: window)
                    }
                case .lost:
                    guard let shift, steady, self.shows(pin.mark, shifted: shift, in: nil) else { continue }
                    self.reveal(index, in: window, at: shift)
                }
            }
            if watching || now < window.checkUntil {
                window.checkAt = max(started + Self.checkInterval, now)
                self.activeUntil = max(self.activeUntil, now + Self.checkInterval + 0.1)
            } else {
                for index in window.pins.indices { window.pins[index].seen = nil }
            }
        }
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
                  LiveAnchor.attribute(element, kAXSubroleAttribute) as? String == kAXMinimizeButtonSubrole as String else { return }
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
        for index in window.pins.indices where window.pins[index].phase == .shown {
            hide(index, in: window, because: "minimise")
        }
        Log.write("[live-ink] window=\(window.id) minimising")
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        // Marks waiting for their content to be still are let back as soon as it is.
        if windows.values.contains(where: { $0.pins.contains { $0.phase == .moving } }) { activeUntil = max(activeUntil, now + 0.1) }
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
                // window has settled, wherever their content is then.
                window.overlay.level = .normal
                window.overlay.order(.above, relativeTo: Int(window.id))
                window.minimisingSince = nil
                window.settleFrom = now + Self.resizeQuiet
                for index in window.pins.indices where window.pins[index].phase == .shown {
                    window.pins[index].phase = .moving
                    window.pins[index].hiddenAt = now
                    window.overlay.marks.fade(window.pins[index].mark.id, shown: false, duration: 0)
                }
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
                window.lastResize = now
                activeUntil = max(activeUntil, now + 0.6)
                for index in window.pins.indices where window.pins[index].phase == .shown { hide(index, in: window, because: "resize") }
                fitOverlay(window)
            } else {
                window.overlay.move(over: frame)
            }
        }
        keepInPlace(window, now: now)
        if let since = window.minimisingSince, now - since > 1 {
            // Still on screen a second after ⌘M: the app did not minimise it.
            window.minimisingSince = nil
        }
        if now - window.lastPoll >= Self.pollInterval { poll(window) }
        if let at = window.checkAt, now >= at {
            window.checkAt = nil
            check(window)
        }
        settle(window, now: now)
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
        }
        return moved
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
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

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
