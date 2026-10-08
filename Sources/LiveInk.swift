import AppKit

/// Live ink: drawing straight on the screen, over any app, while Control and Option are held
/// (docs/live-ink-integration-2026-10-04.md). A loop becomes an ellipse and any other stroke an
/// arrow, in the person's colour, and a tap on a mark erases it. The marks stay where they were drawn,
/// on the Space they were drawn on, until they are erased or cleared, live ink is turned off, or
/// Vignette quits. Letting go of the chord after drawing opens a note beside the new ink, and Return
/// there asks `LiveResponder` about it; the answer is drawn on the screen as marks in the agent's
/// colour, which erase and clear as the person's do.
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

    private let responder = LiveResponder()
    /// The marks drawn on an app's window, which stay on it (docs/live-ink-step3-2026-10-05.md). The
    /// surfaces keep the rest: marks drawn where no window is.
    private let windows = LiveWindows()
    /// The working sessions Send can reach, newest first; it may answer twice, with a kept list and
    /// then a fresh one.
    var listSessions: ((@escaping ([AgentDestination]) -> Void) -> Void)?
    /// Sends a picture and a message to a session through today's Send: the request's id, or why it
    /// was refused.
    var sendToSession: ((Data, AgentDestination, String) -> Result<String, ScreenshotRequests.Refusal>)?
    /// Whether a session is in the middle of a turn, or nil when that cannot be told.
    var isWorking: ((AgentDestination) -> Bool?)?
    /// The ask a session is working on, watched until its turn ends: whether the turn was seen to
    /// start, and since when it has been idle.
    private var working: (request: String, seenBusy: Bool, idleSince: Date?, until: Date)?
    private var workingWatch: Timer?
    /// The marks leaving, and how, removed once they have gone.
    private var finishing: [Mark.ID: LiveMarksLayer.Finish] = [:]
    /// The × that dismisses the answer, shown while the pointer is over its note.
    private var dismissButton: LiveDismissButton?
    /// The answer's actions, under its reply while it is on the screen.
    private var actionsPanel: LiveAnswerActions?
    private var pointerWatch: [Any] = []
    private var replyWatch: NSObjectProtocol?
    private var focusRun: FocusRun?
    /// The packet for the ink the note is open on, captured when it opened, so its text can move
    /// the note clear of the window's text and the ask need not capture again.
    private var prepared: (ink: Set<Mark.ID>, packet: Task<LivePacket, Error>, glance: Task<LivePacket.Glance?, Never>)?
    /// The request ids of sends from live ink still waiting for their client's answer.
    private var sending: [String: Shared] = [:]
    /// The person's marks some ask has been about. The rest are new, and the next ask is about them.
    private var asked = Set<Mark.ID>()
    /// A mark was drawn since the chord went down, so letting it go opens the note.
    private var drewWhileInking = false
    private var note: LiveNotePanel?
    /// Listening to the person while they draw, with speech on. It can span several presses of the
    /// chord, so "this" and "that" drawn in two strokes are one note.
    private var listening: LiveListening?
    /// The person typed in the note, so what they say no longer replaces its words.
    private var typedOver = false
    /// The final words of the last listening, while the note holds them as they were said, and when
    /// that listening began, which their times count from.
    private var spoken: (words: [SpokenWord], began: Date)?
    /// When the stroke under way began.
    private var strokeBegan: Date?
    /// When each of the person's strokes was drawn, so a spoken note can say which "this" is which.
    private var strokeTimes: [Mark.ID: (began: Date, ended: Date)] = [:]
    /// The note sent to a session, still on screen until the drawn note takes its place.
    private var handing: LiveNotePanel?
    /// The note's target picked last, which the next note starts on.
    private var lastTarget: LiveNotePanel.Target = .responder
    /// The ask under way, or the last one.
    private var asking: AskState?
    /// The answer a follow-up under way was sent from, and the words sent, which a failed follow-up
    /// puts back (`restoreFollowed`). Gone once the follow-up's answer starts to replace it.
    private var followed: (state: AskState, words: String, pick: LiveAnswerActions.Pick)?
    /// The marks of the last answer, and of a failure's note: a new ask takes them off the screen.
    private var answerMarks = Set<Mark.ID>()
    /// An answer's steps still to show, each a mark and its label, and the window they go on. One is
    /// on the screen, and a click on it shows the next, while `stepClicks` listens.
    private var steps: [[Mark]] = []
    private var stepsWindow: CGWindowID?
    /// What each step's mark points at, and where the mark was then, so a click on the thing counts
    /// as well as one on the mark, wherever its window has moved it since.
    private var stepTargets: [Mark.ID: (target: CGRect, at: CGPoint)] = [:]
    private var stepClicks: Any?
    /// The picture the responder's conversation has, and the ids of the text lines sent with it, so a
    /// follow-up about the same window, showing the same text, sends no picture and only the lines
    /// near its ink not sent yet.
    private var lastPicture: (conversation: Int, windowID: CGWindowID?, text: String, lines: Set<String>)?
    /// Marks that draw themselves on at the next `showMarks`.
    private var drawingOn = Set<Mark.ID>()
    /// The answer's shapes whose window was dark behind them when it was captured, which are drawn
    /// as light on dark (`LightMarkLayer`).
    private var overDark = Set<Mark.ID>()
    /// How the person's hand drew each of their marks, so it is drawn as their ink.
    private var hands: [Mark.ID: InkHand] = [:]
    /// What a tap where the pointer is would do, shown while inking.
    private var preview: LiveMarksLayer.Preview?
    /// The mark a tap just made the person's: no preview shows a tap erasing it until the pointer
    /// has left it.
    private var justPicked: Mark.ID?

    /// An ask handed to a working session, by request id, kept until its answer is drawn: the
    /// session, the person's marks it was about, and the window they were on.
    private struct Shared {
        let session: AgentDestination
        let about: Set<Mark.ID>
        let windowID: CGWindowID?
    }

    /// What `[state]` says about the ask under way, or the last one.
    private struct AskState {
        /// `working`: sent to a session, whose turn is under way.
        enum Phase: String { case looking, asking, working, answered, failed }
        var phase: Phase
        /// The person's marks it is about, which pulse while it is under way.
        var about: Set<Mark.ID>
        var reason: String?
        var picture = false
        /// The reply as it streams in, and once it is whole. A follow-up starts with the reply it
        /// follows, which the next answer's words replace where it hangs.
        var say: Mark?
        /// The newest mark asked about, which the answer's notes stay beside, and how far its content
        /// had moved when the ask began.
        var leader: Mark.ID?
        var leaderShift: CGVector?
        /// The session it was sent to, which the person's reply goes back to; nil for the responder.
        var session: Shared?
        /// The answer's actions, shown as buttons under its reply.
        var actions: [LiveAnswer.Action] = []
        /// The button the person answered the reply with, which stays checked under it, with the
        /// rest, all disabled, until the next answer.
        var picked: LiveAnswerActions.Pick?
        /// Words typed in Reply's field and not sent, which the field opens with again, even after
        /// its panel was rebuilt while the reply was out of sight.
        var draft = ""
        /// For each of the answer's marks, the marks drawn for it, which an action names by index.
        var findings: [[Mark.ID]] = []
    }

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

    /// Every mark, on every Space and window, once each, where it was last shown.
    var marks: [Mark] { screenMarks + windows.marks.map(\.mark) }

    /// The marks on screen now: a mark on a window is left out while its content moves or after it
    /// was lost.
    private var shownMarks: [Mark] { windows.marks.filter(\.shown).map(\.mark) + screenMarks }

    private var screenMarks: [Mark] {
        var seen = Set<Mark.ID>()
        return surfaces.flatMap(\.marks).filter { seen.insert($0.id).inserted }
    }

    init(mayInk: @escaping () -> Bool) {
        self.mayInk = mayInk
        windows.onGone = { [weak self] ids in self?.forget(ids) }
        windows.drawnExtent = { [weak self] mark in self.flatMap { Self.drawnExtent(of: mark, sizes: $0.answerSizes) } }
    }

    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            LivePacket.warmUp()
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
            endConversation()
            chord = nil
            for (center, observer) in observers { center.removeObserver(observer) }
            observers = []
            surfaces.forEach { $0.marks = [] }
            showMarks()
            surfaces.forEach { $0.overlay.close(after: LiveMarksLayer.removalFade) }
            surfaces = []
            windows.removeAll()
        }
        Log.write("[live-ink] \(on ? "on" : "off")")
    }

    /// What a stroke did, as `[live-ink]` lines and `live-ink-stroke` answer it.
    enum Outcome {
        case drew(MarkKind)
        case erased(MarkKind)
        /// A tap on an answer's loop or arrow, which made it the person's.
        case picked(MarkKind)
        /// A tap on no mark.
        case missed
        /// A stroke that is no mark and no tap.
        case nothing

        var description: String {
            switch self {
            case .drew(let kind): "drew \(kind.rawValue)"
            case .erased(let kind): "erased \(kind.rawValue)"
            case .picked(let kind): "picked \(kind.rawValue)"
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
        closeEmpty(fade: LiveMarksLayer.removalFade)
        return outcome
    }

    /// Erases every mark, and says how many there were.
    @discardableResult
    func clear() -> Int {
        let count = marks.count
        for surface in surfaces { surface.marks = [] }
        windows.removeAll()
        endConversation()
        showMarks()
        closeEmpty(fade: LiveMarksLayer.removalFade)
        Log.write("[live-ink] cleared \(count)")
        return count
    }

    /// The stack or the annotator is coming up under the raised overlays: inking stops, the stroke
    /// under way is dropped, and the chord must be pressed again to ink.
    func standAside() {
        closeNote()
        stopListening()
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
        guard !surfaces.isEmpty || !windows.isEmpty else { return }
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
            windows.pickerClear = up
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
        if pickerUp {
            surfaces.forEach { $0.overlay.alphaValue = 1 }
            windows.pickerClear = false
        }
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

    /// The index of the mark a tap at `point` erases: the topmost note it is on, or whose stroke it is
    /// near, or else the smallest ellipse it is inside, since a circled thing is where a hand goes to
    /// take the circle off. `noteBox` gives a note's tag.
    nonisolated static func markToErase(at point: CGPoint, in marks: [Mark], markStyle: MarkStyle,
                                        noteBox: (Mark) -> CGRect? = { _ in nil }) -> Int? {
        let near = marks.lastIndex { mark in
            if let box = noteBox(mark) { return box.contains(point) }
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
            "listening": listening != nil,
            "surfaces": surfaces.map { surface -> [String: Any] in
                [
                    "frame": StateReport.topLeft(surface.overlay.frame, primaryHeight: StateReport.primaryHeight),
                    "activeSpace": surface.overlay.isOnActiveSpace,
                    "marks": surface.marks.count,
                ]
            },
            "marks": marks.map { mark -> [String: Any] in
                let extent = mark.shapeExtent ?? LiveAnswerLayout.noteBox(mark, sizes: answerSizes)
                let frame = extent.map { [$0.minX, $0.minY, $0.width, $0.height].map { Int($0.rounded()) } } ?? []
                return ["id": mark.id.uuidString, "type": mark.kind.rawValue, "frame": frame, "agent": mark.agent,
                        "shown": shownMarks.contains { $0.id == mark.id }, "window": windows.window(of: mark.id).map { Int($0) } ?? NSNull()]
            },
            "windows": windows.stateJSON,
            "new": newInk.count,
            "steps": stepClicks == nil ? 0 : steps.count + 1,
            "focus": focusRun.map { run -> Any in
                ["stop": run.index + 1, "stops": run.stops.count, "zoom": run.stops.indices.contains(run.index) && run.stops[run.index].first?.focus?.zoom == true]
            } ?? NSNull(),
            "note": note.map { panel -> Any in StateReport.topLeft(panel.frame, primaryHeight: StateReport.primaryHeight) } ?? NSNull(),
            "actions": actionsPanel.map { panel -> Any in
                panel.buttons.map { ["title": $0.title, "frame": [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height].map { Int($0.rounded()) },
                                     "enabled": $0.enabled, "picked": $0.picked] }
            } ?? NSNull(),
            "replyField": actionsPanel?.fieldFrame.map { [$0.minX, $0.minY, $0.width, $0.height].map { Int($0.rounded()) } } ?? NSNull(),
            "replyCancel": actionsPanel?.cancelFrame.map { [$0.minX, $0.minY, $0.width, $0.height].map { Int($0.rounded()) } } ?? NSNull(),
            "dismiss": dismissButton.map { button -> Any in StateReport.topLeft(button.frame, primaryHeight: StateReport.primaryHeight) } ?? NSNull(),
            "noteTarget": note.map { panel -> Any in panel.target == .responder ? "responder" : "session" } ?? NSNull(),
            "responder": responder.stateJSON,
            "ask": asking.map { ask -> Any in
                var json: [String: Any] = ["phase": ask.phase.rawValue, "about": ask.about.count, "picture": ask.picture]
                if let reason = ask.reason { json["reason"] = reason }
                if let say = ask.say, case .text(let text) = say.geometry { json["sayLength"] = text.text.count }
                return json
            } ?? NSNull(),
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
            let mark = Mark(geometry: .ellipse(frame))
            stroked(mark, by: points)
            place(mark, on: surface, among: among, markStyle: ui.markStyle)
            outcome = .drew(.ellipse)
            drewWhileInking = true
        case .arrow(let arrow):
            let mark = Mark(geometry: .arrow(arrow))
            stroked(mark, by: points)
            place(mark, on: surface, among: among, markStyle: ui.markStyle)
            outcome = .drew(.arrow)
            drewWhileInking = true
        case .tap(let point):
            switch tapTarget(at: point, on: surface) {
            case .pick(let hit):
                pick(hit, on: surface, among: among)
                outcome = .picked(hit.kind)
                drewWhileInking = true
            case .erase(let hit):
                remove([hit.id])
                outcome = .erased(hit.kind)
            case nil:
                outcome = .missed
            }
        case .nothing:
            outcome = .nothing
        }
        Log.write("[live-ink] \(outcome.description) marks=\(marks.count)")
        showMarks()
        return outcome
    }

    /// Records when `mark` was drawn: from the stroke's first move to now. With the stroke's `points`,
    /// it also records the hand that drew it, and the mark eases onto its shape from them.
    private func stroked(_ mark: Mark, by points: [CGPoint]? = nil) {
        strokeTimes[mark.id] = (strokeBegan ?? Date(), Date())
        if let points, let hand = InkHand(raw: points, mark: mark) {
            hands[mark.id] = hand
            drawingOn.insert(mark.id)
        }
    }

    /// Puts a mark the person drew on the window under it, or on `surface` where there is none.
    private func place(_ mark: Mark, on surface: Surface, among: [Surface], markStyle: MarkStyle) {
        let point = LiveWindows.anchorPoint(of: mark)
        if let target = windows.target(under: point) {
            windows.pin(mark, to: target, anchor: .at(point))
        } else {
            add(mark, on: surface, among: among, markStyle: markStyle)
        }
    }

    private enum TapTarget {
        case erase(Mark)
        case pick(Mark)

        var preview: LiveMarksLayer.Preview {
            switch self {
            case .erase(let mark): .erase(mark.id)
            case .pick(let mark): .pick(mark.id)
            }
        }
    }

    /// What a tap at `point` would do: pick an answer's loop or arrow, or erase any other mark.
    private func tapTarget(at point: CGPoint, on surface: Surface) -> TapTarget? {
        let sizes = answerSizes
        let candidates = erasable(at: point, on: surface)
        guard let index = Self.markToErase(at: point, in: candidates, markStyle: Settings.shared.data.ui.markStyle,
                                           noteBox: { LiveAnswerLayout.noteBox($0, sizes: sizes) }) else { return nil }
        let hit = candidates[index]
        return hit.agent && hit.kind != .text && hit.focus == nil && answerMarks.contains(hit.id) ? .pick(hit) : .erase(hit)
    }

    /// Shows what a tap at `point` would do, or nothing with no point.
    private func hover(at point: CGPoint?) {
        let surface = point.flatMap { point in inking.first { $0.overlay.globalFrame.contains(point) } }
        var next = point.flatMap { point in surface.flatMap { tapTarget(at: point, on: $0)?.preview } }
        if let picked = justPicked, point != nil {
            if next?.id == picked { next = nil } else { justPicked = nil }
        }
        guard next != preview else { return }
        preview = next
        surfaces.forEach { $0.overlay.preview(next) }
        windows.preview(next)
    }

    /// Makes an answer's loop or arrow the person's own, drawn again in their colour, so the next ask
    /// is about what it points at. An answer that loops two candidates asks which one, and a tap picks
    /// it; the rest of the answer stays until that ask.
    private func pick(_ mark: Mark, on surface: Surface, among: [Surface]) {
        let own = Mark(geometry: mark.geometry)
        stroked(own)
        // Shown in the person's colour already when the pointer rested on it first.
        if preview != .pick(mark.id) { drawingOn.insert(own.id) }
        justPicked = own.id
        place(own, on: surface, among: among, markStyle: Settings.shared.data.ui.markStyle)
        answerMarks.remove(mark.id)
        remove([mark.id])
    }

    /// The marks a tap at `point` may erase, the topmost last: those on the surface, and those on the
    /// window under the tap that show, since a window in front covers the rest.
    private func erasable(at point: CGPoint, on surface: Surface) -> [Mark] {
        let top = windows.target(under: point)?.id
        return windows.marks.filter { $0.shown && $0.window == top }.map(\.mark) + surface.marks
    }

    /// Takes marks off every surface and window.
    private func remove(_ ids: Set<Mark.ID>) {
        for surface in surfaces { surface.marks.removeAll { ids.contains($0.id) } }
        windows.remove(ids)
    }

    /// Marks that went with their window.
    private func forget(_ ids: Set<Mark.ID>) {
        asked.subtract(ids)
        answerMarks.subtract(ids)
        showMarks()
    }

    /// The rect a mark draws in, its stroke, edge and shadows included.
    private static func drawnExtent(of mark: Mark, sizes: LiveAnswerLayout.Sizes) -> CGRect? {
        if case .text = mark.geometry { return LiveAnswerLayout.noteBox(mark, sizes: sizes)?.insetBy(dx: -Mark.shadowSize, dy: -Mark.shadowSize) }
        let markStyle = Settings.shared.data.ui.markStyle
        guard let shape = mark.shape(pointScale: 1, markStyle: markStyle) else { return nil }
        let ink = [shape.stroked, shape.filled].compactMap { $0?.boundingBoxOfPath }.reduce(CGRect.null) { $0.union($1) }
        let reach = shape.lineWidth / 2 + markStyle.edgeWidth + Mark.shadowSize
        return ink.insetBy(dx: -reach, dy: -reach)
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

    // MARK: Asking

    /// The person's own marks on screen now, oldest first: a failure's note is in their colour, but
    /// Vignette's.
    private var ink: [Mark] { shownMarks.filter { !$0.agent && !answerMarks.contains($0.id) } }

    /// The person's marks no ask has been about yet, oldest first.
    private var newInk: [Mark] { ink.filter { !asked.contains($0.id) } }

    var responderState: LiveResponder.State { responder.state }

    private var answerSizes: LiveAnswerLayout.Sizes {
        let ui = Settings.shared.data.ui
        return LiveAnswerLayout.Sizes(textSize: ui.liveInkTextSize, textWidth: ui.liveInkTextWidth, style: ui.textStyle)
    }

    private func openNote() {
        guard let mark = newInk.last(where: { $0.shapeExtent != nil }), let newest = mark.shapeExtent else { return }
        closeNote()
        let ui = Settings.shared.data.ui
        let panel = LiveNotePanel(beside: newest, textSize: answerSizes.textSize, style: ui.textStyle, markStyle: ui.markStyle, target: lastTarget)
        panel.onAsk = { [weak self, weak panel] words, target in
            guard let self else { return }
            self.stopListening()
            self.note = nil
            self.lastTarget = target
            self.handing = panel
            let session: AgentDestination? = if case .session(let destination) = target { destination } else { nil }
            if case .failure = self.ask(words, sendingTo: session, from: panel?.tagFrame) { self.letGoOfNote(into: nil) }
        }
        prepare(beside: mark, panel: panel)
        listSessions? { [weak panel] list in panel?.setSessions(list) }
        panel.onClose = { [weak self] in
            self?.note = nil
            self?.stopListening()
            Log.write("[live-ink] note closed")
        }
        panel.onTyped = { [weak self] in self?.typedInNote() }
        if let listening {
            panel.setListening(true)
            if !typedOver, !listening.words.isEmpty { panel.hear(listening.text) }
        }
        note = panel
        Log.write("[live-ink] note open")
    }

    private func closeNote() {
        note?.dismiss()
        note = nil
    }

    /// Fades the sent note into the drawn one at `tag`, or where it is.
    private func letGoOfNote(into tag: CGRect?) {
        handing?.settle(into: tag)
        handing = nil
    }

    /// Asks the responder about the new ink, with `words` as its note, or about the ink asked about
    /// last when there is none new, as a follow-up. With `session`, sends the picture and the words to
    /// that working session instead, whose answer `showAnswer` draws. `following` is the reply the
    /// person answered with `picked`: it stays, quoting their words in place of a note, with the
    /// answer's marks, which carry the thinking light until the next answer replaces them. Answers
    /// whether an ask started, and why not.
    @discardableResult
    func ask(_ words: String, sendingTo session: AgentDestination? = nil, from spot: CGRect? = nil,
             following reply: Mark? = nil, picked: LiveAnswerActions.Pick? = nil) -> Result<Void, LiveResponder.Failure> {
        closeNote()
        // The words as they were said, unless the person changed them in the note.
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let said = spoken.flatMap { LiveListening.text(of: $0.words).trimmingCharacters(in: .whitespacesAndNewlines) == trimmed ? $0 : nil }
        spoken = nil
        let person = ink
        let fresh = newInk
        let about = fresh.isEmpty ? person.filter { asked.contains($0.id) } : fresh
        guard let point = about.last?.shapeExtent.map({ CGPoint(x: $0.midX, y: $0.midY) }) else {
            return .failure(LiveResponder.Failure(reason: "There's no ink to ask about.", detail: "no ink"))
        }
        if case .looking = asking?.phase { return .failure(LiveResponder.Failure(reason: "An ask is under way.", detail: "busy")) }
        if case .asking = asking?.phase { return .failure(LiveResponder.Failure(reason: "An ask is under way.", detail: "busy")) }
        if reply == nil { removeAnswer() }
        let ids = Set(about.map(\.id))
        asked.formUnion(ids)
        // The ink leads, not the person's note: the notes follow it directly, so moving its content
        // moves the question and the reply together.
        let leader = about.last { $0.kind != .text }?.id ?? about.last?.id
        asking = AskState(phase: .looking, about: ids, leader: leader, leaderShift: leader.flatMap(windows.shift(of:)))
        if let reply {
            asking?.say = reply
            asking?.picked = picked
            asking?.about.formUnion(answerMarks)
            put([reply], window: windows.window(of: reply.id))
        }
        showMarks()
        let started = Date()
        let ui = Settings.shared.data.ui
        Log.write("[live-ink] asking new=\(fresh.count) words=\(words.count)")
        let early = prepared.flatMap { $0.ink == Set(person.map(\.id)) ? $0.packet : nil }
        prepared = nil
        Task { @MainActor [weak self] in
            do {
                let packet: LivePacket
                if let early {
                    packet = try await early.value
                } else {
                    packet = try await LivePacket.build(at: point, ink: person, style: ui.textStyle, markStyle: ui.markStyle)
                }
                if let session {
                    self?.share(packet, words: words, spoken: said, with: session, from: spot)
                } else {
                    self?.send(packet, words: words, spoken: said, about: about, new: Set(fresh.map(\.id)), started: started, from: spot)
                }
            } catch let failure as LivePacket.Failure {
                Log.write("[live-ink] error packet \(failure.detail)")
                self?.failed(LiveResponder.Failure(reason: failure.reason, detail: failure.detail))
            } catch {
                self?.failed(LiveResponder.Failure(reason: "Vignette couldn't see the screen.", detail: "\(error)"))
            }
        }
        return .success(())
    }

    private func send(_ packet: LivePacket, words: String, spoken: (words: [SpokenWord], began: Date)?, about: [Mark],
                      new: Set<Mark.ID>, started: Date, from spot: CGRect?) {
        guard asking?.phase == .looking else { return letGoOfNote(into: nil) }
        let note = numberedNote(spoken, packet: packet) ?? words
        asking?.phase = .asking
        // The words stay beside the ink as the person's note, which the reply hangs under, unless
        // the reply is up already, quoting them.
        let question = asking?.say == nil ? promptNote(words, about: Set(about.map(\.id)), packet: packet, at: spot) : nil
        if let question { asking?.about.insert(question.id) }
        letGoOfNote(into: question.flatMap { LiveAnswerLayout.noteBox($0, sizes: answerSizes) })
        if question != nil { showMarks() }
        let person = ink.filter { packet.frame.intersects($0.shapeExtent ?? .null) }
        let asked = about.compactMap(\.shapeExtent).reduce(CGRect.null) { $0.union($1) }
        let near = packet.lines(near: asked)
        Log.write("[live-ink] packet ms=\(Int(Date().timeIntervalSince(started) * 1000)) app=\(packet.app ?? "none") lines=\(packet.lines.count) near=\(near.count) bytes=\(packet.picture.count)\(packet.detail == nil ? "" : " detail")")
        responder.ask(LiveResponder.Ask(
            content: { [weak self] conversation in
                let last = self?.lastPicture
                let same = last.map { $0.conversation == conversation && $0.windowID == packet.windowID && $0.text == packet.textSignature } ?? false
                let sent = same ? last?.lines ?? [] : []
                let unsent = near.filter { !sent.contains($0.id) }
                self?.lastPicture = (conversation, packet.windowID, packet.textSignature, sent.union(unsent.map(\.id)))
                self?.asking?.picture = !same
                var content: [[String: Any]] = []
                if !same {
                    content.append(Self.image(packet.picture))
                    if let detail = packet.detail { content.append(Self.image(detail.png)) }
                }
                if let lines = LivePacket.textLines(unsent) { content.append(["type": "text", "text": lines]) }
                content.append(["type": "text", "text": packet.message(note: note, ink: person, new: new, freshPicture: !same)])
                return content
            },
            onSay: { [weak self] say in self?.showSay(say, near: asked, question: question, packet: packet) },
            onAnswer: { [weak self] result in
                switch result {
                case .success(let answer):
                    self?.answered(answer, packet: packet, sent: self?.lastPicture?.lines ?? [], near: asked, question: question)
                case .failure(let failure): self?.failed(failure)
                }
            }))
    }

    /// Hands the picture to a working session through Send, with the words and where the ink is in
    /// the message, and says on the ink that it went.
    private func share(_ packet: LivePacket, words: String, spoken: (words: [SpokenWord], began: Date)?, with session: AgentDestination,
                       from spot: CGRect?) {
        guard asking?.phase == .looking, let about = asking?.about, let sendToSession else { return letGoOfNote(into: nil) }
        let numbered = numberedNote(spoken, packet: packet)
        var place = [packet.app, packet.title.map { "\"\($0)\"" }, packet.location].compactMap { $0 }.joined(separator: ", ")
        if place.isEmpty { place = "the screen" }
        // One line: the plugin's monitor makes each line it prints a message of its own.
        var said = (numbered ?? words).components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        if let last = said.last, !".?!]".contains(last) { said += "." }
        var message = (said.isEmpty ? "" : said + " ") + "Drawn with Vignette's live ink on \(place)."
        if numbered != nil { message += " Each [n] in the words is where the ink numbered n in the picture was drawn as they were said." }
        switch sendToSession(packet.picture, session, message) {
        case .success(let request):
            asking?.phase = .working
            let note = promptNote(words, about: about, packet: packet, at: spot)
            if let note { asking?.about.insert(note.id) }
            letGoOfNote(into: note.flatMap { LiveAnswerLayout.noteBox($0, sizes: answerSizes) })
            sending[request] = Shared(session: session, about: asking?.about ?? about, windowID: packet.windowID)
            Log.write("[live-ink] sent to a session request=\(request)")
            watchWorking(request)
            showMarks()
        case .failure(let refusal):
            failed(LiveResponder.Failure(reason: "Not sent. " + refusal.reason, detail: "send refused"))
        }
    }

    /// The spoken words with the numbers of the strokes drawn while they were said put in where each
    /// was drawn, or nil when the note is not as it was said or no stroke was drawn while speaking.
    private func numberedNote(_ spoken: (words: [SpokenWord], began: Date)?, packet: LivePacket) -> String? {
        guard let spoken else { return nil }
        let strokes = packet.numbers.compactMap { id, number -> SpokenNote.Stroke? in
            guard let times = strokeTimes[id] else { return nil }
            let stroke = SpokenNote.Stroke(number: number, start: times.began.timeIntervalSince(spoken.began),
                                           end: times.ended.timeIntervalSince(spoken.began))
            // A stroke that ended before listening began belongs to an earlier note.
            return stroke.end >= 0 ? stroke : nil
        }
        guard !strokes.isEmpty else { return nil }
        Log.write("[speech] numbered strokes=\(strokes.count)")
        return SpokenNote.marked(spoken.words, strokes: strokes)
    }

    /// The person's words, kept beside their ink in their colour as their own note, so the ink says
    /// what was asked while the session works on it. Its tag takes the note panel's, `spot`, with no
    /// animation, since the panel fades into it; without one it keeps off the window's text, as an
    /// answer's note does, and springs in. Nil for an ask with no words.
    private func promptNote(_ words: String, about: Set<Mark.ID>, packet: LivePacket, at spot: CGRect?) -> Mark? {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let near = marks.filter { about.contains($0.id) }.compactMap(\.shapeExtent).reduce(CGRect.null) { $0.union($1) }
        guard !words.isEmpty, !near.isNull else { return nil }
        let scene = scene(for: packet)
        let note = spot.map { LiveAnswerLayout.note(words, at: $0, sizes: answerSizes) }
            ?? LiveAnswerLayout.note(words, near: near, scene: scene, obstacles: LiveAnswerLayout.obstacles(in: scene), sizes: answerSizes,
                                     byPerson: true)
        asked.insert(note.id)
        if spot == nil { drawingOn.insert(note.id) }
        put([note], window: packet.windowID)
        return note
    }

    /// How long an ask may show the thinking light with no word on the session's turn, as from a
    /// route that cannot tell.
    private static let workingLimit: TimeInterval = 180
    /// How long the turn must stay idle to count as over: the line waits for a turn under way to
    /// end, and the session's own turn starts a moment after.
    private static let idleSettle: TimeInterval = 2

    /// Reads the session's turn twice a second, and ends the thinking light once the turn it started is
    /// over, whether or not it answered on the screen.
    private func watchWorking(_ request: String) {
        working = (request, false, nil, Date().addingTimeInterval(Self.workingLimit))
        workingWatch?.invalidate()
        workingWatch = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkWorking() }
        }
    }

    private func checkWorking() {
        guard let watched = working, let shared = sending[watched.request], asking?.phase == .working,
              asking?.about == shared.about else { return stopWorking() }
        let busy = isWorking?(shared.session)
        if busy == true {
            working?.seenBusy = true
            working?.idleSince = nil
        } else if busy == false, watched.seenBusy {
            let since = watched.idleSince ?? Date()
            working?.idleSince = since
            guard Date().timeIntervalSince(since) >= Self.idleSettle else { return }
            Log.write("[live-ink] session's turn ended request=\(watched.request)")
            return finishWorking()
        }
        if Date() > watched.until {
            Log.write("[live-ink] stopped waiting on the session request=\(watched.request)")
            finishWorking()
        }
    }

    /// The session's turn is over. With no answer drawn on the window, the ink and its note play
    /// the done animation and go, since the person sees the change itself; an answer keeps them,
    /// as what it is beside. The reply the person answered is not an answer to what they said.
    private func finishWorking() {
        stopWorking()
        asking?.phase = .answered
        guard let about = asking?.about, asking?.say == nil || asking?.picked != nil else { return showMarks() }
        finish(about, .done)
    }

    /// How long marks take to leave before they are removed.
    private func finishDuration(_ how: LiveMarksLayer.Finish) -> TimeInterval {
        let motion = Settings.shared.motionScale
        guard motion > 0 else { return LiveMarksLayer.doneFade + 0.05 }
        return ((how == .done ? LiveMarksLayer.doneHold : 0) + LiveMarksLayer.doneAway) * motion + 0.15
    }

    private func finish(_ ids: Set<Mark.ID>, _ how: LiveMarksLayer.Finish) {
        for id in ids { finishing[id] = how }
        Log.write("[live-ink] \(how == .done ? "done" : "dismissed") marks=\(ids.count)")
        showMarks()
        DispatchQueue.main.asyncAfter(deadline: .now() + finishDuration(how)) { [weak self] in
            guard let self, ids.contains(where: { self.finishing[$0] != nil }) else { return }
            for id in ids { self.finishing[id] = nil }
            self.asked.subtract(ids)
            self.answerMarks.subtract(ids)
            if self.asking?.about.isSubset(of: ids) == true { self.asking = nil }
            self.remove(ids)
            self.showMarks()
            self.closeEmpty(fade: 0)
        }
    }

    /// Takes the answer off the screen with the ink it was about, and the person's note.
    func dismissAnswer() {
        hideDismissButton()
        stopSteps()
        letGoOfFocus(because: "dismissed")
        let ids = answerMarks.union(asking?.about ?? [])
        guard !ids.isEmpty else { return }
        finish(ids, .dismissed)
    }

    /// How long a new note waits out of sight for the window's text before it shows where it opened.
    private static let revealLimit: TimeInterval = 0.8

    /// Starts capturing the window under the ink as a stroke ends, while the chord is still held,
    /// so the note can open clear of the window's text without waiting for a capture of its own. The
    /// note waits only for the glance at where the text is, which comes long before the packet.
    private func prefetch(at point: CGPoint) {
        let person = ink
        let ui = Settings.shared.data.ui
        let (glances, glanced) = AsyncStream<LivePacket.Glance>.makeStream()
        let packet = Task { @MainActor in
            defer { glanced.finish() }
            return try await LivePacket.build(at: point, ink: person, style: ui.textStyle, markStyle: ui.markStyle,
                                              glanced: { glanced.yield($0) })
        }
        let glance = Task { @MainActor () -> LivePacket.Glance? in
            for await glance in glances { return glance }
            return nil
        }
        prepared = (Set(person.map(\.id)), packet, glance)
    }

    /// Shows the note against its ink, where a hand would write it, which needs the window's frame
    /// and text from a glance at the window: the one started as the stroke ended, which also serves
    /// the ask when the ink is the same, or a new one. Without an answer in `revealLimit`, the note
    /// shows where it opened.
    private func prepare(beside newest: Mark, panel: LiveNotePanel) {
        let person = ink
        let extent = newest.shapeExtent ?? .zero
        if prepared?.ink != Set(person.map(\.id)) { prefetch(at: CGPoint(x: extent.midX, y: extent.midY)) }
        if let glance = prepared?.glance { place(panel, beside: newest, from: glance) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.revealLimit) { [weak panel] in panel?.reveal(at: nil) }
    }

    private func place(_ panel: LiveNotePanel, beside newest: Mark, from glance: Task<LivePacket.Glance?, Never>) {
        Task { @MainActor [weak self, weak panel] in
            guard let glance = await glance.value, let self, let panel, self.note === panel else {
                panel?.reveal(at: nil)
                return
            }
            let scene = self.scene(frame: glance.frame, page: glance.page, text: glance.text)
            let pill = panel.pillFrame
            // Room for the words still to come, so typing does not grow it over the ink; the chip under it.
            let size = CGSize(width: max(pill.width, LiveNotePanel.roomyWidth), height: pill.height)
            let spot = LiveAnswerLayout.noteSpot(size, under: panel.globalFrame.height - pill.height, for: newest, scene: scene)
            panel.reveal(at: spot.rect, growsLeft: spot.growsLeft)
        }
    }

    private func stopWorking() {
        workingWatch?.invalidate()
        workingWatch = nil
        working = nil
    }

    // MARK: Dismissing and actions

    /// The answer's reply popover, while it is up.
    private var shownReply: ReplyPopover? {
        guard let say = asking?.say, answerMarks.contains(say.id), finishing[say.id] == nil,
              let popover = windows.popover(of: say.id) ?? surfaces.lazy.compactMap({ $0.overlay.popover(of: say.id) }).first,
              popover.globalFrame != nil
        else { return nil }
        return popover
    }

    /// The answer's reply, its popover's body where AppKit put it, in global top-left points.
    private var shownSay: CGRect? { shownReply?.globalFrame }

    /// Follows the pointer for as long as an answer is up, in sight or not, to show the × over its
    /// reply, and keeps the actions at the reply's foot as its window scrolls.
    private func watchPointer() {
        guard pointerWatch.isEmpty else { return }
        // The reply's popover can move with its window, or fade, while the pointer is still.
        replyWatch = NotificationCenter.default.addObserver(forName: .liveReplyChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        let moved: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.pointerMoved() } }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .scrollWheel], handler: moved) {
            pointerWatch.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { event in moved(event); return event }) {
            pointerWatch.append(local)
        }
    }

    private func stopWatchingPointer() {
        pointerWatch.forEach(NSEvent.removeMonitor)
        pointerWatch = []
        replyWatch.map(NotificationCenter.default.removeObserver)
        replyWatch = nil
        hideDismissButton()
        hideActions()
    }

    private func pointerMoved() {
        showActions()
        guard let reply = shownReply, let note = reply.globalFrame, !isInking, offersDismiss else { return hideDismissButton() }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: StateReport.primaryHeight - mouse.y)
        let over = note.insetBy(dx: -10, dy: -10).contains(point) || dismissButton?.globalFrame.insetBy(dx: -6, dy: -6).contains(point) == true
        guard over else { return hideDismissButton() }
        if let dismissButton {
            reply.carry(dismissButton)
            dismissButton.place(at: CGPoint(x: note.maxX, y: note.minY))
        } else {
            let button = LiveDismissButton(at: CGPoint(x: note.maxX, y: note.minY), over: reply)
            button.onClick = { [weak self] in
                Log.write("[live-ink] answer dismissed by its ×")
                self?.dismissAnswer()
            }
            dismissButton = button
        }
    }

    /// Not while a follow-up is under way, unless its send was queued or not confirmed, when its
    /// answer may be a long time coming.
    private var offersDismiss: Bool { asking?.picked == nil || asking?.say?.notice != nil }

    private func hideDismissButton() {
        dismissButton?.hide()
        dismissButton = nil
    }

    /// Shows the answer's buttons in the room kept at its reply's foot, or moves them there.
    private func showActions() {
        guard let reply = shownReply, let note = reply.globalFrame, let ask = asking, ask.phase == .answered || ask.picked != nil
        else { return hideActions() }
        let insets = ReplyContent.insets
        let corner = CGPoint(x: note.minX + insets.left, y: note.maxY - insets.bottom - LiveAnswerActions.height)
        let width = note.width - insets.left - insets.right
        if let actionsPanel {
            reply.carry(actionsPanel)
            return actionsPanel.place(at: corner, width: width)
        }
        let panel = LiveAnswerActions(ask.actions, answerer: NoteBadge.label(for: ask.say?.agentName), at: corner, width: width,
                                      over: reply, picked: ask.picked, draft: ask.draft)
        panel.onPick = { [weak self] action in self?.respond(action, by: .action(action)) }
        panel.onReply = { [weak self] words in self?.respond(words, by: .reply) }
        let replyID = ask.say?.id
        panel.onDraft = { [weak self] words in
            // Only the answer the panel was made for keeps its draft: one hidden after a new ask began
            // must not hand its words to the new answer.
            guard let self, self.asking?.say?.id == replyID else { return }
            self.asking?.draft = words
        }
        panel.onPoint = { [weak self] action in self?.point(at: action) }
        actionsPanel = panel
    }

    private func hideActions() {
        if actionsPanel != nil { point(at: nil) }
        actionsPanel?.hide()
        actionsPanel = nil
    }

    /// The pointer is on an action, or nil when it left them: the marks it acts on stand out and the
    /// rest of the answer's findings fade, so "Header only" shows which. One that acts on every mark
    /// changes nothing.
    private func point(at action: LiveAnswer.Action?) {
        let findings = asking?.findings ?? []
        let all = Set(findings.joined())
        let lit = action?.marks.map { Set($0.flatMap { $0 < findings.count ? findings[$0] : [] }) } ?? all
        windows.light(lit, among: all)
    }

    /// The person answered the reply, with one of its actions or with words typed after Reply: the
    /// words go back to whoever answered, about the same ink. The reply stays where it is, quoting
    /// them, and it and the ink carry the thinking light until the next answer takes its place. A
    /// session gets them with a fresh picture of the window; the responder takes them as a follow-up ask.
    private func respond(_ words: String, by pick: LiveAnswerActions.Pick) {
        Log.write("[live-ink] \(pick == .reply ? "reply typed" : "action picked") words=\(words.count)")
        hideDismissButton()
        point(at: nil)
        guard let answer = asking, let said = answer.say, let note = shownSay else { return }
        actionsPanel?.pick(pick)
        followed = (answer, words, pick)
        guard let shared = asking?.session, let sendToSession else {
            // A new ask starts from the reply where it is now.
            guard var reply = marks.first(where: { $0.id == said.id }) else { return }
            reply.quote = words
            reply.notice = nil
            if case .failure(let failure) = ask(words, following: reply, picked: pick) { restoreFollowed(saying: failure.reason) }
            return
        }
        var reply = said
        reply.quote = words
        reply.notice = nil
        let about = (asking?.about ?? []).union(answerMarks)
        let ui = Settings.shared.data.ui
        asking?.say = reply
        asking?.picked = pick
        asking?.reason = nil
        asking?.phase = .working
        asking?.about = about
        put([reply], window: shared.windowID)
        Task { @MainActor [weak self] in
            do {
                let packet = try await LivePacket.build(at: CGPoint(x: note.midX, y: note.midY), window: shared.windowID, ink: self?.ink ?? [],
                                                        style: ui.textStyle, markStyle: ui.markStyle)
                guard let self, self.asking?.about == about else { return }
                var place = [packet.app, packet.title.map { "\"\($0)\"" }, packet.location].compactMap { $0 }.joined(separator: ", ")
                if place.isEmpty { place = "the screen" }
                let words = words.trimmingCharacters(in: .whitespaces)
                let how = pick == .reply ? "Replied" : "Picked"
                let message = words + (".?!".contains(words.last ?? " ") ? "" : ".") + " \(how) under your answer on \(place)."
                switch sendToSession(packet.picture, shared.session, message) {
                case .success(let request):
                    self.sending[request] = Shared(session: shared.session, about: about, windowID: shared.windowID)
                    Log.write("[live-ink] sent to a session request=\(request)")
                    self.watchWorking(request)
                case .failure(let refusal):
                    self.failed(LiveResponder.Failure(reason: "Not sent. " + refusal.reason, detail: "send refused"))
                }
            } catch {
                guard let self, self.asking?.about == about else { return }
                self.failed(LiveResponder.Failure(reason: "Vignette couldn't see the screen.", detail: "\(error)"))
            }
        }
    }

    // MARK: Answering

    /// Whether the request is one live ink sent, which its answer and its failures come back to.
    func sent(request: String) -> Bool { sending[request] != nil }

    /// A send's client answered. A send that went says nothing, since the thinking light already says the
    /// session has it; any other outcome says why on the ink, or in the reply's header for a follow-up,
    /// while that ink is still the last asked about.
    func delivered(request: String, _ state: SendNotice.State, reason: String?) {
        guard let shared = sending[request] else { return }
        let project = shared.session.project
        switch state {
        case .sent: break
        case .queued, .uncertain:
            let notice = (state == .queued ? "Queued for \(project). " : "Check \(project). ") + (reason ?? "")
            if !noteOnFollowUp(notice, about: shared.about) { say(notice, about: shared.about) }
        default:
            sending[request] = nil
            if asking?.about == shared.about {
                stopWorking()
                if restoreFollowed(saying: "Not sent. " + (reason ?? "")) { return }
                asking?.phase = .failed
            }
            say("Not sent. " + (reason ?? ""), about: shared.about)
        }
    }

    /// A session's answer was accepted and could not be shown, on this ink or as a card.
    func replyFailed(request: String, reason: String) {
        guard let shared = sending[request] else { return }
        say("Answer not shown. " + reason, about: shared.about)
    }

    /// Draws a working session's answer beside the ink it was about, on that ink's window, as the
    /// responder's answers are drawn: its marks point at the words they name, read from a fresh
    /// capture of the window, since the session has likely changed what the window shows. Answers
    /// false when the ink is gone or the window cannot be read, and the answer becomes a card.
    func showAnswer(request: String, _ answer: LiveAnswer, agent: String, done: @escaping (Bool) -> Void) {
        let person = marks.filter { !$0.agent && !answerMarks.contains($0.id) }
        guard let shared = sending[request], isOn else { return done(false) }
        let about = person.filter { shared.about.contains($0.id) }
        let asked = about.compactMap(\.shapeExtent).reduce(CGRect.null) { $0.union($1) }
        guard !asked.isNull else {
            Log.write("[live-ink] answer for \(request) has no ink to go beside")
            return done(false)
        }
        closeNote()
        // The ink leads, not the person's note: the notes follow it directly, so moving its content
        // moves the question and the reply together.
        let leader = about.last { $0.kind != .text }?.id ?? about.last?.id
        if asking?.picked != nil, asking?.about == shared.about, let said = asking?.say, var reply = marks.first(where: { $0.id == said.id }) {
            // The answer to the person's reply under an answer takes that reply's place, and the
            // earlier answer, with its checked button, stays until it is drawn. A notice about the
            // send has had its say.
            reply.notice = nil
            asking?.phase = .asking
            asking?.say = reply
            asking?.leader = leader
            asking?.leaderShift = leader.flatMap(windows.shift(of:))
        } else {
            removeAnswer()
            asking = AskState(phase: .asking, about: shared.about, leader: leader, leaderShift: leader.flatMap(windows.shift(of:)), session: shared)
        }
        let ui = Settings.shared.data.ui
        Task { @MainActor [weak self] in
            do {
                let packet = try await LivePacket.build(at: CGPoint(x: asked.midX, y: asked.midY), window: shared.windowID,
                                                        ink: person, style: ui.textStyle, markStyle: ui.markStyle)
                guard let self, self.asking?.about == shared.about else { return done(false) }
                self.sending[request] = nil
                self.stopWorking()
                self.answered(answer, packet: packet, sent: [], near: asked, question: self.question(in: shared.about), agent: agent)
                done(true)
            } catch {
                Log.write("[live-ink] error answer packet \(error)")
                self?.asking = nil
                done(false)
            }
        }
    }

    /// Vignette's own note beside the ink asked about, in the person's colour, replacing the last.
    /// With `about`, only while that ink is still the last asked about.
    private func say(_ words: String, about only: Set<Mark.ID>? = nil) {
        guard let about = asking?.about, only == nil || only == about else { return }
        removeAnswer()
        let near = shownMarks.filter { about.contains($0.id) }.compactMap(\.shapeExtent).reduce(CGRect.null) { $0.union($1) }
        guard !near.isNull else { showMarks(); return }
        let screen = activeSurfaces().map(\.overlay.globalFrame).first { $0.intersects(near) } ?? near
        let scene = LiveAnswerLayout.Scene(room: screen.insetBy(dx: 8, dy: 8), ink: ink, text: [])
        let note = LiveAnswerLayout.note(words.trimmingCharacters(in: .whitespaces), near: near, scene: scene,
                                         obstacles: scene.ink.compactMap(\.shapeExtent), sizes: answerSizes, byPerson: true)
        answerMarks.insert(note.id)
        drawingOn.insert(note.id)
        put([note], window: nil)
    }

    private static func image(_ png: Data) -> [String: Any] {
        ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]]
    }

    /// `question` is the person's note an answer replies to, which goes as the reply comes, so the
    /// answer need not keep clear of it.
    private func scene(for packet: LivePacket, leaving question: Mark? = nil) -> LiveAnswerLayout.Scene {
        scene(frame: packet.frame, page: packet.page, text: packet.lines.map { packet.global($0.box) }, leaving: question)
    }

    /// The window at `frame` with its text at `text`, both in global top-left points.
    private func scene(frame: CGRect, page: CGRect?, text: [CGRect], leaving question: Mark? = nil) -> LiveAnswerLayout.Scene {
        let screen = activeSurfaces().map(\.overlay.globalFrame).first { $0.intersects(frame) } ?? frame
        // A browser's page, not its tabs and toolbar: notes on those read as being about the browser.
        let room = (page ?? frame).intersection(screen).insetBy(dx: 8, dy: 8)
        let ink = self.ink.filter { $0.id != question?.id }
        let notes = ink.filter { $0.kind == .text }.compactMap { LiveAnswerLayout.noteBox($0, sizes: answerSizes) }
        return LiveAnswerLayout.Scene(room: room.isNull ? frame : room, ink: ink, text: text, notes: notes,
                                      screen: Self.visibleScreen(around: frame)?.insetBy(dx: 8, dy: 8))
    }

    /// The visible part of the screen `frame` is on, without the menu bar and the Dock, in global
    /// top-left points.
    private static func visibleScreen(around frame: CGRect) -> CGRect? {
        let centre = CGPoint(x: frame.midX, y: StateReport.primaryHeight - frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(centre) }) ?? NSScreen.main else { return nil }
        let visible = screen.visibleFrame
        return CGRect(x: visible.minX, y: StateReport.primaryHeight - visible.maxY, width: visible.width, height: visible.height)
    }

    /// The note the person asked with, among the marks `about`.
    private func question(in about: Set<Mark.ID>) -> Mark? {
        marks.last { about.contains($0.id) && !$0.agent && $0.kind == .text }
    }

    private func words(of note: Mark?) -> String? {
        if case .text(let text) = note?.geometry { text.text } else { nil }
    }

    /// The person's note goes as the reply that quotes it comes, in its place.
    private func replace(question: Mark?) {
        guard let question, marks.contains(where: { $0.id == question.id }) else { return }
        Log.write("[live-ink] question replaced by its reply")
        remove([question.id])
        showMarks()
    }

    /// The reply so far, as a popover hung from the ink, quoting the question. It keeps where it hangs,
    /// so it grows rather than jumping as words arrive.
    private func showSay(_ say: String, near asked: CGRect, question: Mark?, packet: LivePacket) {
        guard asking?.phase == .asking else { return }
        clearEarlierAnswer()
        let scene = scene(for: packet, leaving: question)
        let note: Mark
        if let shown = asking?.say {
            note = LiveAnswerLayout.grown(shown, to: say, sizes: answerSizes)
        } else {
            note = LiveAnswerLayout.reply(say, quote: words(of: question), from: asked, scene: scene, sizes: answerSizes)
            drawingOn.insert(note.id)
        }
        asking?.say = note
        answerMarks.insert(note.id)
        put([note], window: packet.windowID)
        replace(question: question)
    }

    /// `sent` is the ids of the text lines the answer was given, the only ones it may name.
    private func answered(_ answer: LiveAnswer, packet: LivePacket, sent: Set<String>, near asked: CGRect, question: Mark?,
                          agent: String = LiveAnswerLayout.agentName) {
        guard asking != nil else { return }
        clearEarlierAnswer()
        let targets = answer.marks.map { target(of: $0, in: packet, sent: sent) }
        let layout = LiveAnswerLayout.placed(for: answer, targets: targets, asked: asked,
                                             quote: words(of: question), scene: scene(for: packet, leaving: question), sizes: answerSizes, streamed: asking?.say,
                                             below: LiveAnswerActions.room(for: answer.actions), focusable: packet.windowID != nil)
        let placed = layout.marks.map { mark in
            var mark = mark
            if mark.agent { mark.agentName = agent }
            return mark
        }
        // The focus marks, each with its label, come in one at a time once the window is captured.
        let focus = Self.steps(in: Array(placed.dropFirst())).filter { $0.first?.focus != nil }
        let held = Set(focus.joined().map(\.id))
        let shown = placed.filter { !held.contains($0.id) }
        // A reply that streamed in is on the screen already, so only the rest draw themselves on.
        drawingOn.formUnion(shown.map(\.id).filter { $0 != asking?.say?.id })
        for mark in placed where mark.agent && mark.kind != .text {
            let behind = mark.shapeExtent.flatMap { packet.luminance?.mean(in: $0.insetBy(dx: -8, dy: -8)) }
            if let behind, behind <= LivePacket.Luminance.dark { overDark.insert(mark.id) }
        }
        asking?.phase = .answered
        asking?.say = placed.first
        asking?.actions = answer.actions
        asking?.picked = nil
        asking?.findings = layout.findings
        answerMarks.formUnion(shown.map(\.id))
        let labels = zip(answer.marks, targets).filter { $0.0.label != nil && $0.1 != nil }.count
        Log.write("[live-ink] drew answer marks=\(placed.count - 1) dropped=\(targets.filter { $0 == nil }.count) "
                  + "labels=\(layout.findings.filter { $0.count > 1 }.count)/\(labels)\(answer.steps ? " steps" : "")"
                  + (focus.isEmpty ? "" : " focus=\(focus.count)"))
        let groups = Self.steps(in: Array(placed.dropFirst()))
        defer { replace(question: question) }
        guard answer.steps, groups.count > 1 else {
            put(shown, window: packet.windowID)
            pullFocus(focus, window: packet.windowID, say: answer.say, replies: layout.tour)
            return
        }
        steps = Array(groups.dropFirst())
        stepsWindow = packet.windowID
        // `placed(for:)` places one pointing mark for each target found, in order.
        let pointers = groups.compactMap(\.first)
        stepTargets = Dictionary(uniqueKeysWithValues: zip(pointers, targets.compactMap { $0 }).compactMap { mark, target in
            mark.shapeExtent.map { (mark.id, (target, $0.origin)) }
        })
        put([placed[0]] + groups[0], window: packet.windowID)
        watchStepClicks()
    }


    /// An answer's marks after its reply, as steps: each pointing mark with the labels after it.
    private static func steps(in marks: [Mark]) -> [[Mark]] {
        var groups: [[Mark]] = []
        for mark in marks {
            if mark.kind == .text, !groups.isEmpty { groups[groups.count - 1].append(mark) } else { groups.append([mark]) }
        }
        return groups
    }

    /// Hears clicks anywhere while steps wait, since the click on a step goes to the app under it.
    private func watchStepClicks() {
        guard stepClicks == nil else { return }
        stepClicks = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            let point = event.cgEvent?.location ?? .zero
            MainActor.assumeIsolated { self?.clicked(at: point) }
        }
    }

    private func stopSteps() {
        steps = []
        stepsWindow = nil
        stepTargets = [:]
        if let stepClicks { NSEvent.removeMonitor(stepClicks) }
        stepClicks = nil
    }

    /// The step on the screen is the answer's pointing mark that shows; a click in it lets the app
    /// answer the click first, then takes the step off and draws the next.
    private func clicked(at point: CGPoint) {
        guard stepClicks != nil, !isInking else { return }
        let shown = shownMarks.filter { answerMarks.contains($0.id) && $0.agent && $0.kind != .text }
        guard let current = shown.last else { return }
        let pointedAt = stepTargets[current.id].flatMap { step in
            current.shapeExtent.map { step.target.offsetBy(dx: $0.minX - step.at.x, dy: $0.minY - step.at.y).insetBy(dx: -6, dy: -6) }
        }
        guard Self.stepTarget(of: current).contains(point) || pointedAt?.contains(point) == true else { return }
        let done = shownMarks.filter { answerMarks.contains($0.id) && $0.kind == .text && $0.id != asking?.say?.id }.map(\.id) + [current.id]
        // The last step goes too once it is clicked, and the reply stays.
        let next = steps.isEmpty ? [] : steps.removeFirst()
        let window = stepsWindow
        if next.isEmpty { stopSteps() }
        Log.write("[live-ink] step done; \(next.isEmpty ? 0 : steps.count + 1) to go")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stepPause) { [weak self] in
            guard let self, self.answerMarks.contains(current.id) else { return }
            self.answerMarks.subtract(done)
            self.remove(Set(done))
            self.showMarks()
            guard !next.isEmpty else { return }
            self.answerMarks.formUnion(next.map(\.id))
            self.drawingOn.formUnion(next.map(\.id))
            self.put(next, window: window)
        }
    }

    /// How long the app gets to answer a step's click before the next step draws.
    private static let stepPause: TimeInterval = 0.35

    /// Where a click counts as taking a step: inside its loop, or on what its arrow points at, just
    /// past its head.
    private static func stepTarget(of mark: Mark) -> CGRect {
        switch mark.geometry {
        case .arrow(let arrow):
            let length = max(1, hypot(arrow.end.x - arrow.start.x, arrow.end.y - arrow.start.y))
            let ahead = CGPoint(x: arrow.end.x + (arrow.end.x - arrow.start.x) / length * 24,
                                y: arrow.end.y + (arrow.end.y - arrow.start.y) / length * 24)
            return CGRect(origin: ahead, size: .zero).insetBy(dx: -32, dy: -32)
        default:
            return (mark.shapeExtent ?? .null).insetBy(dx: -6, dy: -6)
        }
    }

    // MARK: Pulling focus

    /// The agent pulling focus: an answer's focus marks, each with its label, shown one stop at a time.
    private struct FocusRun {
        let id = UUID()
        var stops: [[Mark]]
        let holds: [TimeInterval]
        let window: CGWindowID
        /// Where the reply hangs at each stop after the first, by the stop's focus mark's id.
        let replies: [Mark.ID: PopoverPlace]
        var index = -1
        var timer: Timer?
        var watch: [Any] = []
        /// The pointer when the focus came in, in AppKit's global coordinates.
        var origin: CGPoint?
    }

    /// Captures the window the answer is on and pulls focus to each of `stops` in turn, for as long as
    /// the reply's sentence about it takes to read (`Focus.holds`).
    private func pullFocus(_ stops: [[Mark]], window: CGWindowID?, say: String, replies: [Mark.ID: PopoverPlace]) {
        letGoOfFocus(because: "replaced")
        guard !stops.isEmpty else { return }
        guard let window else {
            Log.write("[live-ink] focus skipped: the answer is on no window; drawn as circles")
            return showUnfocused(stops, window: nil)
        }
        let run = FocusRun(stops: stops, holds: Focus.holds(for: say, stops: stops.count), window: window, replies: replies)
        focusRun = run
        let zooms = stops.compactMap { $0.first?.focus?.zoom }
        let rack = zooms.contains(false), loupe = zooms.contains(true)
        let started = Date()
        Task { @MainActor [weak self] in
            do {
                let capture = try await LivePacket.capture(window: window)
                let picture = await Task.detached(priority: .userInitiated) {
                    FocusPicture.make(capture.image, frame: capture.frame, rack: rack, loupe: loupe)
                }.value
                guard let self, self.focusRun?.id == run.id else { return }
                guard let picture else {
                    self.focusRun = nil
                    Log.write("[live-ink] error focus picture; drawn as circles")
                    return self.showUnfocused(stops, window: window)
                }
                Log.write("[live-ink] focus ready ms=\(Int(Date().timeIntervalSince(started) * 1000)) stops=\(stops.count)")
                self.focusRun?.stops = stops.map { stop in
                    stop.map { mark in
                        var mark = mark
                        mark.focus?.show(picture)
                        return mark
                    }
                }
                self.nextFocus()
            } catch {
                Log.write("[live-ink] error focus \(error); drawn as circles")
                guard let self, self.focusRun?.id == run.id else { return }
                self.focusRun = nil
                self.showUnfocused(stops, window: window)
            }
        }
    }

    /// Focus could not be pulled, so each stop shows at once as a circle round its target, with its
    /// label, rather than not at all. A stop keeps its id, which the answer's actions name.
    private func showUnfocused(_ stops: [[Mark]], window: CGWindowID?) {
        let marks = stops.joined().map { mark -> Mark in
            guard let focus = mark.focus else { return mark }
            var circle = mark
            circle.geometry = LiveAnswerLayout.circle(around: focus.target)
            circle.focus = nil
            return circle
        }
        answerMarks.formUnion(marks.map(\.id))
        drawingOn.formUnion(marks.map(\.id))
        put(marks, window: window)
    }

    /// Shows the next stop, and lets the one before go once the new one is mostly in, so the old target
    /// blurs and then the new one sharpens. The reply moves to hang from each stop, and the window's
    /// other marks fade (`lightStop`). After the last stop, lets go.
    private func nextFocus() {
        guard var run = focusRun else { return }
        let previous = run.index >= 0 ? run.stops[run.index] : []
        run.index += 1
        guard run.index < run.stops.count else { return letGoOfFocus(because: "read") }
        let stop = run.stops[run.index]
        run.origin = run.origin ?? NSEvent.mouseLocation
        run.timer = Timer.scheduledTimer(withTimeInterval: run.holds[run.index], repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.nextFocus() }
        }
        focusRun = run
        answerMarks.formUnion(stop.map(\.id))
        drawingOn.formUnion(stop.map(\.id))
        if let place = stop.first.flatMap({ run.replies[$0.id] }), var reply = asking?.say, case .text(var words) = reply.geometry,
           answerMarks.contains(reply.id) {
            words.origin = place.body.origin
            reply.geometry = .text(words)
            reply.popover = place
            asking?.say = reply
            put(stop + [reply], window: run.window)
        } else {
            put(stop, window: run.window)
        }
        lightStop(stop, leaving: previous, on: run.window)
        Log.write("[live-ink] focus stop=\(run.index + 1)/\(run.stops.count) zoom=\(stop.first?.focus?.zoom ?? false) hold=\(String(format: "%.1f", run.holds[run.index]))")
        watchFocus()
        guard !previous.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Focus.fade * Focus.overlap * Settings.shared.motionScale) { [weak self] in
            self?.dropFocus(previous)
        }
    }

    /// Lets the focus go: the stop on the screen fades out, and the rest of the tour is dropped.
    private func letGoOfFocus(because reason: String) {
        guard let run = focusRun else { return }
        focusRun = nil
        run.timer?.invalidate()
        run.watch.forEach(NSEvent.removeMonitor)
        if run.stops.indices.contains(run.index) { dropFocus(run.stops[run.index]) }
        let all = Set(windows.marks.filter { $0.window == run.window }.map(\.mark.id))
        windows.light(all, among: all)
        Log.write("[live-ink] focus let go because=\(reason)")
    }

    /// While a stop shows, the window's other marks fade to a fifth, so nothing else draws the eye:
    /// all but the stop, the reply, and the person's ink on the stop's target or round it. Ink that
    /// only grazes the target, as a loop round the line below does, fades. The stop `leaving` keeps
    /// its strength, since it is handing over to this one.
    private func lightStop(_ stop: [Mark], leaving: [Mark], on window: CGWindowID) {
        let shown = windows.marks.filter { $0.window == window }.map(\.mark)
        let ids = Set(stop.map(\.id))
        let target = shown.first { ids.contains($0.id) }?.focus?.target ?? .null
        let handing = Set(leaving.map(\.id))
        let onTarget = { (ink: CGRect) in
            target.insetBy(dx: -8, dy: -6).contains(CGPoint(x: ink.midX, y: ink.midY)) || ink.contains(CGPoint(x: target.midX, y: target.midY))
        }
        let lit = shown.filter { mark in
            ids.contains(mark.id) || handing.contains(mark.id) || mark.id == asking?.say?.id
                || (!mark.agent && !answerMarks.contains(mark.id) && mark.shapeExtent.map(onTarget) == true)
        }
        windows.light(Set(lit.map(\.id)), among: Set(shown.map(\.id)))
    }

    private func dropFocus(_ stop: [Mark]) {
        let ids = Set(stop.map(\.id)).intersection(answerMarks)
        guard !ids.isEmpty else { return }
        answerMarks.subtract(ids)
        remove(ids)
        showMarks()
    }

    /// Lets the focus go when the person takes over: a key, a click, a scroll, or the pointer moving
    /// `Focus.pointerReach` from where it was when the focus came in.
    private func watchFocus() {
        guard var run = focusRun, run.watch.isEmpty else { return }
        let heard: (NSEvent) -> Void = { [weak self] event in MainActor.assumeIsolated { self?.focusHeard(event) } }
        let kinds: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .mouseMoved]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: heard) { run.watch.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: kinds, handler: { heard($0); return $0 }) { run.watch.append(local) }
        focusRun = run
    }

    private func focusHeard(_ event: NSEvent) {
        guard let run = focusRun, run.index >= 0 else { return }
        switch event.type {
        case .mouseMoved:
            let mouse = NSEvent.mouseLocation
            guard let origin = run.origin, hypot(mouse.x - origin.x, mouse.y - origin.y) > Focus.pointerReach else { return }
            letGoOfFocus(because: "pointer")
        case .keyDown: letGoOfFocus(because: "key")
        case .scrollWheel: letGoOfFocus(because: "scroll")
        default: letGoOfFocus(because: "click")
        }
    }

    /// Where an answer's mark points, in global top-left points: a line, the words within it that the
    /// mark names, or its box. Words Vision gives no box for fall back to the line. Words with no line
    /// in `sent`, as a session names them or the responder names text it was not sent, are looked for
    /// in every line, the first that has them all winning. Ids run in reading order over every line,
    /// so a guessed id would name a line the answer never saw.
    private func target(of mark: AnswerMark, in packet: LivePacket, sent: Set<String>) -> CGRect? {
        let named = mark.line.flatMap { id in sent.contains(id) ? packet.lines.first { $0.id == id } : nil }
        let line = named ?? mark.words.flatMap { words in
            packet.lines.first { $0.recognized.string.range(of: words, options: [.caseInsensitive]) != nil }
                ?? Self.loose(words).flatMap { key in packet.lines.first { Self.loose($0.recognized.string)?.contains(key) == true } }
        }
        if let line {
            if let words = mark.words, let range = line.recognized.string.range(of: words, options: [.caseInsensitive]),
               let box = try? line.recognized.boundingBox(for: range)?.boundingBox {
                return packet.global(CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
            }
            return packet.global(line.box)
        }
        return mark.box.map(packet.global)
    }

    /// Letters and digits only, lowercased, so words still match a line Vision read with other
    /// punctuation or spacing.
    private static func loose(_ text: String) -> String? {
        let kept = String(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
        return kept.isEmpty ? nil : kept
    }

    /// The note says why beside the ink, in the person's colour, since Vignette says it, not the agent.
    private func failed(_ failure: LiveResponder.Failure) {
        letGoOfNote(into: nil)
        guard asking != nil else { return }
        Log.write("[live-ink] error ask \(failure.detail)")
        stopWorking()
        if restoreFollowed(saying: failure.reason) { return }
        asking?.phase = .failed
        asking?.reason = failure.reason
        say(failure.reason)
    }

    /// A follow-up that failed leaves the answer it was sent from as it was: its buttons come back,
    /// typed words wait in Reply again, and the reply's header says why in place of their words.
    /// False when no follow-up of the answer on screen is under way.
    @discardableResult
    private func restoreFollowed(saying reason: String) -> Bool {
        guard let followed, var reply = followingReply else { return false }
        self.followed = nil
        reply.quote = nil
        reply = noticed(reply, reason)
        var answer = followed.state
        answer.say = reply
        answer.reason = reason
        if followed.pick == .reply { answer.draft = followed.words }
        asking = answer
        Log.write("[live-ink] follow-up failed; its answer stays draft=\(answer.draft.count)")
        hideActions()
        put([reply], window: windows.window(of: reply.id))
        showMarks()
        return true
    }

    /// Vignette's word on a follow-up's send that may still arrive, queued or not confirmed: it goes
    /// in the reply's header, and the answer stays as the follow-up left it. False when no follow-up
    /// of the answer on screen is under way.
    private func noteOnFollowUp(_ notice: String, about only: Set<Mark.ID>) -> Bool {
        guard asking?.about == only, let reply = followingReply else { return false }
        let shown = noticed(reply, notice)
        asking?.say = shown
        Log.write("[live-ink] follow-up notice in the reply's header")
        put([shown], window: windows.window(of: shown.id))
        showMarks()
        return true
    }

    /// The reply a follow-up under way was sent from, while it is the answer on screen.
    private var followingReply: Mark? {
        guard let id = followed?.state.say?.id, asking?.say?.id == id else { return nil }
        return marks.first { $0.id == id }
    }

    /// `reply` with `notice` in its header in place of its quote, grown to fit it.
    private func noticed(_ reply: Mark, _ notice: String) -> Mark {
        guard case .text(let text) = reply.geometry else { return reply }
        var reply = reply
        reply.notice = notice
        return LiveAnswerLayout.grown(reply, to: text.text, sizes: answerSizes, foot: reply.popover?.foot ?? .zero)
    }

    /// Adds an answer's marks, or Vignette's own note, replacing marks of the same id. They go on the
    /// window the ask was about, or the window the ink asked about is on, beside that ink: when its
    /// content moved since the ask, they move with it and follow it, and otherwise each mark is
    /// anchored to what it points at, a label follows the mark it names, and a note follows the ink.
    /// A mark that followed the ink drifted off its target when the session's edit moved the content
    /// under the ink. With no window they go on the active Space's surfaces.
    private func put(_ placed: [Mark], window windowID: CGWindowID?) {
        let leader = asking?.leader.flatMap { id in windows.window(of: id).map { (id: id, window: $0) } }
        let target = (windowID ?? leader?.window).flatMap(windows.target(id:))
        let active = activeSurfaces()
        let markStyle = Settings.shared.data.ui.markStyle
        var moved = CGVector.zero
        if let leader, leader.window == target?.id, let then = asking?.leaderShift, let now = windows.shift(of: leader.id) {
            moved = CGVector(dx: now.dx - then.dx, dy: now.dy - then.dy)
        }
        let still = leader.map { windows.isShown($0.id) && moved == .zero } ?? true
        // A reply follows the mark it hangs from, so it is pinned after it.
        let ids = Set(placed.map(\.id))
        let hangs = { (mark: Mark) in mark.popover?.anchor.map(ids.contains) ?? false }
        // The mark a label names comes just before it.
        var labelled: Mark.ID?
        for mark in placed.filter({ !hangs($0) }) + placed.filter(hangs) {
            remove([mark.id])
            if let target {
                let mark = LiveWindows.translated(mark, by: moved)
                let anchor: LiveWindows.Anchor
                if let hung = mark.popover?.anchor, ids.contains(hung) {
                    anchor = .follows(hung)
                } else if mark.isLabel, still, let labelled {
                    anchor = .follows(labelled)
                } else if let leader, leader.window == target.id, !still || mark.kind == .text {
                    anchor = .follows(leader.id)
                } else {
                    anchor = .at(LiveWindows.anchorPoint(of: mark))
                }
                if mark.kind != .text { labelled = mark.id }
                windows.pin(mark, to: target, anchor: anchor)
                continue
            }
            let centre = mark.shapeExtent ?? LiveAnswerLayout.noteBox(mark, sizes: answerSizes) ?? .zero
            let home = active.first { $0.overlay.globalFrame.contains(CGPoint(x: centre.midX, y: centre.midY)) } ?? active.first
            if let home { add(mark, on: home, among: active, markStyle: markStyle) }
        }
        showMarks()
        closeEmpty(fade: LiveMarksLayer.removalFade)
    }

    /// Takes the last answer's marks, or the last failure's note, off the screen, all but `kept`.
    private func removeAnswer(keeping kept: Mark.ID? = nil) {
        followed = nil
        stopSteps()
        letGoOfFocus(because: "replaced")
        hideActions()
        let gone = answerMarks.filter { $0 != kept }
        guard !gone.isEmpty else { return }
        remove(gone)
        answerMarks.subtract(gone)
    }

    /// A follow-up's answer has come: the earlier answer goes, its buttons too, all but the reply,
    /// whose words it replaces where it hangs.
    private func clearEarlierAnswer() {
        followed = nil
        guard let reply = asking?.say?.id else { return }
        removeAnswer(keeping: reply)
    }

    /// Ends the responder's conversation and forgets what was asked, as clearing the screen does.
    private func endConversation() {
        closeNote()
        stopListening()
        spoken = nil
        strokeTimes = [:]
        letGoOfNote(into: nil)
        responder.stop()
        asked = []
        letGoOfFocus(because: "cleared")
        answerMarks = []
        followed = nil
        stopSteps()
        stopWorking()
        finishing = [:]
        prepared = nil
        sending = [:]
        lastPicture = nil
        asking = nil
    }

    // MARK: Inking

    private func chordChanged(_ change: HeldChord.Change) {
        switch change {
        case .began:
            guard mayInk() else {
                Log.write("[live-ink] not inking: the stack or the annotator is up")
                return
            }
            closeNote()
            listening?.pressedAgain()
            responder.prepare()
            startInking()
        case .ended:
            guard isInking else { return }
            if inking.contains(where: \.overlay.isTracking) { watchRelease() } else { finishInking() }
        }
    }

    private func startInking() {
        isInking = true
        letGoOfFocus(because: "ink")
        drewWhileInking = false
        // Pressed again before the button came up: the stroke now ends without ending the inking.
        releaseWatch?.invalidate()
        releaseWatch = nil
        inking = activeSurfaces()
        inking.forEach { $0.overlay.setInking(true) }
        let mouse = NSEvent.mouseLocation
        hover(at: CGPoint(x: mouse.x, y: StateReport.primaryHeight - mouse.y))
        // The glow waits, so holding the chord on the way to a key, as in a window manager's
        // Control-Option-arrow, does not flash it. A press shows it at once.
        glowTimer?.invalidate()
        glowTimer = Timer.scheduledTimer(withTimeInterval: Settings.shared.data.ui.liveInkGlowDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showGlow(true) }
        }
        Log.write("[live-ink] inking")
    }

    private func stopInking() {
        hover(at: nil)
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
        if !points.isEmpty, strokeBegan == nil { strokeBegan = Date() }
        // A press that moves is drawing, not tapping.
        if let first = points.first, let last = points.last, hypot(last.x - first.x, last.y - first.y) > 4 { hover(at: nil) }
        let markStyle = Settings.shared.data.ui.markStyle
        inking.forEach { $0.overlay.showPen(points, markStyle: markStyle) }
    }

    private func strokeEnded(_ points: [CGPoint], on surface: Surface) {
        let before = newInk.count
        take(points, on: surface, among: inking)
        strokeBegan = nil
        if newInk.count > before, let extent = newInk.last?.shapeExtent { prefetch(at: CGPoint(x: extent.midX, y: extent.midY)) }
        // The mark the preview was on has gone, or a stroke was drawn; the next move shows it again.
        hover(at: nil)
        if releaseWatch != nil { finishInking() }
    }

    /// The chord was let go: inking stops, and ink drawn while it was held gets the note.
    private func finishInking() {
        stopInking()
        if drewWhileInking || listening != nil, !newInk.isEmpty { openNote() }
        drewWhileInking = false
        // What is said goes into the note; with no note there is nowhere for it to go.
        if note != nil { listening?.released() } else { stopListening() }
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
                self.finishInking()
            }
        }
    }

    private func showGlow(_ on: Bool) {
        glowTimer?.invalidate()
        if on { listen() }
        if !on && !glowing { return }
        glowing = on
        let ui = Settings.shared.motionUI
        let color = ui.markStyle.color(.person)
        let mouse = NSEvent.mouseLocation
        let pen = CGPoint(x: mouse.x, y: StateReport.primaryHeight - mouse.y)
        inking.forEach { $0.overlay.showGlow(on, ui: ui, color: color, pen: pen) }
    }

    // MARK: Listening

    /// Starts listening, with speech on, as the glow shows: the chord on its way to a shortcut shows no
    /// glow, so it never turns the microphone on either.
    private func listen() {
        guard listening == nil else { return }
        let settings = Settings.shared.data
        guard settings.liveInkSpeech else { return }
        guard SpeechPermission.granted else {
            Log.write("[speech] not listening: the microphone or speech recognition is not allowed")
            return
        }
        guard let transcriber = SpeechEngine.make() else {
            Log.write("[speech] error no recognizer for \(Locale.current.identifier)")
            return
        }
        let listening = LiveListening(transcriber: transcriber, until: settings.listenUntil,
                                      pause: settings.ui.liveInkSpeechPause, quiet: Float(settings.ui.liveInkSpeechQuiet))
        listening.onWords = { [weak self] words in self?.heard(words) }
        listening.onFinished = { [weak self, weak listening] words in
            guard let self, let listening, self.listening === listening else { return }
            self.doneListening(words, began: listening.began)
        }
        do {
            try listening.start()
            self.listening = listening
            typedOver = false
        } catch let failure as TranscriberFailure {
            Log.write("[speech] error \(failure.detail)")
        } catch {
            Log.write("[speech] error \(error)")
        }
    }

    private func heard(_ words: [SpokenWord]) {
        guard !typedOver else { return }
        note?.hear(LiveListening.text(of: words))
    }

    /// Listening ended by itself: the final words replace the partial ones, and the ask goes when the
    /// person stopped talking, if that is how it sends.
    private func doneListening(_ words: [SpokenWord], began: Date) {
        listening = nil
        guard let note else { return }
        note.setListening(false)
        let text = LiveListening.text(of: words)
        guard !typedOver, !text.isEmpty else { return }
        spoken = (words, began)
        note.hear(text)
        if Settings.shared.data.liveInkSendWhenQuiet { note.send() }
    }

    /// A key typed in the note takes over from speech: listening ends, and the words stay the
    /// person's to edit.
    private func typedInNote() {
        spoken = nil
        guard let listening, !typedOver else { return }
        typedOver = true
        listening.finish()
    }

    /// Stops listening and drops what was heard.
    private func stopListening() {
        listening?.cancel()
        listening = nil
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
            overlay.onHover = { [weak self] point in self?.hover(at: point) }
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
        let ui = Settings.shared.data.ui
        let pulsing = asking.map { [.looking, .asking, .working].contains($0.phase) ? $0.about : [] } ?? []
        overDark.formIntersection(answerMarks)
        let ids = Set(marks.map(\.id))
        hands = hands.filter { ids.contains($0.key) }
        for surface in surfaces {
            surface.overlay.show(surface.marks, markStyle: ui.markStyle, textStyle: ui.textStyle, drawingOn: drawingOn, pulsing: pulsing,
                                 finishing: finishing, overDark: overDark, hands: hands)
        }
        windows.show(markStyle: ui.markStyle, textStyle: ui.textStyle, drawingOn: drawingOn, pulsing: pulsing, finishing: finishing,
                     overDark: overDark, hands: hands)
        drawingOn = []
        // Watched while the reply is out of sight too, as when its window is minimized, so its × and
        // buttons come back when it fades back in.
        if let say = asking?.say, answerMarks.contains(say.id) {
            watchPointer()
            pointerMoved()
        } else {
            stopWatchingPointer()
        }
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
