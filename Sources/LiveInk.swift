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
    /// Runs out the pointer field's delay after the chord goes down.
    private var fieldTimer: Timer?
    /// The chord shows the pointer field on the surfaces taking ink: its delay passed, or a press came.
    private var chordShowsField = false
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
    /// The working sessions Send can reach, newest first, as the candidates found so far: once from
    /// the kept lists, then again as each client's fresh answer arrives.
    var listSessions: ((@escaping (DestinationChoice.Candidates) -> Void) -> Void)?
    /// Sends a note to a session through today's Send, as the card it becomes, and answers on the
    /// main thread with the request's id, or why it was refused.
    var sendNote: ((NoteCard, AgentDestination, String,
                    @escaping (Result<String, ScreenshotRequests.Refusal>) -> Void) -> Void)?
    /// Withdraws a note sent to a session that is still in its grace (Don't send), by its request id.
    var unsendNote: ((String) -> Void)?
    /// The × that dismisses an answer, shown while the pointer is over its note, and the ask it ends.
    private var dismissButton: LiveDismissButton?
    private var dismissing: LiveAsks.Ask.ID?
    /// Each answer's actions, under its reply while it is on the screen, by its ask.
    private var actionsPanels: [LiveAsks.Ask.ID: LiveAnswerActions] = [:]
    private var pointerWatch: [Any] = []
    private var replyWatch: NSObjectProtocol?
    private var focusRun: FocusRun?
    /// The packet for the ink the note is open on, captured when it opened, so its text can move
    /// the note clear of the window's text and the ask need not capture again.
    private var prepared: (ink: Set<Mark.ID>, plan: LivePacket.Plan, packet: Task<LivePacket, Error>, glance: Task<LivePacket.Glance?, Never>)?
    /// A mark was drawn since the chord went down, so letting it go opens the note.
    private var drewWhileInking = false
    /// A key or another modifier cut the chord short, as the start of a shortcut.
    private var chordInterrupted = false
    /// The note on the ink no ask has been about, while there is some (`keepNoteWithItsInk`).
    private var note: LiveNotePopover?
    /// Where the note hangs, in global top-left points, from the mark its `anchor` names.
    private var notePlace: PopoverPlace?
    /// Listening to the person while they draw, with speech on. It can span several presses of the
    /// chord, so "this" and "that" drawn in two strokes are one note.
    private var listening: LiveListening?
    /// The note's words are the person's to keep: typed, or in the note before this listening began, so
    /// what they say no longer replaces them.
    private var typedOver = false
    /// The final words of the last listening, while the note holds them as they were said, and when
    /// that listening began, which their times count from.
    private var spoken: (words: [SpokenWord], began: Date)?
    /// When the stroke under way began.
    private var strokeBegan: Date?
    /// The diagonal of the screen the stroke under way began on, which sets how much line it keeps.
    private var strokeScreenDiagonal: CGFloat?
    /// When each of the person's strokes was drawn, so a spoken note can say which "this" is which.
    private var strokeTimes: [Mark.ID: (began: Date, ended: Date)] = [:]
    /// Each note asked in, by its ask, on screen until the conversation has taken its place, or until
    /// it fades with nothing to take it.
    private var handing: [LiveAsks.Ask.ID: LiveNotePopover] = [:]
    /// The conversation that takes a note's place, once the note has settled into its look.
    private var handingTo: [LiveAsks.Ask.ID: Mark.ID] = [:]
    /// Who each ask goes to: the agent, and how the conversation's row names it.
    private var answerers: [LiveAsks.Ask.ID: (agent: String, name: String?)] = [:]
    /// What each ask to the responder sends, from when its packet came until the asks before it end
    /// (`LiveAsks.Effect.send`).
    private var held: [LiveAsks.Ask.ID: LiveResponder.Ask] = [:]
    /// Esc, held while `LiveEscape` has a step for it.
    private var escapeKey: HotKey?
    /// The note's target picked last, which the next note starts on.
    private var lastTarget: LiveNotePopover.Target = .responder
    /// The target the open note started on, for `SendContext`.
    private var noteOffered: LiveNotePopover.Target?
    /// The asks since the screen was last cleared, and each mark's part in them.
    private var asks = LiveAsks()
    /// An answer's steps still to show, each a mark and its label, and the window they go on. One is
    /// on the screen, and a click on it shows the next, while `stepClicks` listens.
    private var steps: [[Mark]] = []
    private var stepsAsk: LiveAsks.Ask.ID?
    private var stepsWindow: CGWindowID?
    /// The steps answer a picture of an area, so each goes on the window under it.
    private var stepsOnTheirWindows = false
    /// What each step's mark points at, and where the mark was then, so a click on the thing counts
    /// as well as one on the mark, wherever its window has moved it since.
    private var stepTargets: [Mark.ID: (target: CGRect, at: CGPoint)] = [:]
    private var stepClicks: Any?
    /// The picture the responder's conversation has, and the ids of the text lines sent with it, so a
    /// follow-up about the same window, showing the same text, sends no picture and only the lines
    /// near its ink not sent yet.
    private var lastPicture: (conversation: Int, subject: LivePacket.Subject, text: String, lines: Set<String>)?
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

    /// A note going to a session: the picture the session is sent, and the card the note becomes,
    /// the window without the ink, with the ink and the words as its drawing.
    struct NoteCard {
        let picture: Data
        let capture: CGImage
        /// In `capture`'s pixels, with sizes in points of `pointScale`.
        let marks: [Mark]
        let pointScale: CGFloat
        /// The window the note was on, nil for a note of no one window, and where its ink was, in
        /// global top-left points, which a result card is captured round.
        let window: CGWindowID?
        let ink: CGRect
        /// How the window looked round the ink, which the window is compared with when the turn ends.
        let before: LiveNoteCards.Before?
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

    /// The marks on screen now, the person's in the order they were drawn: a mark on a window is left
    /// out while its window is away, minimised or set aside.
    private var shownMarks: [Mark] {
        inDrawnOrder(windows.marks.filter(\.shown).map(\.mark) + screenMarks)
    }

    /// `marks` with the person's in the order they were drawn, and the rest after them in the order
    /// given. The windows' marks come window by window, in no order, so ink across windows is put back
    /// in the order drawn, which numbers it and makes the newest the one an ask's answer and the note
    /// stay beside.
    private func inDrawnOrder(_ marks: [Mark]) -> [Mark] {
        let drawn = { (index: Int) in self.strokeTimes[marks[index].id]?.began ?? .distantFuture }
        return marks.indices.sorted { (drawn($0), $0) < (drawn($1), $1) }.map { marks[$0] }
    }

    /// Set-aside marks that were on no window (`setAside`), which come back from here.
    private var asideOnScreen: [Mark] = []
    private var screenMarks: [Mark] {
        var seen = Set<Mark.ID>()
        return surfaces.flatMap(\.marks).filter { seen.insert($0.id).inserted }
    }

    init(mayInk: @escaping () -> Bool) {
        self.mayInk = mayInk
        windows.onGone = { [weak self] ids in self?.forget(ids) }
        windows.drawnExtent = { [weak self] mark in self.flatMap { Self.drawnExtent(of: mark, sizes: $0.answerSizes) } }
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.bringNoteBack()
                self?.holdEscape()
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
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
            if isInking { stopInking(because: "live ink turned off") }
            stopWatchingForWindowPicker()
            endConversation()
            chord = nil
            for (center, observer) in observers { center.removeObserver(observer) }
            observers = []
            surfaces.forEach { $0.marks = [] }
            asideOnScreen = []
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
        asideOnScreen = []
        windows.removeAll()
        endConversation()
        showMarks()
        closeEmpty(fade: LiveMarksLayer.removalFade)
        Log.write("[live-ink] cleared \(count)")
        return count
    }

    /// The stack or the annotator is coming up under the raised overlays: inking stops, the stroke
    /// under way is dropped, and the chord must be pressed again to ink. The note hides, with its words,
    /// until they are gone (`bringNoteBack`).
    func standAside() {
        if let note, !note.standsAside {
            note.standAside(true)
            Log.write("[live-ink] note hidden: the stack or the annotator is up")
        }
        stopListening()
        guard isInking else { return }
        stopInking(because: "the stack or the annotator is up")
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

    /// The note hidden by `standAside` shows again, without the keys, once the stack and the annotator
    /// are gone. The main run loop asks before each wait, as it does `holdEscape`, so the note follows
    /// whatever closed them.
    private func bringNoteBack() {
        guard let note, note.standsAside, mayInk() else { return }
        note.standAside(false)
        Log.write("[live-ink] note back: the screen is free")
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

    /// The marks and the pointer field drawn again in the current settings.
    func applyTweaks() {
        windows.restyle()
        showMarks()
        holdField()
    }

    /// How far past a stroke's edge a tap still erases it. Wider than the editor's hit margin: nothing
    /// shows which mark a tap would erase, and while inking a tap does nothing else.
    nonisolated static let eraseReach: CGFloat = 12

    /// The index of the mark a tap at `point` erases: the topmost note it is on, or whose stroke it is
    /// near, or else the smallest ellipse it is inside, since a circled thing is where a hand goes to
    /// take the circle off. `noteBox` gives what a note draws, an agent's badge included, so a tap on
    /// the badge or beside it erases the note, as generous as `eraseReach`.
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
            "note": note?.globalFrame.map { [$0.minX, $0.minY, $0.width, $0.height].map { Int($0.rounded()) } } ?? NSNull(),
            "noteKeys": note?.hasKeys ?? false,
            "noteSessions": note?.sessionCount ?? NSNull(),
            "noteTargetSession": note?.target.session?.id ?? NSNull(),
            "noteShown": note?.isShown ?? false,
            "actions": newestPanel.map { panel -> Any in
                panel.buttons.map { ["title": $0.title, "frame": [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height].map { Int($0.rounded()) },
                                     "enabled": $0.enabled, "picked": $0.picked] }
            } ?? NSNull(),
            "replyField": newestPanel?.fieldFrame.map { [$0.minX, $0.minY, $0.width, $0.height].map { Int($0.rounded()) } } ?? NSNull(),
            "replyCancel": newestPanel?.cancelFrame.map { [$0.minX, $0.minY, $0.width, $0.height].map { Int($0.rounded()) } } ?? NSNull(),
            "dismiss": dismissButton.map { button -> Any in StateReport.topLeft(button.frame, primaryHeight: StateReport.primaryHeight) } ?? NSNull(),
            "noteTarget": note.map { panel -> Any in panel.target == .responder ? "responder" : "session" } ?? NSNull(),
            "responder": responder.stateJSON,
            "escape": LiveEscape.next(escapeSnapshot)?.rawValue ?? NSNull(),
            "escapeHeld": escapeKey != nil,
            "ask": asks.newest.map(Self.json(of:)) ?? NSNull(),
            "asks": asks.asks.map(Self.json(of:)),
            "queued": asks.queued.count,
        ]
    }

    private static func json(of ask: LiveAsks.Ask) -> [String: Any] {
        var json: [String: Any] = ["id": ask.id, "phase": ask.phase.rawValue, "about": ask.about.count, "picture": ask.picture,
                                   "toSession": ask.toSession]
        if let reason = ask.reason { json["reason"] = reason }
        if let say = ask.say, case .text(let text) = say.geometry { json["sayLength"] = text.text.count }
        return json
    }

    /// The buttons of the newest answer that has them.
    private var newestPanel: LiveAnswerActions? {
        asks.asks.reversed().lazy.compactMap { self.actionsPanels[$0.id] }.first
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

    /// Records when `mark` was drawn: from the stroke's first move to now, and that it is the note's
    /// ink. With the stroke's `points`, it also records the hand that drew it, and the mark eases onto
    /// its shape from them.
    private func stroked(_ mark: Mark, by points: [CGPoint]? = nil) {
        strokeTimes[mark.id] = (strokeBegan ?? Date(), Date())
        _ = asks.reduce(.drew(mark.id))
        if let points, let hand = InkHand(raw: points, mark: mark, feel: Settings.shared.data.ui.inkHandFeel) {
            hands[mark.id] = hand
            drawingOn.insert(mark.id)
        }
    }

    /// Puts a mark the person drew on the window under it, or on `surface` where there is none.
    private func place(_ mark: Mark, on surface: Surface, among: [Surface], markStyle: MarkStyle) {
        if let target = windows.target(under: LiveWindows.point(of: mark)) {
            windows.pin(mark, to: target)
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
        return hit.agent && hit.kind != .text && hit.focus == nil && asks.isAnswer(hit.id) ? .pick(hit) : .erase(hit)
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
        remove([mark.id])
    }

    /// The marks a tap at `point` may erase, the topmost last: those on the surface, and those on the
    /// window under the tap that show, since a window in front covers the rest.
    private func erasable(at point: CGPoint, on surface: Surface) -> [Mark] {
        let top = windows.target(under: point)?.id
        return windows.marks.filter { $0.shown && $0.window == top }.map(\.mark) + surface.marks
    }

    /// Takes marks off every surface and window, and they lose their part in the asks.
    private func remove(_ ids: Set<Mark.ID>) {
        takeOff(ids)
        run(asks.reduce(.removed(ids)))
    }

    /// Takes marks off every surface and window, without a word to the asks.
    private func takeOff(_ ids: Set<Mark.ID>) {
        for surface in surfaces { surface.marks.removeAll { ids.contains($0.id) } }
        asideOnScreen.removeAll { ids.contains($0.id) }
        windows.remove(ids)
    }

    /// Marks that went with their window.
    private func forget(_ ids: Set<Mark.ID>) {
        run(asks.reduce(.windowGone(ids)))
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
    private var ink: [Mark] { asks.ink(among: shownMarks) }

    /// The person's marks no ask has been about yet, oldest first.
    private var newInk: [Mark] { asks.newInk(among: shownMarks) }

    var responderState: LiveResponder.State { responder.state }

    private var answerSizes: LiveAnswerLayout.Sizes {
        let ui = Settings.shared.data.ui
        return LiveAnswerLayout.Sizes(textSize: ui.liveInkTextSize, textWidth: ui.liveInkTextWidth, style: ui.textStyle)
    }

    /// The note's ink, oldest first, on the screen or away with its window: the person's ink no ask has
    /// been about.
    private var noteInk: [Mark] {
        let ids = asks.noteInk
        return inDrawnOrder(marks.filter { ids.contains($0.id) })
    }

    /// Where a note hangs from `mark` before the window's text is known.
    private func firstPlace(beside mark: Mark) -> PopoverPlace? {
        guard let extent = mark.shapeExtent else { return nil }
        return LiveAnswerLayout.noteHang(LiveNotePopover.placementSize, for: mark, scene: scene(frame: extent, page: nil, text: []))
    }

    /// Gives the new ink its note, with the keys. A note up already keeps its words, its target and
    /// its caret, and moves to hang from the newest ink. Answers whether the note took the keys.
    @discardableResult
    private func showNote() -> Bool {
        guard let mark = newInk.last(where: { $0.shapeExtent != nil }), let first = firstPlace(beside: mark) else { return false }
        if let note {
            if notePlace?.anchor != mark.id {
                hang(note, from: mark, at: first)
                prepare(beside: mark, panel: note)
                Log.write("[live-ink] note moved to the newest ink")
            }
            // Taking the keys back lists the targets again (`onKeysBack`).
            note.takeKeys()
            return true
        }
        let panel = LiveNotePopover(at: first, target: lastTarget)
        noteOffered = lastTarget
        panel.onAsk = { [weak self, weak panel] words, target in
            guard let self else { return }
            self.stopListening()
            self.letGoOfNotePanel()
            self.lastTarget = target
            let session = target.session
            let note = panel.flatMap { panel in panel.shownPlace.map { (panel: panel, place: $0, tag: panel.tagFrame) } }
            if case .failure = self.ask(words, sendingTo: session, from: note) { panel?.fadeAway() }
        }
        panel.onKeysBack = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.refreshTargets(of: panel)
        }
        panel.onEscape = { [weak self] in self?.escape() }
        panel.onTyped = { [weak self] in self?.typedInNote() }
        note = panel
        hang(panel, from: mark, at: first)
        prepare(beside: mark, panel: panel)
        refreshTargets(of: panel)
        if let listening {
            panel.setListening(listening.listensPastRelease)
            if !typedOver, !listening.words.isEmpty { panel.hear(listening.text) }
        }
        Log.write("[live-ink] note open")
        return panel.hasKeys
    }

    /// Lists the sessions for the note's target again, so one started since shows up. A target the
    /// person picked by hand stays (`DestinationChoice`).
    private func refreshTargets(of panel: LiveNotePopover) {
        listSessions? { [weak panel] candidates in panel?.setSessions(candidates) }
    }

    /// Hangs the note from `mark`, at `place`.
    private func hang(_ panel: LiveNotePopover, from mark: Mark, at place: PopoverPlace) {
        var place = place
        place.anchor = mark.id
        notePlace = place
        hangNote()
    }

    /// Hands the note to the overlays: the one that draws the mark it hangs from, its window's or its
    /// home screen's, hangs it, and every other lets go of it.
    private func hangNote() {
        let anchor = notePlace?.anchor
        let drawing = surfaces.filter { $0.marks.contains { $0.id == anchor } }
        let mark = drawing.first?.marks.first { $0.id == anchor }
        let holder = mark.flatMap { home(of: $0, among: drawing) }
        for surface in surfaces { surface.overlay.marks.hang(surface === holder ? note : nil, place: notePlace) }
        windows.hang(note, place: notePlace)
    }

    /// The note goes when its ink does: asked about, taken back, erased, or gone with its window. When
    /// the ink it hangs from went and other ink of its is left, it moves to hang from the newest of that,
    /// once the chord is let go.
    private func keepNoteWithItsInk() {
        guard let note else { return }
        let ink = noteInk
        guard let newest = ink.last(where: { $0.shapeExtent != nil }) else {
            closeNote()
            Log.write("[live-ink] note closed: its ink is gone")
            return
        }
        guard !isInking, !ink.contains(where: { $0.id == notePlace?.anchor }), let place = firstPlace(beside: newest)
        else { return }
        hang(note, from: newest, at: place)
        Log.write("[live-ink] note moved: the ink it hung from went")
    }

    /// The note is no longer this one's to place: it was asked in, and hands over or fades where it is.
    private func letGoOfNotePanel() {
        note = nil
        notePlace = nil
        hangNote()
    }

    private func closeNote() {
        let closing = note
        letGoOfNotePanel()
        closing?.dismiss()
    }

    /// Esc stopped an ask, and its ink is the note's again (`LiveAsks.Effect.reopenNote`): the note
    /// opens on it with the keys and the words the ask carried, or the note up already takes the keys
    /// and keeps its own words.
    private func reopenNote(_ words: String) {
        let opening = note == nil
        showNote()
        guard let note else { return }
        if opening || note.isEmpty {
            note.put(words)
            typedOver = true
        }
        Log.write("[live-ink] note reopened words=\(words.split(whereSeparator: \.isWhitespace).count)")
    }

    /// Esc in the note: the note goes, with what was said for it and its ink, all the ink no ask has
    /// been about. Ink an ask was about stays.
    private func discardNote() {
        closeNote()
        stopListening()
        let before = marks.count
        run(asks.reduce(.noteDiscarded))
        showMarks()
        closeEmpty(fade: LiveMarksLayer.removalFade)
        Log.write("[live-ink] note discarded marks=\(before - marks.count)")
    }

    /// Fades the note ask `id` was asked in, where it is, even partway through handing over. With
    /// `how`, the ask finished before the conversation came up, and the note leaves as the
    /// conversation would have.
    private func letGoOfNote(of id: LiveAsks.Ask.ID, as how: LiveMarksLayer.Finish? = nil) {
        let leave = how.map(LiveMarksLayer.popoverLeave)
        handing.removeValue(forKey: id)?.fadeAway(after: leave?.after ?? 0, over: leave?.fade)
        handingTo[id] = nil
    }

    /// The note ask `id` was sent in hands over to `reply`, the conversation, which comes up in its
    /// place once the note looks as it does, and the note goes behind it.
    private func handOver(to reply: Mark, for id: LiveAsks.Ask.ID) {
        guard let note = handing[id] else { return }
        handingTo[id] = reply.id
        note.handOver { [weak self] in
            guard let self, handingTo[id] == reply.id else { return }
            handing[id] = nil
            handingTo[id] = nil
            // The ask may have drawn it already, or redrawn it saying why it failed.
            guard let shown = asks.ask(id)?.say, shown.id == reply.id, !marks.contains(where: { $0.id == reply.id }) else { return }
            put([shown], window: nil, for: id)
        }
    }

    /// The marks on the screen, and the conversations about to take their notes' places.
    private var shownIDs: Set<Mark.ID> { Set(marks.map(\.id)).union(handingTo.values) }

    /// Asks the responder about the new ink, with `words` as its note, or about the ink asked about
    /// last when there is none new, as a follow-up. The picture is taken now, and the ask waits for the
    /// asks to the responder before it (`LiveAsks.Effect.send`). With `session`, sends the picture and
    /// the words to that working session instead, as a card (`share`), at once. `note` is the note asked
    /// in, where it hangs and where its words are: the conversation takes its place, and a card draws
    /// the words there. `following` is the reply the person answered with `picked`: it stays, with
    /// their words as its question, and it and the answer's marks carry the thinking light until the
    /// next answer replaces them. A follow-up is about the ink asked about, and the note, with its new
    /// ink and its words, stays. Answers whether an ask started, and why not.
    @discardableResult
    func ask(_ words: String, sendingTo session: AgentDestination? = nil,
             from note: (panel: LiveNotePopover, place: PopoverPlace, tag: CGRect?)? = nil,
             following reply: Mark? = nil, picked: LiveAnswerActions.Pick? = nil) -> Result<Void, LiveResponder.Failure> {
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        // A follow-up is not about the note's ink, and leaves the note, its words and what was said for it.
        let noteIDs = reply == nil ? [] : asks.noteInk
        if reply == nil { closeNote() }
        // The words as they were said, unless the person changed them in the note.
        let said = reply != nil ? nil : spoken.flatMap { LiveListening.text(of: $0.words).trimmingCharacters(in: .whitespacesAndNewlines) == trimmed ? $0 : nil }
        if reply == nil { spoken = nil }
        let person = ink.filter { !noteIDs.contains($0.id) }
        let fresh = reply == nil ? newInk : []
        let following = reply.map { LiveAsks.Following(reply: $0, pick: picked ?? .reply, words: words) }
        let id: LiveAsks.Ask.ID
        let about: [Mark]
        let point: CGPoint
        switch asks.begin(among: shownMarks, following: following, words: trimmed, toSession: session != nil) {
        case .refused(let refusal, let effects):
            run(effects)
            return .failure(LiveResponder.Failure(reason: refusal.rawValue, detail: refusal.detail))
        case .began(let began, let asked, let centre, let effects):
            id = began
            about = asked
            point = centre
            run(effects)
        }
        let answerer = (agent: session?.client.rawValue ?? LiveAnswerLayout.agentName, name: session?.project)
        answerers[id] = answerer
        if let note { handing[id] = note.panel }
        if let reply {
            put([reply], window: windows.window(of: reply.id), for: id)
        } else if let note, !trimmed.isEmpty {
            let conversation = LiveAnswerLayout.conversation(trimmed, agent: answerer.agent, answerer: answerer.name, at: note.place,
                                                             sizes: answerSizes)
            _ = asks.reduce(.conversed(conversation, for: id))
            handOver(to: conversation, for: id)
        }
        let spot = note?.tag
        showMarks()
        let started = Date()
        let ui = Settings.shared.data.ui
        let plan = picturePlan(for: about)
        Log.write("[live-ink] asking id=\(id) new=\(fresh.count) about=\(about.count) words=\(trimmed.split(whereSeparator: \.isWhitespace).count) queued=\(asks.queued.count) picture=\(Self.describe(plan))")
        let early = prepared.flatMap { $0.ink == Set(person.map(\.id)) && $0.plan == plan ? $0.packet : nil }
        if reply == nil { prepared = nil }
        let inkWindows = inkWindows(of: person)
        Task { @MainActor [weak self] in
            do {
                let packet: LivePacket
                if let early {
                    packet = try await early.value
                } else {
                    packet = try await LivePacket.build(plan, at: point, ink: person, inkWindows: inkWindows, style: ui.textStyle,
                                                        markStyle: ui.markStyle)
                }
                if reply == nil {
                    let offered: String? = switch self?.noteOffered {
                    case .responder: "responder"
                    case .session(let destination): destination.id
                    case nil: nil
                    }
                    SendContext.note(packet, to: session?.id ?? "responder", offered: offered)
                }
                if let session {
                    self?.share(packet, words: words, spoken: said, with: session, from: spot, for: id)
                } else {
                    self?.send(packet, words: words, spoken: said, about: about, new: Set(fresh.map(\.id)), started: started, for: id)
                }
            } catch let failure as LivePacket.Failure {
                Log.write("[live-ink] error packet \(failure.detail)")
                self?.failed(LiveResponder.Failure(reason: failure.reason, detail: failure.detail), for: id)
            } catch {
                self?.failed(LiveResponder.Failure(reason: "Vignette couldn't see the screen.", detail: "\(error)"), for: id)
            }
        }
        return .success(())
    }

    /// Holds what ask `id` sends the responder, made from its packet and the ink on the screen now,
    /// and sends it once the asks before it have ended.
    private func send(_ packet: LivePacket, words: String, spoken: (words: [SpokenWord], began: Date)?, about: [Mark],
                      new: Set<Mark.ID>, started: Date, for id: LiveAsks.Ask.ID) {
        guard asks.ask(id)?.phase == .looking else { return }
        let note = numberedNote(spoken, packet: packet) ?? words
        let person = ink.filter { packet.holds($0) }
        let asked = about.compactMap(\.shapeExtent).reduce(CGRect.null) { $0.union($1) }
        let near = packet.lines(near: asked)
        Log.write("[live-ink] packet ms=\(Int(Date().timeIntervalSince(started) * 1000)) app=\(packet.app ?? "none") lines=\(packet.lines.count) near=\(near.count) bytes=\(packet.picture.count)\(packet.detail == nil ? "" : " detail")"
                  + Self.describeArea(of: packet))
        held[id] = LiveResponder.Ask(
            content: { [weak self] conversation in
                let last = self?.lastPicture
                let same = last.map { $0.conversation == conversation && $0.subject == packet.subject && $0.text == packet.textSignature } ?? false
                let sent = same ? last?.lines ?? [] : []
                let unsent = near.filter { !sent.contains($0.id) }
                self?.lastPicture = (conversation, packet.subject, packet.textSignature, sent.union(unsent.map(\.id)))
                _ = self?.asks.reduce(.pictureSent(fresh: !same, for: id))
                var content: [[String: Any]] = []
                if !same {
                    content.append(Self.image(packet.picture))
                    if let detail = packet.detail { content.append(Self.image(detail.png)) }
                    for window in packet.alone { content.append(Self.image(window.picture)) }
                }
                if let lines = LivePacket.textLines(unsent) { content.append(["type": "text", "text": lines]) }
                content.append(["type": "text", "text": packet.message(note: note, ink: person, new: new, freshPicture: !same)])
                return content
            },
            onSay: { [weak self] say in self?.showSay(say, near: asked, packet: packet, for: id) },
            onAnswer: { [weak self] result in
                switch result {
                case .success(let answer):
                    self?.answered(answer, packet: packet, sent: self?.lastPicture?.lines ?? [], near: asked, for: id)
                case .failure(let failure): self?.failed(failure, for: id)
                }
            })
        let effects = asks.reduce(.arrived(.packetCame, for: id))
        if asks.ask(id)?.phase == .waiting { Log.write("[live-ink] waiting id=\(id) behind=\(asks.queued.firstIndex(of: id) ?? 0)") }
        run(effects)
    }

    /// Hands the responder ask `id`, whose turn has come.
    private func sendHeld(_ id: LiveAsks.Ask.ID) {
        guard let ask = held.removeValue(forKey: id) else { return }
        Log.write("[live-ink] sending id=\(id)")
        responder.ask(ask)
    }

    /// Sends the note to a working session through Send, with the words and where the ink is in the
    /// message, as a card: the window without the ink, with the person's ink on it and their words as
    /// a note, which is what the session is sent. Once the request is stored the ink and the note leave
    /// the window, and `LiveNoteCards` waits on the session's turn.
    private func share(_ packet: LivePacket, words: String, spoken: (words: [SpokenWord], began: Date)?, with session: AgentDestination,
                       from spot: CGRect?, for id: LiveAsks.Ask.ID) {
        var shared: Set<Mark.ID>?
        for case .share(let about) in asks.reduce(.arrived(.packetCame, for: id)) { shared = about }
        guard let about = shared else { return }
        guard let sendNote else { return letGoOfNote(of: id) }
        let numbered = numberedNote(spoken, packet: packet)
        var place = [packet.app, packet.title.map { "\"\($0)\"" }, packet.location].compactMap { $0 }.joined(separator: ", ")
        if !packet.windows.isEmpty {
            place = "the screen, across " + packet.windows.map { window in
                [window.app, window.title.flatMap { $0.isEmpty ? nil : "\"\($0)\"" }].compactMap { $0 }.joined(separator: " ")
            }.joined(separator: " and ")
        }
        if place.isEmpty { place = "the screen" }
        // One line: the plugin's monitor makes each line it prints a message of its own.
        var said = (numbered ?? words).components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        if let last = said.last, !".?!]".contains(last) { said += "." }
        var message = (said.isEmpty ? "" : said + " ") + "Drawn with Vignette's live ink on \(place)."
        if numbered != nil { message += " Each [n] in the words is where the ink numbered n in the picture was drawn as they were said." }
        let covered = packet.alone.flatMap(\.covered).compactMap { packet.numbers[$0] }.sorted()
        if !covered.isEmpty {
            message += " On the screen, a window in front covers the ink numbered \(covered.map(String.init).joined(separator: ", "))."
        }
        // The same ink the picture has, so the card holds what the session sees and what leaves the window.
        let person = ink.filter { packet.frame.intersects($0.shapeExtent ?? .null) }
        let note = noteMark(words, about: about, packet: packet, at: spot)
        let shapes = person.filter { about.contains($0.id) && $0.kind != .text }.compactMap(\.shapeExtent)
        let inkBox = (shapes.isEmpty ? person.compactMap(\.shapeExtent) : shapes).reduce(CGRect.null) { $0.union($1) }
        let card = NoteCard(picture: packet.picture, capture: packet.capture,
                            marks: packet.drawingMarks(person + (note.map { [$0] } ?? [])), pointScale: packet.scale,
                            window: packet.windowID, ink: inkBox, before: LiveNoteCards.before(packet, ink: inkBox))
        sendNote(card, session, message) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let request):
                Log.write("[live-ink] sent to a session request=\(request) marks=\(card.marks.count)")
                let effects = self.asks.reduce(.arrived(.sentToSession(ink: Set(person.map(\.id))), for: id))
                if effects == [.withdraw] {
                    Log.write("[live-ink] note withdrawn request=\(request)")
                    DispatchQueue.main.async { self.unsendNote?(request) }
                    return
                }
                guard !effects.isEmpty else { return }
                // The note leaves as the conversation would have, before the ask's end lets it go.
                let leaving = effects.lazy.compactMap { if case .finish(_, let how) = $0 { how } else { nil } }.first
                self.letGoOfNote(of: id, as: leaving)
                self.run(effects)
            case .failure(let refusal):
                self.failed(LiveResponder.Failure(reason: "Not sent. " + refusal.reason, detail: "send refused"), for: id)
            }
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

    /// The person's words as a note beside the ink `about`, at the note panel's tag, `spot`, or clear
    /// of the window's text, in global top-left points. Nil for no words.
    private func noteMark(_ words: String, about: Set<Mark.ID>, packet: LivePacket, at spot: CGRect?) -> Mark? {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let near = marks.filter { about.contains($0.id) }.compactMap(\.shapeExtent).reduce(CGRect.null) { $0.union($1) }
        guard !words.isEmpty, !near.isNull else { return nil }
        let scene = scene(for: packet)
        return spot.map { LiveAnswerLayout.note(words, at: $0, sizes: answerSizes) }
            ?? LiveAnswerLayout.note(words, near: near, scene: scene, obstacles: LiveAnswerLayout.obstacles(in: scene), sizes: answerSizes,
                                     byPerson: true)
    }

    /// How long marks take to leave before they are removed.
    private func finishDuration(_ how: LiveMarksLayer.Finish) -> TimeInterval {
        let motion = Settings.shared.motionScale
        guard motion > 0 else { return LiveMarksLayer.doneFade + 0.05 }
        return ((how == .done ? LiveMarksLayer.doneHold : 0) + LiveMarksLayer.doneAway) * motion + 0.15
    }

    /// Shows marks the ask has set leaving (`LiveAsks.finishing`) going, and removes them once they have.
    private func finish(_ ids: Set<Mark.ID>, _ how: LiveMarksLayer.Finish) {
        Log.write("[live-ink] \(how) marks=\(ids.count)")
        showMarks()
        DispatchQueue.main.asyncAfter(deadline: .now() + finishDuration(how)) { [weak self] in
            guard let self else { return }
            let effects = self.asks.reduce(.finished(ids))
            guard !effects.isEmpty else { return }
            self.run(effects)
            self.showMarks()
            self.closeEmpty(fade: 0)
        }
    }

    /// Closes an answer, as `event` says: by its × (`dismissed`), with the ink only it was about, or by
    /// Esc (`answerClosed`), the newest, with the person's ink staying. Its marks leave.
    private func closeAnswer(by event: LiveAsks.Event) {
        hideDismissButton()
        run(asks.reduce(event))
    }

    /// How long a new note waits out of sight for the window's text before it shows where it opened.
    private static let revealLimit: TimeInterval = 0.8

    /// Starts capturing the window under the ink as a stroke ends, while the chord is still held,
    /// so the note can open clear of the window's text without waiting for a capture of its own. The
    /// note waits only for the glance at where the text is, which comes long before the packet.
    private func prefetch(at point: CGPoint) {
        let person = ink
        let plan = picturePlan(for: newInk)
        let inkWindows = inkWindows(of: person)
        let ui = Settings.shared.data.ui
        let (glances, glanced) = AsyncStream<LivePacket.Glance>.makeStream()
        let packet = Task { @MainActor in
            defer { glanced.finish() }
            return try await LivePacket.build(plan, at: point, ink: person, inkWindows: inkWindows, style: ui.textStyle,
                                              markStyle: ui.markStyle, glanced: { glanced.yield($0) })
        }
        let glance = Task { @MainActor () -> LivePacket.Glance? in
            for await glance in glances { return glance }
            return nil
        }
        prepared = (Set(person.map(\.id)), plan, packet, glance)
    }

    /// What the picture of an ask about `about` is of, from the windows on the screen now.
    private func picturePlan(for about: [Mark]) -> LivePacket.Plan {
        let asked = about.filter { $0.kind != .text }.compactMap { mark in
            mark.shapeExtent.map { LivePacket.Asked(id: mark.id, box: $0, window: windows.window(of: mark.id)) }
        }
        return LivePacket.plan(for: asked, windows: LivePacket.listedWindows(), screens: StateReport.screenFrames)
    }

    /// The window each of `marks` is on, for those on one.
    private func inkWindows(of marks: [Mark]) -> [Mark.ID: CGWindowID] {
        Dictionary(uniqueKeysWithValues: marks.compactMap { mark in windows.window(of: mark.id).map { (mark.id, $0) } })
    }

    private static func describe(_ plan: LivePacket.Plan) -> String {
        switch plan {
        case .window(let id): id.map { "window \($0)" } ?? "screen"
        case .area(let rect, let windows, let alone):
            "area \(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height)) windows=\(windows.map(String.init).joined(separator: ","))"
                + " alone=\(alone.map { "\($0.window):covered=\($0.covered.count),outside=\($0.outside.count)" }.joined(separator: ";"))"
        }
    }

    private static func describeArea(of packet: LivePacket) -> String {
        guard case .area = packet.subject else { return "" }
        let frame = packet.frame
        return " area=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height)) windows=\(packet.windows.count)"
            + " alone=\(packet.alone.count) aloneBytes=\(packet.alone.map { String($0.picture.count) }.joined(separator: ","))"
    }

    /// Shows the note against its ink, where a hand would write it, which needs the window's frame
    /// and text from a glance at the window: the one started as the stroke ended, which also serves
    /// the ask when the ink is the same, or a new one. Without an answer in `revealLimit`, the note
    /// shows where it opened.
    private func prepare(beside newest: Mark, panel: LiveNotePopover) {
        let person = ink
        let extent = newest.shapeExtent ?? .zero
        if prepared?.ink != Set(person.map(\.id)) { prefetch(at: CGPoint(x: extent.midX, y: extent.midY)) }
        if let glance = prepared?.glance { place(panel, beside: newest, from: glance) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.revealLimit) { [weak panel] in panel?.reveal() }
    }

    private func place(_ panel: LiveNotePopover, beside newest: Mark, from glance: Task<LivePacket.Glance?, Never>) {
        Task { @MainActor [weak self, weak panel] in
            guard let glance = await glance.value, let self, let panel, self.note === panel, self.notePlace?.anchor == newest.id else {
                panel?.reveal()
                return
            }
            let scene = self.scene(frame: glance.frame, page: glance.page, text: glance.text)
            if let place = LiveAnswerLayout.noteHang(LiveNotePopover.placementSize, for: newest, scene: scene) { self.hang(panel, from: newest, at: place) }
            panel.reveal()
        }
    }

    // MARK: Dismissing and actions

    /// A reply's popover while it is up, and its body in global top-left points.
    private typealias ShownReply = (popover: ReplyPopover, note: CGRect)

    /// `ask`'s reply, while it is up.
    private func shownReply(of ask: LiveAsks.Ask) -> ShownReply? {
        guard let say = ask.say, asks.answer(of: say.id) == ask.id, !asks.isFinishing(say.id),
              let popover = windows.popover(of: say.id) ?? surfaces.lazy.compactMap({ $0.overlay.popover(of: say.id) }).first,
              let note = popover.globalFrame
        else { return nil }
        return (popover, note)
    }

    /// The replies that are up, by their asks.
    private func shownReplies() -> [LiveAsks.Ask.ID: ShownReply] {
        Dictionary(uniqueKeysWithValues: asks.asks.compactMap { ask in shownReply(of: ask).map { (ask.id, $0) } })
    }

    /// Whether some ask's reply is an answer on the screen, in sight or not.
    private var hasReply: Bool { asks.asks.contains { ask in ask.say.map { asks.answer(of: $0.id) == ask.id } ?? false } }

    /// Follows the pointer for as long as an answer is up, in sight or not, to show the × over the
    /// reply it is on, and keeps each answer's actions at its reply's foot as its window moves.
    private func watchPointer() {
        guard pointerWatch.isEmpty else { return }
        // The reply's popover can move with its window, or fade, while the pointer is still.
        replyWatch = NotificationCenter.default.addObserver(forName: .liveReplyChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        let moved: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.pointerMoved() } }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: moved) {
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
        for id in actionsPanels.keys { hideActions(of: id) }
    }

    private func pointerMoved() {
        let replies = shownReplies()
        showActions(replies)
        guard !isInking else { return hideDismissButton() }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: StateReport.primaryHeight - mouse.y)
        // The newest reply on top wins where two overlap.
        let under = asks.asks.reversed().lazy.compactMap { ask -> (id: LiveAsks.Ask.ID, reply: ShownReply)? in
            guard self.asks.offersDismiss(ask.id), let reply = replies[ask.id] else { return nil }
            let onButton = self.dismissing == ask.id && self.dismissButton?.globalFrame.insetBy(dx: -6, dy: -6).contains(point) == true
            return reply.note.insetBy(dx: -10, dy: -10).contains(point) || onButton ? (ask.id, reply) : nil
        }.first
        guard let under else { return hideDismissButton() }
        let note = under.reply.note
        if let dismissButton, dismissing == under.id {
            under.reply.popover.carry(dismissButton)
            dismissButton.place(at: CGPoint(x: note.maxX, y: note.minY))
        } else {
            hideDismissButton()
            let button = LiveDismissButton(at: CGPoint(x: note.maxX, y: note.minY), over: under.reply.popover)
            let id = under.id
            button.onClick = { [weak self] in
                Log.write("[live-ink] answer dismissed by its × id=\(id)")
                self?.closeAnswer(by: .dismissed(id))
            }
            dismissButton = button
            dismissing = id
        }
    }

    private func hideDismissButton() {
        dismissButton?.hide()
        dismissButton = nil
        dismissing = nil
    }

    /// Shows each answer's buttons in the room kept at its reply's foot, or moves them there, and hides
    /// those whose reply is not among `replies`.
    private func showActions(_ replies: [LiveAsks.Ask.ID: ShownReply]) {
        for id in actionsPanels.keys where replies[id] == nil { hideActions(of: id) }
        for ask in asks.asks where ask.phase == .answered {
            guard let shown = replies[ask.id] else { continue }
            let reply = shown.popover, note = shown.note
            let insets = ReplyContent.insets
            let corner = CGPoint(x: note.minX + insets.left, y: note.maxY - insets.bottom - LiveAnswerActions.height)
            let width = note.width - insets.left - insets.right
            if let panel = actionsPanels[ask.id] {
                reply.carry(panel)
                panel.place(at: corner, width: width)
                continue
            }
            let id = ask.id
            let panel = LiveAnswerActions(ask.actions, answerer: NoteBadge.label(for: ask.say?.agentName), at: corner, width: width,
                                          over: reply, picked: ask.picked, draft: ask.draft)
            panel.onPick = { [weak self] action in self?.respond(action, by: .action(action), to: id) }
            panel.onReply = { [weak self] words in self?.respond(words, by: .reply, to: id) }
            let replyID = ask.say?.id
            panel.onDraft = { [weak self] words in _ = self?.asks.reduce(.drafted(words, reply: replyID)) }
            panel.onPoint = { [weak self] action in self?.point(at: action, of: id) }
            panel.onEscape = { [weak self] in self?.escape() }
            actionsPanels[id] = panel
        }
    }

    private func hideActions(of id: LiveAsks.Ask.ID) {
        guard let panel = actionsPanels.removeValue(forKey: id) else { return }
        point(at: nil, of: id)
        panel.hide()
    }

    /// The pointer is on one of ask `id`'s actions, or nil when it left them: the marks it acts on
    /// stand out and the rest of that answer's findings fade, so "Header only" shows which. One that
    /// acts on every mark changes nothing.
    private func point(at action: LiveAnswer.Action?, of id: LiveAsks.Ask.ID) {
        let findings = asks.ask(id)?.findings ?? []
        let all = Set(findings.joined())
        let lit = action?.marks.map { Set($0.flatMap { $0 < findings.count ? findings[$0] : [] }) } ?? all
        windows.light(lit, among: all)
    }

    /// The person answered ask `id`'s reply, with one of its actions or with words typed after Reply:
    /// the words go to the responder as a follow-up ask about the same ink, in its turn. The
    /// conversation stays where it is, with their words as its question and no answer yet, as a first
    /// ask's does, and it and the ink carry the thinking light until the next answer fills it.
    private func respond(_ words: String, by pick: LiveAnswerActions.Pick, to id: LiveAsks.Ask.ID) {
        Log.write("[live-ink] \(pick == .reply ? "reply typed" : "action picked") words=\(words.count) id=\(id)")
        hideDismissButton()
        point(at: nil, of: id)
        guard let answered = asks.ask(id), let said = answered.say, shownReply(of: answered) != nil else { return }
        hideActions(of: id)
        // A new ask starts from the reply where it is now. Refused, it puts the answer back.
        guard var reply = marks.first(where: { $0.id == said.id }) else { return }
        reply.quote = words
        reply.notice = nil
        reply = LiveAnswerLayout.grown(reply, to: "", sizes: answerSizes)
        ask(words, following: reply, picked: pick)
    }

    // MARK: Answering

    /// Vignette says why ask `id`, with no conversation, failed: in a reply hung from the ink it asked
    /// about, named for who the ask went to. The reply is the ask's, with its own ×.
    private func say(_ reason: String, for id: LiveAsks.Ask.ID) {
        guard let about = asks.ask(id)?.about else { return }
        let near = shownMarks.filter { about.contains($0.id) }.compactMap(\.shapeExtent).reduce(CGRect.null) { $0.union($1) }
        guard !near.isNull else { showMarks(); return }
        let screen = StateReport.screenFrames.first { $0.intersects(near) } ?? near
        let scene = LiveAnswerLayout.Scene(room: screen.insetBy(dx: 8, dy: 8), ink: ink, text: [], notes: answerBoxes(except: id),
                                           screen: Self.visibleScreen(around: near))
        var reply = LiveAnswerLayout.reply("", quote: nil, from: near, scene: scene, sizes: answerSizes)
        let answerer = answerers[id] ?? (LiveAnswerLayout.agentName, nil)
        reply.agentName = answerer.agent
        reply.answerer = answerer.name
        reply = noticed(reply, reason)
        _ = asks.reduce(.conversed(reply, for: id))
        drawingOn.insert(reply.id)
        put([reply], window: nil, for: id)
    }

    private static func image(_ png: Data) -> [String: Any] {
        ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]]
    }

    private func scene(for packet: LivePacket, answering id: LiveAsks.Ask.ID? = nil) -> LiveAnswerLayout.Scene {
        scene(frame: packet.frame, page: packet.page, text: packet.lines.map { packet.global($0.box) }, answering: id)
    }

    /// The window at `frame` with its text at `text`, both in global top-left points. The person's
    /// notes and every answer on the screen but ask `id`'s are what a note keeps clear of.
    private func scene(frame: CGRect, page: CGRect?, text: [CGRect], answering id: LiveAsks.Ask.ID? = nil) -> LiveAnswerLayout.Scene {
        let screen = StateReport.screenFrames.first { $0.intersects(frame) } ?? frame
        // A browser's page, not its tabs and toolbar: notes on those read as being about the browser.
        let room = (page ?? frame).intersection(screen).insetBy(dx: 8, dy: 8)
        let ink = self.ink
        let notes = ink.filter { $0.kind == .text }.compactMap { LiveAnswerLayout.noteBox($0, sizes: answerSizes) } + answerBoxes(except: id)
        return LiveAnswerLayout.Scene(room: room.isNull ? frame : room, ink: ink, text: text, notes: notes,
                                      screen: Self.visibleScreen(around: frame))
    }

    /// Where the answers on the screen are, all but ask `id`'s, in global top-left points: each reply's
    /// body and each mark's extent.
    private func answerBoxes(except id: LiveAsks.Ask.ID?) -> [CGRect] {
        shownMarks.filter { mark in asks.answer(of: mark.id).map { $0 != id } ?? false }
            .compactMap { $0.shapeExtent ?? LiveAnswerLayout.noteBox($0, sizes: answerSizes) }
    }

    /// The visible part of the screen `frame` is on, without the menu bar and the Dock, in global
    /// top-left points.
    private static func visibleScreen(around frame: CGRect) -> CGRect? {
        guard let screen = StateReport.screen(at: CGPoint(x: frame.midX, y: frame.midY)) ?? NSScreen.main else { return nil }
        return StateReport.flipped(screen.visibleFrame)
    }

    /// The reply so far, in the conversation where the person asked, or with no question, as a popover
    /// hung from the ink. It keeps where it hangs, so it grows rather than jumping as words arrive.
    private func showSay(_ say: String, near asked: CGRect, packet: LivePacket, for id: LiveAsks.Ask.ID) {
        let effects = asks.reduce(.arrived(.replyCame, for: id))
        guard effects.contains(.showReply) else { return }
        run(effects)
        let note: Mark
        if let shown = asks.ask(id)?.say {
            note = LiveAnswerLayout.grown(shown, to: say, sizes: answerSizes)
        } else {
            note = LiveAnswerLayout.reply(say, quote: nil, from: asked, scene: scene(for: packet, answering: id), sizes: answerSizes)
            drawingOn.insert(note.id)
        }
        _ = asks.reduce(.streamed(note, for: id))
        // Until the note hands over, the conversation takes its words there.
        if handingTo[id] != note.id { put([note], window: packet.windowID, for: id) }
    }

    /// `sent` is the ids of the text lines the answer was given, the only ones it may name. Answers
    /// the indexes of the marks it did not draw, or nil when nothing was drawn.
    @discardableResult
    private func answered(_ answer: LiveAnswer, packet: LivePacket, sent: Set<String>, near asked: CGRect,
                          for id: LiveAsks.Ask.ID) -> [Int]? {
        let effects = asks.reduce(.arrived(.answerCame, for: id))
        guard effects.contains(.drawAnswer) else { return nil }
        run(effects)
        let targets = answer.marks.map { $0.target(in: packet.lines, sent: sent).map(packet.global) }
        let layout = LiveAnswerLayout.placed(for: answer, targets: targets, asked: asked,
                                             scene: scene(for: packet, answering: id), sizes: answerSizes, streamed: asks.ask(id)?.say,
                                             below: LiveAnswerActions.room(for: answer.actions), focusable: packet.windowID != nil)
        let placed = layout.marks.map { mark in
            var mark = mark
            if mark.agent { mark.agentName = LiveAnswerLayout.agentName }
            return mark
        }
        // The focus marks, each with its label, come in one at a time once the window is captured.
        let focus = Self.steps(in: Array(placed.dropFirst())).filter { $0.first?.focus != nil }
        let held = Set(focus.joined().map(\.id))
        let shown = placed.filter { !held.contains($0.id) }
        // A reply that streamed in is on the screen already, so only the rest draw themselves on.
        drawingOn.formUnion(shown.map(\.id).filter { $0 != asks.ask(id)?.say?.id })
        for mark in placed where mark.agent && mark.kind != .text {
            let behind = mark.shapeExtent.flatMap { packet.luminance?.mean(in: $0.insetBy(dx: -8, dy: -8)) }
            if let behind, behind <= LivePacket.Luminance.dark { overDark.insert(mark.id) }
        }
        run(asks.reduce(.answered(reply: placed.first, actions: answer.actions, findings: layout.findings, shown: Set(shown.map(\.id)), for: id)))
        // The agent may have changed the window under the person's ink.
        InkBackdrop.shared.refresh()
        let labels = zip(answer.marks, targets).filter { $0.0.label != nil && $0.1 != nil }.count
        let notDrawn = layout.findings.indices.filter { layout.findings[$0].isEmpty }
        Log.write("[live-ink] drew answer marks=\(placed.count - 1) dropped=\(notDrawn.count) "
                  + "labels=\(layout.findings.filter { $0.count > 1 }.count)/\(labels)\(answer.steps ? " steps" : "")"
                  + (focus.isEmpty ? "" : " focus=\(focus.count)"))
        let groups = Self.steps(in: Array(placed.dropFirst()))
        guard answer.steps, groups.count > 1 else {
            put(shown, window: packet.windowID, eachOnItsWindow: packet.isArea, for: id)
            pullFocus(focus, window: packet.windowID, say: answer.say, replies: layout.tour, for: id)
            return notDrawn
        }
        // One answer's steps or focus at a time: an earlier answer's tour ends as this one's begins.
        letGoOfTour(because: "replaced")
        steps = Array(groups.dropFirst())
        stepsWindow = packet.windowID
        stepsOnTheirWindows = packet.isArea
        stepsAsk = id
        // `placed(for:)` places one pointing mark for each target found, in order.
        let pointers = groups.compactMap(\.first)
        stepTargets = Dictionary(uniqueKeysWithValues: zip(pointers, targets.compactMap { $0 }).compactMap { mark, target in
            mark.shapeExtent.map { (mark.id, (target, $0.origin)) }
        })
        put([placed[0]] + groups[0], window: packet.windowID, eachOnItsWindow: packet.isArea, for: id)
        watchStepClicks()
        return notDrawn
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
        stepsOnTheirWindows = false
        stepsAsk = nil
        stepTargets = [:]
        if let stepClicks { NSEvent.removeMonitor(stepClicks) }
        stepClicks = nil
    }

    /// The step on the screen is the answer's pointing mark that shows; a click in it lets the app
    /// answer the click first, then takes the step off and draws the next.
    private func clicked(at point: CGPoint) {
        guard stepClicks != nil, !isInking, let id = stepsAsk else { return }
        let shown = shownMarks.filter { asks.answer(of: $0.id) == id && $0.agent && $0.kind != .text }
        guard let current = shown.last else { return }
        let pointedAt = stepTargets[current.id].flatMap { step in
            current.shapeExtent.map { step.target.offsetBy(dx: $0.minX - step.at.x, dy: $0.minY - step.at.y).insetBy(dx: -6, dy: -6) }
        }
        guard Self.stepTarget(of: current).contains(point) || pointedAt?.contains(point) == true else { return }
        let done = shownMarks.filter { asks.answer(of: $0.id) == id && $0.kind == .text && $0.id != asks.ask(id)?.say?.id }.map(\.id) + [current.id]
        // The last step goes too once it is clicked, and the reply stays.
        let next = steps.isEmpty ? [] : steps.removeFirst()
        let window = stepsWindow, each = stepsOnTheirWindows
        if next.isEmpty { stopSteps() }
        Log.write("[live-ink] step done; \(next.isEmpty ? 0 : steps.count + 1) to go")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stepPause) { [weak self] in
            guard let self, self.asks.answer(of: current.id) == id else { return }
            self.remove(Set(done))
            self.showMarks()
            guard !next.isEmpty else { return }
            _ = self.asks.reduce(.answerShown(Set(next.map(\.id)), for: id))
            self.drawingOn.formUnion(next.map(\.id))
            self.put(next, window: window, eachOnItsWindow: each, for: id)
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
        /// The ask whose answer it is.
        let ask: LiveAsks.Ask.ID
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
    private func pullFocus(_ stops: [[Mark]], window: CGWindowID?, say: String, replies: [Mark.ID: PopoverPlace], for ask: LiveAsks.Ask.ID) {
        guard !stops.isEmpty else { return }
        // One answer's steps or focus at a time: an earlier answer's tour ends as this one's begins.
        letGoOfTour(because: "replaced")
        guard let window else {
            Log.write("[live-ink] focus skipped: the answer is on no window; drawn as circles")
            return showUnfocused(stops, window: nil, for: ask)
        }
        let run = FocusRun(ask: ask, stops: stops, holds: Focus.holds(for: say, stops: stops.count), window: window, replies: replies)
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
                    return self.showUnfocused(stops, window: window, for: ask)
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
                self.showUnfocused(stops, window: window, for: ask)
            }
        }
    }

    /// Focus could not be pulled, so each stop shows at once as a circle round its target, with its
    /// label, rather than not at all. A stop keeps its id, which the answer's actions name.
    private func showUnfocused(_ stops: [[Mark]], window: CGWindowID?, for ask: LiveAsks.Ask.ID) {
        let marks = stops.joined().map { mark -> Mark in
            guard let focus = mark.focus else { return mark }
            var circle = mark
            circle.geometry = LiveAnswerLayout.circle(around: focus.target)
            circle.focus = nil
            return circle
        }
        _ = asks.reduce(.answerShown(Set(marks.map(\.id)), for: ask))
        drawingOn.formUnion(marks.map(\.id))
        put(marks, window: window, for: ask)
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
        _ = asks.reduce(.answerShown(Set(stop.map(\.id)), for: run.ask))
        drawingOn.formUnion(stop.map(\.id))
        if let place = stop.first.flatMap({ run.replies[$0.id] }), var reply = asks.ask(run.ask)?.say, case .text(var words) = reply.geometry,
           asks.answer(of: reply.id) == run.ask {
            words.origin = place.body.origin
            reply.geometry = .text(words)
            reply.popover = place
            _ = asks.reduce(.replyRedrawn(reply))
            put(stop + [reply], window: run.window, for: run.ask)
        } else {
            put(stop, window: run.window, for: run.ask)
        }
        lightStop(stop, leaving: previous, on: run.window, reply: asks.ask(run.ask)?.say?.id)
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
    private func lightStop(_ stop: [Mark], leaving: [Mark], on window: CGWindowID, reply: Mark.ID?) {
        let shown = windows.marks.filter { $0.window == window }.map(\.mark)
        let ids = Set(stop.map(\.id))
        let target = shown.first { ids.contains($0.id) }?.focus?.target ?? .null
        let handing = Set(leaving.map(\.id))
        let onTarget = { (ink: CGRect) in
            target.insetBy(dx: -8, dy: -6).contains(CGPoint(x: ink.midX, y: ink.midY)) || ink.contains(CGPoint(x: target.midX, y: target.midY))
        }
        let lit = shown.filter { mark in
            ids.contains(mark.id) || handing.contains(mark.id) || mark.id == reply
                || (!mark.agent && !asks.isAnswer(mark.id) && mark.shapeExtent.map(onTarget) == true)
        }
        windows.light(Set(lit.map(\.id)), among: Set(shown.map(\.id)))
    }

    private func dropFocus(_ stop: [Mark]) {
        let ids = Set(stop.map(\.id)).intersection(asks.answerMarks)
        guard !ids.isEmpty else { return }
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

    /// Vignette says why in the conversation's row, or in a reply hung from the ink.
    private func failed(_ failure: LiveResponder.Failure, for id: LiveAsks.Ask.ID) {
        let effects = asks.reduce(.arrived(.failed(reason: failure.reason, shown: shownIDs), for: id))
        guard !effects.isEmpty else { return }
        if handingTo[id] == nil { letGoOfNote(of: id) }
        Log.write("[live-ink] error ask id=\(id) \(failure.detail)")
        run(effects)
    }

    /// Runs what the asks answered, but for what the event's own caller draws or sends: the reply,
    /// the answer, a session's note, a withdrawal. An ask that ended is let go, the answer a button was
    /// picked under is put back, an answer is taken off or set aside, a note says why, and the next ask
    /// goes to the responder.
    private func run(_ effects: [LiveAsks.Effect]) {
        for effect in effects {
            switch effect {
            case .ended(let id): release(id)
            case .send(let id): sendHeld(id)
            case .interrupt: responder.cancel()
            case .removeAnswer(let id, let gone): removeAnswer(gone, of: id)
            case .setAside(let id, let ids): setAside(ids, of: id)
            case .restore(let reply, let reason, let aside):
                if !aside.isEmpty { bringBack(aside) }
                restoreAnswer(reply, saying: reason)
            case .say(let id, let reason): say(reason, for: id)
            case .notice(let reply, let reason): notice(reason, in: reply)
            case .remove(let ids): remove(ids)
            case .reopenNote(let words): reopenNote(words)
            case .finish(let ids, let how): finish(ids, how)
            case .showReply, .drawAnswer, .share, .withdraw: break
            }
        }
    }

    /// Ask `id` is over (`LiveAsks.Effect.ended`): what it would have sent and who it went to are
    /// forgotten, its note fades where it is, and its ×, its buttons and its steps or focus are let go.
    private func release(_ id: LiveAsks.Ask.ID) {
        held[id] = nil
        answerers[id] = nil
        letGoOfNote(of: id)
        if dismissing == id { hideDismissButton() }
        letGoOfTour(of: id, because: "dismissed")
        hideActions(of: id)
    }

    /// The answer a button was picked under is back as it was (`LiveAsks.Effect.restore`): its words
    /// and buttons come back, typed words wait in Reply again, and its row says why, unless the person
    /// stopped the ask.
    private func restoreAnswer(_ replyID: Mark.ID, saying reason: String?) {
        guard let ask = asks.ask(withReply: replyID), var reply = ask.say else { return }
        if let reason { reply = noticed(reply, reason) }
        _ = asks.reduce(.replyRedrawn(reply))
        Log.write("[live-ink] follow-up \(reason == nil ? "stopped" : "failed"); its answer stays draft=\(ask.draft.count)")
        hideActions(of: ask.id)
        put([reply], window: windows.window(of: reply.id), for: ask.id)
        showMarks()
    }

    /// The ask failed with its conversation up (`LiveAsks.Effect.notice`): the reply's row says why,
    /// in place of any words that had come.
    private func notice(_ reason: String, in replyID: Mark.ID) {
        guard let ask = asks.ask(withReply: replyID), var reply = ask.say else { return }
        reply.notice = reason
        reply = LiveAnswerLayout.grown(reply, to: "", sizes: answerSizes)
        _ = asks.reduce(.replyRedrawn(reply))
        Log.write("[live-ink] ask failed; its conversation says why")
        if handingTo[ask.id] != replyID { put([reply], window: windows.window(of: replyID), for: ask.id) }
    }

    /// `reply` with `notice` in its row, grown to fit it.
    private func noticed(_ reply: Mark, _ notice: String) -> Mark {
        guard case .text(let text) = reply.geometry else { return reply }
        var reply = reply
        reply.notice = notice
        return LiveAnswerLayout.grown(reply, to: text.text, sizes: answerSizes, foot: reply.popover?.foot ?? .zero)
    }

    /// Adds ask `id`'s answer's marks, or Vignette's own note, replacing marks of the same id. They go
    /// on the window the ask was about, or the window the ink asked about is on, each at its offset
    /// from that window's top-left. With no window they go on the active Space's surfaces.
    /// With `eachOnItsWindow`, for an answer about a picture of an area of the screen, each pointing
    /// mark goes on the window under it, a reply or a label on the window of the mark it hangs from or
    /// names, and any other text on the leader's window.
    private func put(_ placed: [Mark], window windowID: CGWindowID?, eachOnItsWindow: Bool = false, for id: LiveAsks.Ask.ID) {
        let leaderTarget = asks.ask(id)?.leader.flatMap(windows.window(of:)).flatMap(windows.target(id:))
        let shared = windowID.flatMap(windows.target(id:)) ?? leaderTarget
        let active = activeSurfaces()
        let markStyle = Settings.shared.data.ui.markStyle
        // A reply goes on the window of the mark it hangs from, so it is placed after it.
        let ids = Set(placed.map(\.id))
        let hangs = { (mark: Mark) in mark.popover?.anchor.map(ids.contains) ?? false }
        // The mark a label names comes just before it.
        var labelled: Mark.ID?
        var chosen: [Mark.ID: LiveWindows.Target] = [:]
        var onWindows: [(mark: Mark, target: LiveWindows.Target)] = []
        func window(for mark: Mark) -> LiveWindows.Target? {
            guard eachOnItsWindow else { return shared }
            if let hung = mark.popover?.anchor, ids.contains(hung) { return chosen[hung] }
            if mark.isLabel, let labelled { return chosen[labelled] }
            if mark.kind == .text { return leaderTarget }
            return windows.target(under: LiveWindows.point(of: mark))
        }
        // The same marks go back on, so they keep their part in the asks.
        takeOff(ids)
        for mark in placed.filter({ !hangs($0) }) + placed.filter(hangs) {
            if let target = window(for: mark) {
                chosen[mark.id] = target
                if mark.kind != .text { labelled = mark.id }
                onWindows.append((mark, target))
            } else {
                addToScreen(mark, among: active, markStyle: markStyle)
            }
        }
        windows.pin(onWindows)
        showMarks()
        closeEmpty(fade: LiveMarksLayer.removalFade)
    }

    /// Adds a mark on no window to the surface under its centre, and to the others it draws on.
    private func addToScreen(_ mark: Mark, among active: [Surface], markStyle: MarkStyle) {
        if let home = home(of: mark, among: active) { add(mark, on: home, among: active, markStyle: markStyle) }
    }

    /// The surface among `surfaces` a mark belongs to: the one under its centre, else the first.
    private func home(of mark: Mark, among surfaces: [Surface]) -> Surface? {
        let extent = mark.shapeExtent ?? LiveAnswerLayout.noteBox(mark, sizes: answerSizes) ?? .zero
        return surfaces.first { $0.overlay.globalFrame.contains(CGPoint(x: extent.midX, y: extent.midY)) } ?? surfaces.first
    }

    /// Takes marks of ask `id`'s answer, or its failure's note, off the screen
    /// (`LiveAsks.Effect.removeAnswer`), once its steps, its focus and its buttons are let go. The asks
    /// have already taken the answer role from `gone`, so letting go of the focus removes nothing and
    /// the focus stop leaves with `gone`.
    private func removeAnswer(_ gone: Set<Mark.ID>, of id: LiveAsks.Ask.ID) {
        letGoOfTour(of: id, because: "replaced")
        hideActions(of: id)
        if !gone.isEmpty { remove(gone) }
    }

    /// Lets go of the steps and the focus, whichever answer's they are.
    private func letGoOfTour(because reason: String) {
        stopSteps()
        letGoOfFocus(because: reason)
    }

    /// Lets go of the steps or the focus when they are ask `id`'s.
    private func letGoOfTour(of id: LiveAsks.Ask.ID, because reason: String) {
        if stepsAsk == id { stopSteps() }
        if focusRun?.ask == id { letGoOfFocus(because: reason) }
    }

    /// Hides the answer a picked button's ask `id` follows, while that ask's reply streams
    /// (`LiveAsks.Effect.setAside`), once its steps, its focus and its buttons are let go. A mark on a
    /// window stays on it, hidden, and one on no window is kept here.
    private func setAside(_ ids: Set<Mark.ID>, of id: LiveAsks.Ask.ID) {
        letGoOfTour(of: id, because: "replaced")
        hideActions(of: id)
        guard !ids.isEmpty else { return }
        asideOnScreen += screenMarks.filter { ids.contains($0.id) }
        for surface in surfaces { surface.marks.removeAll { ids.contains($0.id) } }
        windows.setAside(ids)
        showMarks()
    }

    /// Shows set-aside marks again (`LiveAsks.Effect.restore`).
    private func bringBack(_ ids: Set<Mark.ID>) {
        windows.bringBack(ids)
        let back = asideOnScreen.filter { ids.contains($0.id) }
        asideOnScreen.removeAll { ids.contains($0.id) }
        if !back.isEmpty {
            let active = activeSurfaces()
            let markStyle = Settings.shared.data.ui.markStyle
            for mark in back { addToScreen(mark, among: active, markStyle: markStyle) }
        }
        showMarks()
    }

    /// Ends the responder's conversation and forgets what was asked, as clearing the screen does.
    private func endConversation() {
        closeNote()
        stopListening()
        spoken = nil
        strokeTimes = [:]
        letGoOfTour(because: "cleared")
        run(asks.reduce(.cleared))
        responder.stop()
        prepared = nil
        lastPicture = nil
    }

    // MARK: Esc

    private var escapeSnapshot: LiveEscape.Snapshot {
        /// Whether a mark that shows and is not leaving passes `test`.
        func shows(_ test: (Mark.ID) -> Bool) -> Bool {
            func staying(_ id: Mark.ID) -> Bool { !asks.isFinishing(id) && test(id) }
            return windows.containsShown(where: staying) || surfaces.contains { $0.marks.contains { staying($0.id) } }
        }
        return LiveEscape.Snapshot(
            isOn: isOn,
            screenIsFree: mayInk(),
            menuOpen: note?.menuOpen == true,
            note: note.map { $0.hasKeys ? .hasKeys : .withoutKeys } ?? LiveEscape.Note.none,
            replyFieldOpen: actionsPanels.values.contains(where: \.isTyping),
            askCanBeCancelled: asks.cancellable(sendsWait: sendsWait) != nil,
            tourRunning: focusRun != nil || stepClicks != nil,
            answerShown: shows(asks.isSettledAnswer),
            marksShown: shows { _ in true })
    }

    /// Holds Esc exactly while `LiveEscape` has a step for it, so with nothing to back out of it is the
    /// frontmost app's. The main run loop asks before each wait, so the key follows every change to
    /// what the snapshot reads, whatever made it.
    private func holdEscape() {
        let wanted = LiveEscape.next(escapeSnapshot) != nil
        guard wanted != (escapeKey != nil) else { return }
        escapeKey = wanted ? HotKey(keyCode: LiveEscape.keyCode, modifiers: 0, action: { [weak self] in self?.escape() }) : nil
    }

    /// Esc: the first step that applies, one per press. The hotkey takes the press while it is held;
    /// the note and the Reply field come here for a press before it is.
    func escape() {
        guard let step = LiveEscape.next(escapeSnapshot) else { return }
        Log.write("[live-ink] esc \(step.rawValue)")
        switch step {
        case .discardNote:
            discardNote()
        case .closeReplyField:
            actionsPanels.values.first(where: \.isTyping)?.closeField()
        case .cancelAsk:
            cancelAsk()
        case .endTour:
            letGoOfTour(because: "escape")
        case .closeAnswer:
            closeAnswer(by: .answerClosed)
        case .clearInk:
            clear()
        }
    }

    /// Whether a note to a session waits out a grace before it goes, which is what lets Esc stop it.
    private var sendsWait: Bool { Settings.shared.data.ui.sendGraceSeconds > 0 }

    /// Stops the newest ask under way: its sent note and any reply leave, the follow-up from a button
    /// puts its answer back, and its ink can be asked about again. The responder's turn is stopped when
    /// it was this ask's, and the next ask waiting goes. A session's note is withdrawn if its send is
    /// stored before the answer to this comes.
    private func cancelAsk() {
        guard let id = asks.cancellable(sendsWait: sendsWait) else { return }
        Log.write("[live-ink] stopping id=\(id)")
        run(asks.reduce(.cancelled(id, shown: shownIDs)))
        showMarks()
    }

    // MARK: Inking

    /// The chord pressed or let go: by the hand, through `HeldChord`, or by a script, through
    /// `live-ink-chord-down` and `live-ink-chord-up`.
    func chordChanged(_ change: HeldChord.Change) {
        switch change {
        case .began:
            guard mayInk() else {
                Log.write("[live-ink] not inking: the stack or the annotator is up")
                return
            }
            // The note stays, and ink drawn now is its ink too.
            chordInterrupted = false
            listening?.pressedAgain()
            responder.prepare()
            startInking()
        case .ended, .interrupted:
            chordInterrupted = change == .interrupted
            guard isInking else { return }
            if inking.contains(where: \.overlay.isTracking) { watchRelease() } else { finishInking() }
        }
    }

    private func startInking() {
        isInking = true
        FocusReturn.shared.sessionStarting()
        letGoOfFocus(because: "ink")
        drewWhileInking = false
        // Pressed again before the button came up: the stroke now ends without ending the inking.
        releaseWatch?.invalidate()
        releaseWatch = nil
        inking = activeSurfaces()
        inking.forEach { $0.overlay.setInking(true) }
        // The ink takes its colour from what is behind it.
        InkBackdrop.shared.refresh()
        let ui = Settings.shared.motionUI
        inking.forEach { $0.overlay.prepareField(ui: ui) }
        let mouse = NSEvent.mouseLocation
        hover(at: CGPoint(x: mouse.x, y: StateReport.primaryHeight - mouse.y))
        // The field waits, so holding the chord on the way to a key, as in a window manager's
        // Control-Option-arrow, does not flash it. A press shows it at once.
        fieldTimer?.invalidate()
        fieldTimer = Timer.scheduledTimer(withTimeInterval: Settings.shared.data.ui.liveInkFieldDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showFieldForChord() }
        }
        Log.write("[live-ink] inking")
    }

    private func stopInking(because reason: String) {
        hover(at: nil)
        isInking = false
        releaseWatch?.invalidate()
        releaseWatch = nil
        fieldTimer?.invalidate()
        chordShowsField = false
        holdField()
        inking.forEach { $0.overlay.setInking(false) }
        inking = []
        closeEmpty(fade: 0)
        Log.write("[live-ink] stopped: \(reason)")
    }

    private func strokeMoved(_ points: [CGPoint]) {
        if !points.isEmpty { showFieldForChord() }
        if let first = points.first, strokeBegan == nil {
            strokeBegan = Date()
            strokeScreenDiagonal = Self.screenDiagonal(at: first)
        }
        // A press that moves is drawing, not tapping.
        if let first = points.first, let last = points.last, hypot(last.x - first.x, last.y - first.y) > 4 { hover(at: nil) }
        let ui = Settings.shared.data.ui
        let longest = longestLine(for: points, ui: ui)
        let markStyle = ui.markStyle
        inking.forEach { $0.overlay.showPen(points, longest: longest, markStyle: markStyle) }
    }

    private func strokeEnded(_ points: [CGPoint], on surface: Surface) {
        let before = newInk.count
        take(InkHand.trailing(points, length: longestLine(for: points, ui: Settings.shared.data.ui)), on: surface, among: inking)
        strokeBegan = nil
        strokeScreenDiagonal = nil
        if newInk.count > before, let extent = newInk.last?.shapeExtent { prefetch(at: CGPoint(x: extent.midX, y: extent.midY)) }
        // The mark the preview was on has gone, or a stroke was drawn; the next move shows it again.
        hover(at: nil)
        if releaseWatch != nil { finishInking() }
    }

    /// The chord was let go: inking stops, and the new ink gets its note, with the keys. A chord cut
    /// short by a key, as a shortcut's start, gives the note the keys only when ink was drawn.
    private func finishInking() {
        stopInking(because: chordInterrupted ? "a key cut the chord short" : "the chord was let go")
        let noteHasKeys = !newInk.isEmpty && (drewWhileInking || listening != nil || !chordInterrupted) && showNote()
        drewWhileInking = false
        keepNoteWithItsInk()
        // What is said goes into the note; with no note there is nowhere for it to go.
        if note != nil { listening?.released() } else { stopListening() }
        // The chord's press, with Control held, made Vignette frontmost.
        if !noteHasKeys { FocusReturn.shared.restore(reason: "live ink inking") }
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

    // MARK: The pointer field

    /// The surfaces the pointer lab holds the pointer field on, at the inking level, passing every
    /// press through.
    private var labSurfaces: [Surface] = []

    /// Holds the pointer field on every screen for the pointer lab, or lets it go, so what the lab tunes
    /// is what inking shows.
    func previewField(_ on: Bool) {
        guard on != !labSurfaces.isEmpty else { return }
        labSurfaces = on ? activeSurfaces() : []
        holdField()
        if !on { closeEmpty(fade: 0) }
        Log.write("[live-ink] field preview \(on ? "on" : "off")")
    }

    /// The pointer field's delay passed, or a press came first: the field shows, and listening starts.
    private func showFieldForChord() {
        fieldTimer?.invalidate()
        guard !chordShowsField else { return }
        chordShowsField = true
        holdField()
        // The field goes to the screen first, so making the recognizer on this thread never holds it back.
        CATransaction.flush()
        listen()
    }

    /// Holds the pointer field up, in the current settings, on the surfaces taking ink while the chord
    /// shows it and on the pointer lab's, and lets it go on every other surface.
    private func holdField() {
        let ui = Settings.shared.motionUI
        let held = (chordShowsField ? inking : []) + labSurfaces
        for surface in surfaces {
            surface.overlay.holdField(held.contains { $0 === surface }, ui: ui)
        }
    }

    // MARK: Listening

    /// Starts listening, with speech on, as the pointer field shows: the chord on its way to a shortcut
    /// shows no field, so it never turns the microphone on either.
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
        listening.start { [weak self, weak listening] failure in
            Log.write("[speech] error \(failure.detail)")
            guard let self, let listening, self.listening === listening else { return }
            self.listening = nil
        }
        self.listening = listening
        typedOver = note.map { !$0.isEmpty } ?? false
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
        let empty = surfaces.filter { surface in
            surface.marks.isEmpty && !inking.contains { $0 === surface } && !labSurfaces.contains { $0 === surface }
        }
        empty.forEach { $0.overlay.close(after: fade) }
        surfaces.removeAll { surface in empty.contains { $0 === surface } }
    }

    private func showMarks() {
        let ui = Settings.shared.data.ui
        let pulsing = asks.pulsing
        let finishing = asks.finishing
        overDark.formIntersection(asks.answerMarks)
        let ids = Set(marks.map(\.id))
        hands = hands.filter { ids.contains($0.key) }
        for surface in surfaces {
            surface.overlay.show(surface.marks, markStyle: ui.markStyle, textStyle: ui.textStyle, drawingOn: drawingOn, pulsing: pulsing,
                                 finishing: finishing, overDark: overDark, hands: hands)
        }
        windows.show(markStyle: ui.markStyle, textStyle: ui.textStyle, drawingOn: drawingOn, pulsing: pulsing, finishing: finishing,
                     overDark: overDark, hands: hands)
        drawingOn = []
        hangNote()
        keepNoteWithItsInk()
        // Watched while the reply is out of sight too, as when its window is minimized, so its × and
        // buttons come back when it fades back in.
        if hasReply {
            watchPointer()
            pointerMoved()
        } else {
            stopWatchingPointer()
        }
    }

    /// Inking stops, since its surfaces are on the Space just left.
    private func spaceChanged() {
        guard isInking else { return }
        stopInking(because: "the Space changed")
    }

    /// Each surface covers its screen again; one whose screen is gone closes with its marks.
    private func screensChanged() {
        let screens = Dictionary(NSScreen.screens.compactMap { screen in Self.display(of: screen).map { ($0, screen) } },
                                 uniquingKeysWith: { first, _ in first })
        // The Dock changing size posts this too, and leaves every screen where it was: inking goes on.
        if isInking, inking.contains(where: { screens[$0.overlay.display]?.frame != $0.overlay.frame }) {
            stopInking(because: "the screens changed")
        }
        var dropped = Set<Mark.ID>()
        for surface in surfaces {
            if let screen = screens[surface.overlay.display] {
                surface.overlay.fit(to: screen)
            } else {
                dropped.formUnion(surface.marks.map(\.id))
                surface.marks = []
            }
        }
        // A mark that reaches onto a screen still here stays, with its part in the asks.
        let gone = dropped.subtracting(marks.map(\.id))
        if !gone.isEmpty { run(asks.reduce(.removed(gone))) }
        bringOntoScreens()
        closeEmpty(fade: 0)
        showMarks()
    }

    /// A mark on no window that a smaller screen left with no part on any screen moves the least way
    /// back onto the screen of the first surface it is on, as macOS moves a window.
    private func bringOntoScreens() {
        let frames = StateReport.screenFrames
        var moves: [Mark.ID: CGVector] = [:]
        for surface in surfaces {
            for mark in surface.marks where moves[mark.id] == nil {
                guard let extent = Self.drawnExtent(of: mark, sizes: answerSizes), !frames.contains(where: { $0.intersects(extent) }) else { continue }
                moves[mark.id] = Self.offset(moving: extent, into: surface.overlay.globalFrame)
            }
        }
        guard !moves.isEmpty else { return }
        for surface in surfaces {
            surface.marks = surface.marks.map { mark in moves[mark.id].map { LiveWindows.translated(mark, by: $0) } ?? mark }
        }
        Log.write("[live-ink] moved \(moves.count) onto the screen")
    }

    /// The least offset that puts `rect` inside `frame`, or its top-left corner at `frame`'s on a side
    /// where it is the larger.
    private static func offset(moving rect: CGRect, into frame: CGRect) -> CGVector {
        func shift(_ min: CGFloat, _ max: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            Mark.shiftInside(from: min - low, to: max - low, within: high - low) ?? low - min
        }
        return CGVector(dx: shift(rect.minX, rect.maxX, frame.minX, frame.maxX), dy: shift(rect.minY, rect.maxY, frame.minY, frame.maxY))
    }

    /// The diagonal of the screen holding `point`, in points.
    private static func screenDiagonal(at point: CGPoint) -> CGFloat {
        guard let screen = (StateReport.screen(at: point) ?? NSScreen.screens.first)?.frame else { return 0 }
        return hypot(screen.width, screen.height)
    }

    /// How much line the pen keeps of a stroke: `ui.inkLengthDiagonals` diagonals of the screen it began on, so a
    /// loop can go round as much of a large screen as of a small one.
    private func longestLine(for points: [CGPoint], ui: UITweaks) -> CGFloat {
        let diagonal = strokeScreenDiagonal ?? points.first.map(Self.screenDiagonal(at:)) ?? 0
        return ui.inkLengthDiagonals * diagonal
    }

    private static func display(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
