import AppKit

/// Live ink: drawing straight on the screen, over any app, while Control and Option are held
/// (docs/live-ink-integration-2026-10-04.md). A loop becomes an ellipse and any other stroke an
/// arrow, in the person's colour, and a tap on a mark erases it. The marks stay where they were drawn,
/// on the Space they were drawn on, until they are erased or cleared, live ink is turned off, or
/// Vignette quits. Nothing is sent to an agent yet.
@MainActor
final class LiveInk {
    /// The chord is held and the active Space's surfaces take presses.
    private(set) var isInking = false
    /// One per screen per Space that has marks, and the active Space's while inking.
    private var surfaces: [Surface] = []
    /// The surfaces taking presses: the active Space's when the chord went down.
    private var inking: [Surface] = []
    private var chord: ModifierChord?
    private var observers: [(NotificationCenter, Any)] = []
    private var glowTimer: Timer?
    private var glowing = false
    /// Runs while a stroke outlives the chord, until the button is up: inking ends then.
    private var releaseWatch: Timer?
    /// Runs after ⌘⇧ while there are marks, looking for macOS's window picker.
    private var pickerWatch: Timer?
    private var pickerWatchUntil = Date.distantPast
    /// macOS's window picker is up, and the overlays are clear for it.
    private var pickerUp = false
    /// Asked when the chord goes down: false while the stack or the annotator holds the screen, which
    /// the raised overlays would cover and take presses from.
    private let mayInk: () -> Bool

    /// One screen on one Space: the overlay there and the marks on it, in global top-left points at
    /// 1 px per pt, the newest last. A mark that crosses onto another screen of the same Space is on
    /// that screen's surface too, under the same id.
    @MainActor
    private final class Surface {
        let overlay: LiveInkOverlay
        var marks: [Mark] = []

        init(_ overlay: LiveInkOverlay) { self.overlay = overlay }
    }

    var isOn: Bool { chord != nil }

    /// Every mark, on every Space, once each.
    var marks: [Mark] {
        var seen = Set<Mark.ID>()
        return surfaces.flatMap(\.marks).filter { seen.insert($0.id).inserted }
    }

    init(mayInk: @escaping () -> Bool) {
        self.mayInk = mayInk
    }

    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            chord = ModifierChord([.control, .option], tag: "live-ink", name: "the chord") { [weak self] change in
                self?.chordChanged(change)
            }
            let workspace = NSWorkspace.shared.notificationCenter
            observers = [
                (NotificationCenter.default, NotificationCenter.default.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.screensChanged() }
                }),
                (workspace, workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.spaceChanged() }
                }),
            ]
        } else {
            if isInking { stopInking() }
            stopWatchingForWindowPicker()
            chord = nil
            for (center, observer) in observers { center.removeObserver(observer) }
            observers = []
            surfaces.forEach { $0.overlay.close() }
            surfaces = []
        }
        Log.write("[live-ink] \(on ? "on" : "off")")
    }

    /// What a stroke did, as `[live-ink]` lines and `live-ink-stroke` answer it.
    enum Outcome {
        case drew(MarkKind)
        case erased(MarkKind)
        /// A tap on no mark.
        case missed
        /// A stroke that is no mark and no tap.
        case nothing

        var description: String {
            switch self {
            case .drew(let kind): "drew \(kind.rawValue)"
            case .erased(let kind): "erased \(kind.rawValue)"
            case .missed: "tap on no mark"
            case .nothing: "nothing"
            }
        }
    }

    /// Reads `points`, in global top-left points, as a stroke drawn on the active Space, as the debug
    /// command does, whether the stack or the annotator is up or not.
    @discardableResult
    func take(_ points: [CGPoint]) -> Outcome {
        let active = activeSurfaces()
        let start = points.first.flatMap { point in active.first { $0.overlay.globalFrame.contains(point) } }
        let outcome = take(points, on: start ?? active.first, among: active)
        closeEmpty(fade: 0)
        return outcome
    }

    /// Erases every mark, and says how many there were.
    @discardableResult
    func clear() -> Int {
        let count = marks.count
        for surface in surfaces { surface.marks = [] }
        showMarks()
        closeEmpty(fade: 0)
        Log.write("[live-ink] cleared \(count)")
        return count
    }

    /// The stack or the annotator is coming up under the raised overlays: inking stops, the stroke
    /// under way is dropped, and the chord must be pressed again to ink.
    func standAside() {
        guard isInking else { return }
        Log.write("[live-ink] standing aside: the stack or the annotator is up")
        stopInking()
    }

    /// ⌘⇧ went down, so a capture may be starting. macOS's window picker, Space during ⌘⇧4 or ⌘⇧5's
    /// window capture, takes the window whose pixels are under the pointer, so over a mark it took the
    /// overlay, which captures leave out ("Unable to capture window image"). It passes over a window
    /// whose alpha is 0, and it reads the windows when Space is pressed (measured on macOS 15), before
    /// its own window is up. So while there are marks this looks 10 times a second, for
    /// `CaptureOrigin.pollSeconds` and as long as a capture lasts, for a `screencapture` process,
    /// which ⌘⇧4 runs, or a window of `screencaptureui`, which ⌘⇧5 puts up, and clears the
    /// overlays while there is one. The marks are out of the capture either way.
    func watchForWindowPicker() {
        guard !surfaces.isEmpty else { return }
        pickerWatchUntil = Date().addingTimeInterval(CaptureOrigin.pollSeconds)
        guard pickerWatch == nil else { return }
        checkWindowPicker()
        pickerWatch = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkWindowPicker() }
        }
    }

    private func checkWindowPicker() {
        let up = Self.isCapturing()
        if up != pickerUp {
            pickerUp = up
            surfaces.forEach { $0.overlay.alphaValue = up ? 0 : 1 }
            Log.write("[live-ink] \(up ? "clear for" : "back after") a capture")
        }
        if !up, Date() > pickerWatchUntil { stopWatchingForWindowPicker() }
    }

    /// A `screencapture` process is running, or `screencaptureui` has a window on screen. The second
    /// can outlive its capture, so its process alone does not count.
    private static func isCapturing() -> Bool {
        var pids = [pid_t](repeating: 0, count: 4096)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var name = [CChar](repeating: 0, count: 64)
        let capturing = pids.prefix(max(0, count)).contains { pid in
            proc_name(pid, &name, UInt32(name.count)) > 0 && String(cString: name) == "screencapture"
        }
        if capturing { return true }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowOwnerName as String] as? String) == "screencaptureui" }
    }

    private func stopWatchingForWindowPicker() {
        pickerWatch?.invalidate()
        pickerWatch = nil
        if pickerUp { surfaces.forEach { $0.overlay.alphaValue = 1 } }
        pickerUp = false
    }

    /// The marks and the glow drawn again in the current settings.
    func applyTweaks() {
        showMarks()
        if glowing { showGlow(true) }
    }

    /// How far past a stroke's edge a tap still erases it. Wider than the editor's hit margin: nothing
    /// shows which mark a tap would erase, and while inking a tap does nothing else.
    nonisolated static let eraseReach: CGFloat = 12

    /// The index of the mark a tap at `point` erases: the topmost whose stroke it is near, or else the
    /// smallest ellipse it is inside, since a circled thing is where a hand goes to take the circle off.
    nonisolated static func markToErase(at point: CGPoint, in marks: [Mark], markStyle: MarkStyle) -> Int? {
        let near = marks.lastIndex { mark in
            guard let distance = EditorGeometry.strokeDistance(from: point, to: mark, pointScale: 1) else { return false }
            return distance <= markStyle.strokeWidth / 2 + eraseReach
        }
        if let near { return near }
        let around = marks.indices.compactMap { index -> (index: Int, area: CGFloat)? in
            guard case .ellipse(let frame) = marks[index].geometry, EditorGeometry.ellipse(frame, contains: point) else { return nil }
            return (index, frame.width * frame.height)
        }
        return around.min { $0.area < $1.area }?.index
    }

    var stateJSON: [String: Any] {
        [
            "on": isOn,
            "inking": isInking,
            "chord": chord?.isHeld ?? false,
            "surfaces": surfaces.map { surface -> [String: Any] in
                [
                    "frame": StateReport.topLeft(surface.overlay.frame, primaryHeight: StateReport.primaryHeight),
                    "activeSpace": surface.overlay.isOnActiveSpace,
                    "marks": surface.marks.count,
                ]
            },
            "marks": marks.map { mark -> [String: Any] in
                let frame = mark.shapeExtent.map { [$0.minX, $0.minY, $0.width, $0.height].map { Int($0.rounded()) } } ?? []
                return ["type": mark.kind.rawValue, "frame": frame]
            },
        ]
    }

    // MARK: Strokes

    /// Adds the stroke's mark to `surface` and to every other one of `among` it reaches, or erases
    /// the mark a tap on `surface` lands on, from every surface that has it.
    @discardableResult
    private func take(_ points: [CGPoint], on surface: Surface?, among: [Surface]) -> Outcome {
        guard let surface else { return .nothing }
        let ui = Settings.shared.data.ui
        let outcome: Outcome
        switch InkStroke(points, shortestArrow: ui.shortestArrow) {
        case .ellipse(let frame):
            add(Mark(geometry: .ellipse(frame)), on: surface, among: among, markStyle: ui.markStyle)
            outcome = .drew(.ellipse)
        case .arrow(let arrow):
            add(Mark(geometry: .arrow(arrow)), on: surface, among: among, markStyle: ui.markStyle)
            outcome = .drew(.arrow)
        case .tap(let point):
            if let index = Self.markToErase(at: point, in: surface.marks, markStyle: ui.markStyle) {
                let erased = surface.marks[index]
                for other in surfaces { other.marks.removeAll { $0.id == erased.id } }
                outcome = .erased(erased.kind)
            } else {
                outcome = .missed
            }
        case .nothing:
            outcome = .nothing
        }
        Log.write("[live-ink] \(outcome.description) marks=\(marks.count)")
        showMarks()
        return outcome
    }

    /// Adds `mark` to `surface`, and to each other one of `among` whose screen it draws on: its stroke,
    /// its arrowhead, its edge and its shadows, which reach less than `Mark.shadowSize` past the edge.
    private func add(_ mark: Mark, on surface: Surface, among: [Surface], markStyle: MarkStyle) {
        let shape = mark.shape(pointScale: 1, markStyle: markStyle)
        let ink = [shape?.stroked, shape?.filled].compactMap { $0?.boundingBoxOfPath }.reduce(CGRect.null) { $0.union($1) }
        let reach = (shape?.lineWidth ?? 0) / 2 + markStyle.edgeWidth + Mark.shadowSize
        let drawn = ink.insetBy(dx: -reach, dy: -reach)
        for other in among where other === surface || other.overlay.globalFrame.intersects(drawn) {
            other.marks.append(mark)
        }
    }

    // MARK: Inking

    private func chordChanged(_ change: HeldChord.Change) {
        switch change {
        case .began:
            guard mayInk() else {
                Log.write("[live-ink] not inking: the stack or the annotator is up")
                return
            }
            startInking()
        case .ended:
            guard isInking else { return }
            if inking.contains(where: \.overlay.isTracking) { watchRelease() } else { stopInking() }
        }
    }

    private func startInking() {
        isInking = true
        // Pressed again before the button came up: the stroke now ends without ending the inking.
        releaseWatch?.invalidate()
        releaseWatch = nil
        inking = activeSurfaces()
        inking.forEach { $0.overlay.setInking(true) }
        // The glow waits, so holding the chord on the way to a key, as in a window manager's
        // Control-Option-arrow, does not flash it. A press shows it at once.
        glowTimer?.invalidate()
        glowTimer = Timer.scheduledTimer(withTimeInterval: Settings.shared.data.ui.liveInkGlowDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showGlow(true) }
        }
        Log.write("[live-ink] inking")
    }

    private func stopInking() {
        isInking = false
        releaseWatch?.invalidate()
        releaseWatch = nil
        showGlow(false)
        inking.forEach { $0.overlay.setInking(false) }
        inking = []
        closeEmpty(fade: Settings.shared.motionUI.liveInkGlowFade)
        Log.write("[live-ink] stopped")
    }

    private func strokeMoved(_ points: [CGPoint]) {
        if !points.isEmpty, !glowing { showGlow(true) }
        let markStyle = Settings.shared.data.ui.markStyle
        inking.forEach { $0.overlay.showPen(points, markStyle: markStyle) }
    }

    private func strokeEnded(_ points: [CGPoint], on surface: Surface) {
        take(points, on: surface, among: inking)
        if releaseWatch != nil { stopInking() }
    }

    /// The chord was let go during a stroke. The stroke keeps going to its release, and inking ends
    /// with it. A release that never reaches the overlay is read from the button's own state, as the
    /// flight layer's `watchRelease` does, and the stroke ends with the points it has.
    private func watchRelease() {
        releaseWatch?.invalidate()
        releaseWatch = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self.releaseWatch?.invalidate()
                self.releaseWatch = nil
                self.inking.forEach { $0.overlay.endStroke() }
                self.stopInking()
            }
        }
    }

    private func showGlow(_ on: Bool) {
        glowTimer?.invalidate()
        if !on && !glowing { return }
        glowing = on
        let ui = Settings.shared.motionUI
        let color = ui.markStyle.color(.person)
        inking.forEach { $0.overlay.showGlow(on, ui: ui, color: color) }
    }

    // MARK: Surfaces

    /// The active Space's surface on every screen, made for the screens that have none there yet.
    private func activeSurfaces() -> [Surface] {
        NSScreen.screens.compactMap { screen in
            guard let display = Self.display(of: screen) else { return nil }
            if let surface = surfaces.first(where: { $0.overlay.display == display && $0.overlay.isOnActiveSpace }) { return surface }
            let overlay = LiveInkOverlay(screen: screen, display: display)
            overlay.alphaValue = pickerUp ? 0 : 1
            let surface = Surface(overlay)
            overlay.onStrokeMoved = { [weak self] points in self?.strokeMoved(points) }
            overlay.onStroke = { [weak self, weak surface] points in
                guard let surface else { return }
                self?.strokeEnded(points, on: surface)
            }
            surfaces.append(surface)
            return surface
        }
    }

    /// A surface with no marks closes, unless it is taking ink, so an idle live ink puts no
    /// full-screen window over every app.
    private func closeEmpty(fade: TimeInterval) {
        let empty = surfaces.filter { surface in surface.marks.isEmpty && !inking.contains { $0 === surface } }
        empty.forEach { $0.overlay.close(after: fade) }
        surfaces.removeAll { surface in empty.contains { $0 === surface } }
    }

    private func showMarks() {
        let markStyle = Settings.shared.data.ui.markStyle
        for surface in surfaces { surface.overlay.show(surface.marks, markStyle: markStyle) }
    }

    /// Inking stops, since its surfaces are on the Space just left.
    private func spaceChanged() {
        guard isInking else { return }
        Log.write("[live-ink] stopped: the Space changed")
        stopInking()
    }

    /// Each surface covers its screen again; one whose screen is gone closes with its marks.
    private func screensChanged() {
        if isInking { stopInking() }
        let screens = Dictionary(NSScreen.screens.compactMap { screen in Self.display(of: screen).map { ($0, screen) } },
                                 uniquingKeysWith: { first, _ in first })
        for surface in surfaces {
            if let screen = screens[surface.overlay.display] { surface.overlay.fit(to: screen) } else { surface.marks = [] }
        }
        closeEmpty(fade: 0)
        showMarks()
    }

    private static func display(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
