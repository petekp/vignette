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
    var surfaces: [Surface] = []
    /// The surfaces taking presses: the active Space's when the chord went down.
    private(set) var inking: [Surface] = []
    var chord: ModifierChord?
    private var observers: [(NotificationCenter, Any)] = []
    private let ownMenus = LiveMenus.Own()
    /// Runs out the pointer field's delay after the chord goes down.
    private(set) var fieldTimer: Timer?
    /// The chord shows the pointer field on the surfaces taking ink: its delay passed, or a press came.
    var chordShowsField = false
    /// Runs while a stroke outlives the chord, until the button is up: inking ends then.
    private(set) var releaseWatch: Timer?
    /// Takes the pointer's events while inking, so no app hears them (`LiveInkTap`).
    var tap: LiveInkTap?
    /// The surface the press under way began on, which takes its drags and its release, as the window
    /// server sends them to the window that took the press.
    var pressedSurface: Surface?
    /// Asked when the chord goes down: false while the stack or the annotator holds the screen, which
    /// the raised overlays would cover and take presses from.
    let mayInk: () -> Bool

    let responders = LiveResponders()
    /// The marks drawn on an app's window, which stay on it (docs/live-ink-step3-2026-10-05.md). The
    /// surfaces keep the rest: marks drawn where no window is.
    let windows = LiveWindows()
    /// The working sessions Send can reach, newest first, as the candidates found so far: once from
    /// the kept lists, then again as each client's fresh answer arrives.
    var listSessions: ((@escaping (DestinationChoice.Candidates) -> Void) -> Void)?
    /// Sends a note to a session through Send, as the card it becomes, which calls the session `title`,
    /// and answers on the main thread with the request and the session it reached, or why it was refused.
    var sendNote: ((NoteCard, AgentDestination, _ title: String, _ message: String,
                    @escaping (Result<SentNote, ScreenshotRequests.Refusal>) -> Void) -> Void)?
    typealias SentNote = (request: String, session: AgentDestination)
    /// Withdraws a note sent to a session that is still in its grace (Don't send), by its request id.
    var unsendNote: ((String) -> Void)?
    /// The × that dismisses an answer, shown while the pointer is over its note, and the ask it ends.
    private var dismissButton: LiveDismissButton?
    private var dismissing: LiveAsks.Ask.ID?
    /// Each answer's actions, under its reply while it is on the screen, by its ask.
    var actionsPanels: [LiveAsks.Ask.ID: LiveAnswerActions] = [:]
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
    /// The note on the ink no ask has been about, while there is some, or by the pointer before any
    /// ink (`keepNoteWithItsInk`).
    var note: LiveNotePopover?
    /// Where the note hangs, in global top-left points, from the mark its `anchor` names, or by the pointer.
    var notePlace: PopoverPlace?
    /// Listening to the person while they draw, with speech on. It can span several presses of the
    /// chord, so "this" and "that" drawn in two strokes are one note.
    var listening: LiveListening?
    /// Why speech cannot listen, or nil when it can. A note says so in its prompt.
    var speechProblem: String? {
        didSet { note?.speechProblem = speechProblem }
    }
    /// The note's words are the person's to keep: typed, or in the note before this listening began, so
    /// what they say no longer replaces them.
    var typedOver = false
    /// The final words of the last listening, while the note holds them as they were said, and when
    /// that listening began, which their times count from.
    var spoken: (words: [SpokenWord], began: Date)?
    /// What a listening that reached its limit before the note opened heard, for the note to take.
    var heardBeforeNote: (words: [SpokenWord], began: Date)?
    /// The chord was let go with no ink and no note, and listening runs on for `ListeningEnd.tail`:
    /// words it hears open the note by the pointer.
    var tailMayOpenNote = false
    /// When the chord last went down, which the log counts the first sound from.
    var keysDown = Date()
    /// When the stroke under way began.
    private var strokeBegan: Date?
    /// The diagonal of the screen the stroke under way began on, which sets how much line it keeps.
    private var strokeScreenDiagonal: CGFloat?
    /// When each of the person's strokes was drawn, so a spoken note can say which "this" is which.
    var strokeTimes: [Mark.ID: (began: Date, ended: Date)] = [:]
    /// Each note asked in, by its ask, on screen until the conversation has taken its place, or until
    /// it fades with nothing to take it.
    private var handing: [LiveAsks.Ask.ID: LiveNotePopover] = [:]
    /// The conversation that takes a note's place, once the note has settled into its look.
    private var handingTo: [LiveAsks.Ask.ID: Mark.ID] = [:]
    /// Who each ask goes to: the agent, and how the conversation's row names it.
    private var answerers: [LiveAsks.Ask.ID: (agent: AgentClient, name: String?)] = [:]
    /// What each ask to the responder sends, from when its packet came until the asks before it end
    /// (`LiveAsks.Effect.send`).
    private var held: [LiveAsks.Ask.ID: LiveResponder.Ask] = [:]
    /// Esc, held while `LiveEscape` has a step for it, with the chord's modifiers while it is held.
    var escapeKey: (key: HotKey, modifiers: UInt32)?
    /// Watches for the Esc that cancelled the hold to come up. Until it does, its repeats go nowhere.
    var escapeRepeats: Timer?
    /// Keeps Esc live ink's from the chord's release until the person goes elsewhere.
    var escapeAfterRelease: LiveEscapeAfterRelease?
    /// The marks drawn or picked since the chord last went down, and the note up then with its words
    /// and place, which Esc during the hold leaves as they were.
    var holdInk = Set<Mark.ID>()
    var noteBeforeHold: (note: LiveNotePopover, words: String, place: PopoverPlace?)?
    /// The note is sent because the person stopped talking (`liveInkSendWhenQuiet`).
    var sendingOnRelease = false
    /// The note's target picked last, which the next note starts on.
    var lastTarget: LiveNotePopover.Target?
    /// The asks since the screen was last cleared, and each mark's part in them.
    var asks = LiveAsks()
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
    var tourRunning: Bool { focusRun != nil || stepClicks != nil }
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
    final class Surface {
        let overlay: LiveInkOverlay
        var marks: [Mark] = []

        init(_ overlay: LiveInkOverlay) { self.overlay = overlay }
    }

    var isOn: Bool { chord != nil }

    /// Every mark, on every Space and window, once each, where it was last shown.
    var marks: [Mark] { screenMarks + windows.marks.map(\.mark) }

    /// The marks on screen now, the person's in the order they were drawn: a mark on a window is left
    /// out while its window is away, minimised or set aside.
    var shownMarks: [Mark] {
        var seen = Set<Mark.ID>()
        return inDrawnOrder(windows.marks.filter(\.shown).map(\.mark) + surfacesInSight.flatMap(\.marks).filter { seen.insert($0.id).inserted })
    }

    /// The surfaces on the Space the person sees. A surface on another Space keeps its marks out of sight.
    var surfacesInSight: [Surface] { surfaces.filter(\.overlay.isOnActiveSpace) }

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
        InkBackdrop.shared.isNearInk = { [weak self] in self?.pointerIsOnInk(reach: Self.backdropReach) ?? false }
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
            checkResponder()
            LivePacket.warmUp()
            InkMarkLayer.warmUp(scale: NSScreen.main?.backingScaleFactor ?? 2)
            chord = makeChord()
            let workspace = NSWorkspace.shared.notificationCenter
            observers = [
                (NotificationCenter.default, NotificationCenter.default.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.screensChanged() }
                }),
                (workspace, workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.spaceChanged() }
                }),
            ] + [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification].map { name in
                // No release comes once the Mac sleeps or the person switches user, so inking ends here.
                (workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if self?.isInking == true { self?.cutInkingShort(because: name.rawValue) } }
                })
            }
        } else {
            if isInking { stopInking(because: "live ink turned off") }
            endConversation()
            chord = nil
            for (center, observer) in observers { center.removeObserver(observer) }
            observers = []
            surfaces.forEach { $0.marks = [] }
            overMenus = []
            pinsAfterMenus = [:]
            asideOnScreen = []
            showMarks()
            surfaces.forEach { $0.overlay.close(after: LiveMarksLayer.removalFade) }
            surfaces = []
            windows.removeAll()
        }
        Log.write("[live-ink] \(on ? "on" : "off")")
    }

    /// Takes the pair chosen under Live Ink. The marks stay; a stroke under way ends.
    func takeChord() {
        guard isOn else { return }
        if isInking { cutInkingShort(because: "the chord changed") }
        chord = makeChord()
        Log.write("[live-ink] chord \(Settings.shared.data.liveInkChordChoice.glyphs)")
    }

    private func makeChord() -> ModifierChord {
        ModifierChord(Settings.shared.data.liveInkChordChoice.flags, tag: "live-ink", name: "the chord") { [weak self] change in
            self?.chordChanged(change)
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
        overMenus = []
        pinsAfterMenus = [:]
        asideOnScreen = []
        windows.removeAll()
        endConversation()
        showMarks()
        closeEmpty(fade: LiveMarksLayer.removalFade)
        Log.write("[live-ink] cleared \(count)")
        return count
    }

    /// The marks and the pointer field drawn again in the current settings.
    func applyTweaks() {
        windows.restyle()
        showMarks()
        holdField()
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
            "reply": asks.newest.flatMap(shownReply(of:)).map { [$0.note.minX, $0.note.minY, $0.note.width, $0.note.height].map { Int($0.rounded()) } } ?? NSNull(),
            "actions": newestPanel.map { panel -> Any in
                panel.buttons.map { ["title": $0.title, "frame": [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height].map { Int($0.rounded()) },
                                     "enabled": $0.enabled, "picked": $0.picked] }
            } ?? NSNull(),
            "replyField": newestPanel?.fieldFrame.map { [$0.minX, $0.minY, $0.width, $0.height].map { Int($0.rounded()) } } ?? NSNull(),
            "replyCancel": newestPanel?.cancelFrame.map { [$0.minX, $0.minY, $0.width, $0.height].map { Int($0.rounded()) } } ?? NSNull(),
            "dismiss": dismissButton.map { button -> Any in StateReport.topLeft(button.frame, primaryHeight: StateReport.primaryHeight) } ?? NSNull(),
            "noteTarget": note.map { panel -> Any in panel.target.responder.map { "responder \($0.rawValue)" } ?? "session" } ?? NSNull(),
            "responders": responders.stateJSON,
            "pair": Settings.shared.data.liveInkChordChoice.glyphs,
            "escape": (escapeRepeats == nil ? LiveEscape.next(escapeSnapshot)?.rawValue : nil) ?? NSNull(),
            "escapeHeld": escapeKey != nil,
            "escapeAfterRelease": escapeAfterRelease != nil,
            "ask": asks.newest.map(\.stateJSON) ?? NSNull(),
            "asks": asks.asks.map(\.stateJSON),
            "queued": asks.queued.count,
        ]
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
        if isInking { holdInk.insert(mark.id) }
        _ = asks.reduce(.drew(mark.id))
        if let points, let hand = InkHand(raw: points, mark: mark, feel: Settings.shared.data.ui.inkHandFeel) {
            hands[mark.id] = hand
            drawingOn.insert(mark.id)
        }
    }

    /// Puts a mark the person drew on the window under it, or on `surface` where there is none. Drawn
    /// over a menu while inking, it stays on `surface` until the menu has closed (`overMenus`).
    private func place(_ mark: Mark, on surface: Surface, among: [Surface], markStyle: MarkStyle) {
        let target = windows.target(under: LiveWindows.point(of: mark))
        if isInking, let extent = mark.shapeExtent, LiveMenus.open().contains(where: { $0.frame.intersects(extent) }) {
            overMenus.insert(mark.id)
            pinsAfterMenus[mark.id] = target?.id
            add(mark, on: surface, among: among, markStyle: markStyle)
        } else if let target {
            windows.pin(mark, to: target)
        } else {
            add(mark, on: surface, among: among, markStyle: markStyle)
        }
    }

    /// Marks drawn over a menu. A window's marks are drawn just above it, under the menu, and a
    /// surface rests under menus too, so these stay on the screen's surfaces, kept above the menu, until
    /// it has closed (`pinOverMenus`).
    private var overMenus: Set<Mark.ID> = []
    /// The window under each mark drawn over a menu, which it goes onto, where it is, once the menu has
    /// closed. One drawn where there is no window stays on its surface.
    private(set) var pinsAfterMenus: [Mark.ID: CGWindowID] = [:]

    /// Puts the marks drawn over a menu on the windows under them, and lets the surfaces that kept
    /// them above the menu down.
    private func pinOverMenus() {
        surfaces.forEach { $0.overlay.keepAboveMenus(false) }
        guard !overMenus.isEmpty else { return }
        let held = pinsAfterMenus
        let drawnOver = overMenus.count
        overMenus = []
        pinsAfterMenus = [:]
        let pins = screenMarks.compactMap { mark in held[mark.id].flatMap(windows.target(id:)).map { (mark: mark, target: $0) } }
        let pinned = Set(pins.map(\.mark.id))
        for surface in surfaces {
            surface.marks.removeAll { pinned.contains($0.id) }
            surface.overlay.marks.handOff(pinned)
        }
        windows.pin(pins)
        showMarks()
        closeEmpty(fade: 0)
        Log.write("[live-ink] pinned \(pins.count) of \(drawnOver) marks drawn over a menu")
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

    /// Shows what a tap at `point` would do, or nothing with no point or no mark.
    private func hover(at point: CGPoint?) {
        if let point { noteMayMove(from: point) }
        let surface = marks.isEmpty ? nil : point.flatMap { point in inking.first { $0.overlay.globalFrame.contains(point) } }
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
    func remove(_ ids: Set<Mark.ID>) {
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

    /// Adds `mark` to `surface`, and to each other one of `among` whose screen it draws on: its stroke,
    /// its arrowhead, its edge and its shadows, which reach less than `Mark.shadowSize` past the edge.
    private func add(_ mark: Mark, on surface: Surface, among: [Surface], markStyle: MarkStyle) {
        let drawn = Self.shapeExtent(of: mark, markStyle: markStyle) ?? .null
        for other in among where other === surface || other.overlay.globalFrame.intersects(drawn) {
            other.marks.append(mark)
        }
    }

    // MARK: Asking

    /// The person's own marks on screen now, oldest first: a failure's note is in their colour, but
    /// Vignette's.
    var ink: [Mark] { asks.ink(among: shownMarks) }

    /// The person's marks no ask has been about yet, oldest first.
    var newInk: [Mark] { asks.newInk(among: shownMarks) }

    var answerSizes: LiveAnswerLayout.Sizes { LiveAnswerLayout.Sizes(ui: Settings.shared.data.ui) }

    /// The note's ink, oldest first, on the screen or away with its window: the person's ink no ask has
    /// been about.
    var noteInk: [Mark] {
        let ids = asks.noteInk
        return inDrawnOrder(marks.filter { ids.contains($0.id) })
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
    var shownIDs: Set<Mark.ID> { Set(marks.map(\.id)).union(handingTo.values) }

    /// The open note's responder, else the one a new note starts on before its sessions are listed
    /// (`LiveNotePopover.start`). A script's `live-ink-ask` with no session asks it.
    var noteAgent: AgentClient {
        note?.target.responder
            ?? LiveNotePopover.start(pick: nil, handPicked: nil, conversing: responders.conversing, responders: responders.offers, list: []).agent
    }

    /// Asks the responder about the new ink, with `words` as its note, or about the ink asked about
    /// last when there is none new, as a follow-up. The picture is taken now, and the ask waits for the
    /// asks to the responder before it (`LiveAsks.Effect.send`). With `session`, sends the picture and
    /// the words to that working session instead, as a card that calls it `title` (`share`), at once.
    /// `note` is the note asked in, where it hangs and where its words are: the conversation takes its
    /// place, and a card draws the words there. `following` is the reply the person answered with `picked`: it stays, with
    /// their words as its question, and it and the answer's marks carry the thinking light until the
    /// next answer replaces them. A follow-up is about the ink asked about, and the note, with its new
    /// ink and its words, stays. With `pointer`, the ask has no ink: it is about the window under it.
    /// Answers whether an ask started, and why not.
    @discardableResult
    func ask(_ words: String, to agent: AgentClient, sendingTo session: (destination: AgentDestination, title: String)? = nil,
             from note: (panel: LiveNotePopover, place: PopoverPlace, tag: CGRect?)? = nil,
             following reply: Mark? = nil, picked: LiveAnswerActions.Pick? = nil, at pointer: CGPoint? = nil) -> Result<Void, LiveResponder.Failure> {
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        // A follow-up is not about the note's ink, and leaves the note, its words and what was said for it.
        let noteIDs = reply == nil ? [] : asks.noteInk
        if reply == nil { closeNote() }
        // The words as they were said, unless the person changed them in the note.
        let said = reply != nil ? nil : spoken.flatMap { LiveListening.text(of: $0.words).trimmingCharacters(in: .whitespacesAndNewlines) == trimmed ? $0 : nil }
        if reply == nil { spoken = nil }
        let fresh = reply == nil && pointer == nil ? newInk : []
        let following = reply.map { LiveAsks.Following(reply: $0, pick: picked ?? .reply, words: words) }
        let id: LiveAsks.Ask.ID
        let about: [Mark]
        let point: CGPoint
        switch asks.begin(among: shownMarks, following: following, words: trimmed, toSession: session != nil, sentOnRelease: sendingOnRelease,
                          at: pointer) {
        case .refused(let refusal, let effects):
            run(effects)
            return .failure(LiveResponder.Failure(reason: refusal.rawValue, detail: refusal.detail))
        case .began(let began, let asked, let centre, let effects):
            id = began
            about = asked
            point = centre
            answerers[id] = (agent, session?.title)
            run(effects)
        }
        let person = asks.drawnInk(ink.filter { !noteIDs.contains($0.id) }, for: id)
        if let note { handing[id] = note.panel }
        if let reply {
            put([reply], window: windows.window(of: reply.id), for: id)
        } else if let note, !trimmed.isEmpty {
            let conversation = LiveAnswerLayout.conversation(trimmed, agent: agent, answerer: session?.title, at: note.place,
                                                             sizes: answerSizes)
            _ = asks.reduce(.conversed(conversation, for: id))
            handOver(to: conversation, for: id)
        }
        let spot = note?.tag
        showMarks()
        let started = Date()
        let ui = Settings.shared.data.ui
        // The note's ink was planned and captured as its last stroke ended, while a menu drawn on was
        // still open; planned now, the menu would be gone from the picture.
        let captured = reply == nil && pointer == nil ? prepared.flatMap { $0.ink == Set(person.map(\.id)) ? $0 : nil } : nil
        let plan = captured?.plan ?? picturePlan(for: about)
        Log.write("[live-ink] asking id=\(id) new=\(fresh.count) about=\(about.count) words=\(trimmed.split(whereSeparator: \.isWhitespace).count) queued=\(asks.queued.count) picture=\(plan.forLog)")
        let early = captured?.packet
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
                if let session {
                    self?.share(packet, words: words, spoken: said, with: session.destination, titled: session.title, from: spot, for: id)
                } else {
                    self?.send(packet, words: words, spoken: said, about: about, new: Set(fresh.map(\.id)), started: started, to: agent, for: id)
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
                      new: Set<Mark.ID>, started: Date, to agent: AgentClient, for id: LiveAsks.Ask.ID) {
        guard asks.ask(id)?.phase == .looking else { return }
        let note = numberedNote(spoken, packet: packet) ?? words
        let person = asks.drawnInk(ink.filter { packet.holds($0) }, for: id)
        let spot = asks.ask(id)?.spot
        let asked = Self.askedBox(about, spot: spot)
        let near = packet.lines(near: asked)
        Log.write("[live-ink] packet ms=\(Int(Date().timeIntervalSince(started) * 1000)) app=\(packet.app ?? "none") lines=\(packet.lines.count) near=\(near.count) bytes=\(packet.picture.count)\(packet.detail == nil ? "" : " detail")"
                  + packet.areaForLog)
        held[id] = LiveResponder.Ask(
            content: { [weak self] conversation in
                guard let self else { return [] }
                let content = responders.content(of: packet, note: note, ink: person, new: new, near: near, pointer: spot, to: agent,
                                                 conversation: conversation)
                _ = asks.reduce(.pictureSent(fresh: content.fresh, for: id))
                return content.parts
            },
            onSay: { [weak self] say in self?.showSay(say, near: asked, packet: packet, for: id) },
            onAnswer: { [weak self] result in
                switch result {
                case .success(let answer):
                    self?.answered(answer, packet: packet, sent: self?.responders.linesSent(to: agent) ?? [], near: asked, for: id)
                case .failure(let failure): self?.failed(failure, for: id)
                }
            })
        let effects = asks.reduce(.arrived(.packetCame, for: id))
        if asks.ask(id)?.phase == .waiting { Log.write("[live-ink] waiting id=\(id) behind=\(asks.queued.firstIndex(of: id) ?? 0)") }
        run(effects)
    }

    /// Hands the responder ask `id`, whose turn has come.
    private func sendHeld(_ id: LiveAsks.Ask.ID) {
        guard let ask = held.removeValue(forKey: id), let agent = answerers[id]?.agent else { return }
        Log.write("[live-ink] sending id=\(id) agent=\(agent.rawValue)")
        if let failure = responders.ask(ask, to: agent) { failed(failure, for: id) }
    }

    /// Asks the responders whether they can answer, which decides the note's offer.
    func checkResponder(_ clients: [AgentClient] = AgentClient.allCases) {
        responders.check(clients) { [weak self] in
            guard let self else { return }
            note?.offer(responders.offers, conversing: responders.conversing)
        }
    }

    /// Sends the note to a working session through Send, with the words and where the ink is in the
    /// message, as a card: the window without the ink, with the person's ink on it and their words as
    /// a note, which is what the session is sent. Once the request is stored the ink and the note leave
    /// the window, and `LiveNoteCards` waits on the session's turn.
    private func share(_ packet: LivePacket, words: String, spoken: (words: [SpokenWord], began: Date)?, with session: AgentDestination,
                       titled title: String, from spot: CGRect?, for id: LiveAsks.Ask.ID) {
        var shared: Set<Mark.ID>?
        for case .share(let about) in asks.reduce(.arrived(.packetCame, for: id)) { shared = about }
        guard let about = shared else { return }
        guard let sendNote else { return letGoOfNote(of: id) }
        let numbered = numberedNote(spoken, packet: packet)
        let pointer = asks.ask(id)?.spot
        let message = packet.sessionLine(note: numbered ?? words, numbered: numbered != nil, pointer: pointer)
        // The same ink the picture has, so the card holds what the session sees and what leaves the window.
        let person = asks.drawnInk(ink.filter { packet.frame.intersects($0.shapeExtent ?? .null) }, for: id)
        let note = noteMark(words, about: about, packet: packet, at: spot)
        let shapes = person.filter { about.contains($0.id) && $0.kind != .text }.compactMap(\.shapeExtent)
        let inkBox = pointer.map { Self.askedBox([], spot: $0) }
            ?? (shapes.isEmpty ? person.compactMap(\.shapeExtent) : shapes).reduce(CGRect.null) { $0.union($1) }
        let card = NoteCard(picture: packet.picture, capture: packet.capture,
                            marks: packet.drawingMarks(person + (note.map { [$0] } ?? [])), pointScale: packet.scale,
                            window: packet.windowID, ink: inkBox, before: LiveNoteCards.before(packet, ink: inkBox))
        sendNote(card, session, title, message) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let (request, reached)):
                Log.write("[live-ink] sent to a session request=\(request) marks=\(card.marks.count)")
                // A row that starts a session is remembered as the session it started, so Return on the next note does not start another.
                if self.lastTarget == .session(session) { self.lastTarget = .session(reached) }
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

    /// Shows marks the ask has set leaving (`LiveAsks.finishing`) going, and removes them once they have.
    private func finish(_ ids: Set<Mark.ID>, _ how: LiveMarksLayer.Finish) {
        Log.write("[live-ink] \(how) marks=\(ids.count)")
        showMarks()
        DispatchQueue.main.asyncAfter(deadline: .now() + LiveMarksLayer.finishDuration(how)) { [weak self] in
            guard let self else { return }
            let effects = self.asks.reduce(.finished(ids))
            guard !effects.isEmpty else { return }
            self.run(effects)
            self.showMarks()
            self.closeEmpty(fade: 0)
        }
    }

    /// Closes ask `id`'s answer, by its × or by Esc: its marks leave, with the ink only it was about.
    func closeAnswer(_ id: LiveAsks.Ask.ID) {
        hideDismissButton()
        run(asks.reduce(.dismissed(id)))
    }

    /// How long a new note waits unseen for the window's text before showing where it opened.
    private static let revealLimit: TimeInterval = 0.8

    /// Starts capturing the window under the ink as a stroke ends, with the chord still held,
    /// so the note can open clear of the window's text without a capture of its own. It waits only
    /// for the glance at where the text is, which comes long before the packet.
    private func prefetch(at point: CGPoint) {
        prepared?.packet.cancel()
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

    /// Shows the note against its ink, where a hand would write it, from a glance at the window's
    /// frame and text: the one started as the stroke ended, which also serves an ask about the same
    /// ink, or a new one. Without one in `revealLimit`, the note shows where it opened.
    func prepare(beside newest: Mark, panel: LiveNotePopover) {
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
    typealias ShownReply = (popover: ReplyPopover, note: CGRect)

    /// `ask`'s reply, while it is up.
    private func shownReply(of ask: LiveAsks.Ask) -> ShownReply? {
        guard let say = ask.say, asks.answer(of: say.id) == ask.id, !asks.isFinishing(say.id),
              let popover = windows.popover(of: say.id) ?? surfaces.lazy.compactMap({ $0.overlay.popover(of: say.id) }).first,
              let note = popover.globalFrame
        else { return nil }
        return (popover, note)
    }

    /// The replies that are up, by their asks.
    func shownReplies() -> [LiveAsks.Ask.ID: ShownReply] {
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
        let under = Self.dismissTarget(at: point, in: asks, replies: replies, dismissing: dismissing,
                                       buttonFrame: dismissButton?.globalFrame)
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
                self?.closeAnswer(id)
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
        guard let answered = asks.ask(id), let said = answered.say, shownReply(of: answered) != nil,
              let agent = answerers[id]?.agent else { return }
        hideActions(of: id)
        // A new ask starts from the reply where it is now. Refused, it puts the answer back.
        guard var reply = marks.first(where: { $0.id == said.id }) else { return }
        reply.quote = words
        reply.notice = nil
        reply = LiveAnswerLayout.grown(reply, to: "", sizes: answerSizes)
        ask(words, to: agent, following: reply, picked: pick)
    }

    // MARK: Answering

    /// Vignette says why ask `id`, with no conversation, failed: in a reply hung from the ink it asked
    /// about, named for who the ask went to. The reply is the ask's, with its own ×.
    private func say(_ reason: String, for id: LiveAsks.Ask.ID) {
        guard let ask = asks.ask(id), let answerer = answerers[id] else { return }
        let near = Self.askedBox(shownMarks.filter { ask.about.contains($0.id) }, spot: ask.spot)
        guard !near.isNull else { showMarks(); return }
        let screen = StateReport.screenFrames.first { $0.intersects(near) } ?? near
        let scene = LiveAnswerLayout.Scene(room: screen.insetBy(dx: 8, dy: 8), ink: ink, text: [], notes: answerBoxes(except: id),
                                           screen: Self.visibleScreen(around: near))
        var reply = LiveAnswerLayout.reply("", quote: nil, from: near, scene: scene, sizes: answerSizes, agent: answerer.agent)
        reply.answerer = answerer.name
        reply = noticed(reply, reason)
        _ = asks.reduce(.conversed(reply, for: id))
        drawingOn.insert(reply.id)
        put([reply], window: nil, for: id)
    }

    /// The reply so far, in the conversation where the person asked, or with no question, as a popover
    /// hung from the ink. It keeps where it hangs, so it grows rather than jumping as words arrive.
    private func showSay(_ say: String, near asked: CGRect, packet: LivePacket, for id: LiveAsks.Ask.ID) {
        guard let agent = answerers[id]?.agent else { return }
        let effects = asks.reduce(.arrived(.replyCame, for: id))
        guard effects.contains(.showReply) else { return }
        run(effects)
        let note: Mark
        if let shown = asks.ask(id)?.say {
            note = LiveAnswerLayout.grown(shown, to: say, sizes: answerSizes)
        } else {
            let reply = LiveAnswerLayout.reply(say, quote: nil, from: asked, scene: scene(for: packet, answering: id), sizes: answerSizes,
                                               agent: agent)
            note = LiveAnswerLayout.grown(reply, to: say, sizes: answerSizes)
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
        guard let agent = answerers[id]?.agent else { return nil }
        let effects = asks.reduce(.arrived(.answerCame, for: id))
        guard effects.contains(.drawAnswer) else { return nil }
        run(effects)
        let targets = answer.marks.map { packet.target(of: $0, sent: sent) }
        let layout = LiveAnswerLayout.placed(for: answer, targets: targets, asked: asked,
                                             scene: scene(for: packet, answering: id), sizes: answerSizes, agent: agent,
                                             streamed: asks.ask(id)?.say, below: LiveAnswerActions.room(for: answer.actions),
                                             focusable: packet.windowID != nil)
        let placed = layout.marks
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
    func letGoOfFocus(because reason: String) {
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
    func run(_ effects: [LiveAsks.Effect]) {
        for effect in effects {
            switch effect {
            case .ended(let id): release(id)
            case .send(let id): sendHeld(id)
            case .interrupt: responders.cancel()
            case .removeAnswer(let id, let gone): removeAnswer(gone, of: id)
            case .setAside(let id, let ids): setAside(ids, of: id)
            case .restore(let reply, let reason, let aside, let followUp):
                if !aside.isEmpty { bringBack(aside) }
                restoreAnswer(reply, after: followUp, saying: reason)
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

    /// The answer a button was picked under is back as it was (`LiveAsks.Effect.restore`): the ask that
    /// followed it is let go and its answerer answers the answer's buttons and Reply again, its words
    /// and buttons come back, typed words wait in Reply again, and its row says why, unless the person
    /// stopped the ask.
    private func restoreAnswer(_ replyID: Mark.ID, after followUp: LiveAsks.Ask.ID?, saying reason: String?) {
        let answerer = followUp.flatMap { answerers[$0] }
        if let followUp { release(followUp) }
        guard let ask = asks.ask(withReply: replyID), var reply = ask.say else { return }
        if let answerer { answerers[ask.id] = answerer }
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
    func home(of mark: Mark, among surfaces: [Surface]) -> Surface? {
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
    func letGoOfTour(because reason: String) {
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
        responders.stop()
        prepared?.packet.cancel()
        prepared = nil
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
            ownMenus.close()
            // The note stays, and ink drawn now is its ink too.
            chordInterrupted = false
            listening?.pressedAgain()
            startInking()
        case .ended, .interrupted:
            chordInterrupted = change == .interrupted
            guard isInking else { return }
            if chordInterrupted, cancelForMissedEscape() { return }
            if inking.contains(where: \.overlay.isTracking) { watchRelease() } else { finishInking() }
        }
    }

    private func startInking() {
        let began = Date()
        keysDown = began
        isInking = true
        holdInk = []
        noteBeforeHold = note.map { ($0, $0.content.field.stringValue, notePlace) }
        escapeAfterRelease = nil
        inkings += 1
        FocusReturn.shared.sessionStarting()
        drewWhileInking = false
        // Pressed again before the button came up: the stroke now ends without ending the inking.
        releaseWatch?.invalidate()
        releaseWatch = nil
        inking = activeSurfaces()
        inking.forEach { $0.overlay.setInking(true) }
        startTap(since: began)
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

    /// With `keepingInkAboveMenus`, ink drawn over a menu stays above it, on surfaces kept at the inking
    /// level, until `pinOverMenus`; else it goes onto its windows now.
    func stopInking(because reason: String, keepingInkAboveMenus: Bool = false) {
        hover(at: nil)
        isInking = false
        releaseWatch?.invalidate()
        releaseWatch = nil
        fieldTimer?.invalidate()
        chordShowsField = false
        holdField()
        stopTap()
        // Every screen's part of a stroke under way fades before any screen hides its pen.
        inking.forEach { $0.overlay.fadePen() }
        inking.forEach { $0.overlay.setInking(false) }
        let raised = inking
        inking = []
        if keepingInkAboveMenus, !overMenus.isEmpty {
            raised.forEach { $0.overlay.keepAboveMenus(true) }
        } else {
            pinOverMenus()
        }
        closeEmpty(fade: 0)
        Log.write("[live-ink] stopped: \(reason)")
    }

    private func strokeMoved(_ points: [CGPoint]) {
        if let last = points.last { showFieldForChord(); noteMayMove(from: last) }
        if let first = points.first, strokeBegan == nil {
            strokeBegan = Date()
            strokeScreenDiagonal = Self.screenDiagonal(at: first)
        }
        // A press that moves is drawing, not tapping.
        if let first = points.first, let last = points.last, hypot(last.x - first.x, last.y - first.y) > 4 {
            hover(at: nil)
            prepareResponderForStroke()
        }
        let ui = Settings.shared.data.ui
        let longest = longestLine(for: points, ui: ui)
        let markStyle = ui.markStyle
        inking.forEach { $0.overlay.showPen(points, longest: longest, markStyle: markStyle) }
    }

    /// Starts the responder the note this ink goes to will be aimed at, so its first answer does not
    /// wait for a cold start. A note to a session starts no process, and a tap starts none. Called on
    /// every move of a stroke; `prepare` starts the process only once. With no note open, it is the
    /// one the next note will start on, which needs the sessions listed: once a chord hold, while a
    /// responder a note could start on has no process, and decided on the first complete answer. The
    /// note opens with that listing, and gets its later answers.
    private func prepareResponderForStroke() {
        if let note {
            if let client = note.target.responder { responders.prepare(client) }
            return
        }
        if lastTarget?.session == nil, let client = responders.conversing { return responders.prepare(client) }
        guard listing?.hold != inkings, responders.anyToStart else { return }
        let listing = LiveInkHoldListing(hold: inkings)
        self.listing = listing
        guard let listSessions else { return prepareNextNote(from: nil) }
        listSessions { [weak self] candidates in
            guard let self, self.listing === listing else { return }
            if listing.answer(candidates) { prepareNextNote(from: candidates) }
        }
    }

    var listing: LiveInkHoldListing?

    private func prepareNextNote(from candidates: DestinationChoice.Candidates?) {
        let client = LiveNotePopover.startingResponder(listed: candidates, remembered: lastTarget?.session,
                                                       conversing: responders.conversing, among: responders.offers)
        if let client { responders.prepare(client) }
    }

    private func strokeEnded(_ points: [CGPoint], on surface: Surface) {
        let before = newInk.count
        take(InkHand.trailing(points, length: longestLine(for: points, ui: Settings.shared.data.ui)), on: surface, among: inking)
        strokeBegan = nil
        strokeScreenDiagonal = nil
        if newInk.count > before, let extent = newInk.last?.shapeExtent {
            prefetch(at: CGPoint(x: extent.midX, y: extent.midY))
            showNoteWhileListening()
        }
        // The mark the preview was on has gone, or a stroke was drawn; the next move shows it again.
        hover(at: nil)
        if releaseWatch != nil { finishInking() }
    }

    /// The chord was let go: inking stops, and the new ink gets its note, with the keys. A chord cut
    /// short by a key, as a shortcut's start, gives the note the keys only when ink was drawn.
    ///
    /// A menu still open would take the note's keys, so it is closed first (`LiveMenus`), once the
    /// picture of the ink drawn on it is captured, and the note opens after. When it does not close, the
    /// note opens without the keys.
    private func finishInking() {
        stopInking(because: chordInterrupted ? "a key cut the chord short" : "the chord was let go", keepingInkAboveMenus: true)
        let opensNote = newInk.isEmpty ? noteHangsAtPointer || heardWords
            : drewWhileInking || listening != nil || heardBeforeNote != nil || !chordInterrupted
        drewWhileInking = false
        let menus = opensNote ? LiveMenus.open() : []
        guard !menus.isEmpty else {
            pinOverMenus()
            return settleInking(opensNote: opensNote, listensOn: newInk.isEmpty && !chordInterrupted)
        }
        let inking = inkings
        menusWaiting = (inking, note != nil)
        // The glance comes once the window is captured, the menu with it.
        if let glance = prepared?.glance {
            Task { @MainActor [weak self] in
                _ = await glance.value
                self?.closeMenus(menus, after: inking)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.revealLimit) { [weak self] in self?.closeMenus(menus, after: inking) }
    }

    /// Counts the inkings, so what one that ended still waits for is dropped once another starts: the
    /// chord let go again then opens the note.
    private(set) var inkings = 0
    /// The inking whose note waits for the capture before the menus close, and whether a note was up.
    private var menusWaiting: (inking: Int, noteWasUp: Bool)?

    private func closeMenus(_ menus: [LiveMenus.Window], after inking: Int) {
        guard let waiting = menusWaiting, waiting.inking == inking, inkings == inking, !isInking else { return }
        menusWaiting = nil
        LiveMenus.close(menus) { [weak self] closed in
            // Inking again keeps the ink above the menus, and its end pins it.
            guard let self, self.inkings == inking, !self.isInking else { return }
            self.pinOverMenus()
            guard self.isOn else { return }
            guard self.mayInk() else { return Log.write("[live-ink] no note: the stack or the annotator came up") }
            // A note asked from or closed while the menus closed stays closed.
            self.settleInking(opensNote: !waiting.noteWasUp || self.note != nil, takingKeys: closed)
        }
    }

    /// Opens the note on the new ink, with the keys unless `takingKeys` is false, and hands the keys back
    /// to the app the person was in when it does not take them.
    /// With `listensOn`, listening runs its tail even when no note opens.
    func settleInking(opensNote: Bool, takingKeys: Bool = true, listensOn: Bool = false) {
        let noteHasKeys = opensNote && showNote(takingKeys: takingKeys)
        keepNoteWithItsInk()
        if opensNote { keepEscapeAfterRelease() }
        listenOnceLetGo(keepingTail: listensOn)
        if !noteHasKeys { FocusReturn.shared.restore(reason: "live ink inking") }
    }

    /// The chord was let go during a stroke. The stroke keeps going to its release, and inking ends
    /// with it. A release that never reaches the overlay is read from the button's own state, as the
    /// flight layer's `watchRelease` does, and the stroke ends with the points it has.
    private func watchRelease() {
        releaseWatch?.invalidate()
        releaseWatch = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !LiveInkTap.isButtonDown else { return }
                self.releaseWatch?.invalidate()
                self.releaseWatch = nil
                self.inking.forEach { $0.overlay.endStroke() }
                self.finishInking()
            }
        }
    }

    // MARK: Surfaces

    /// The active Space's surface on every screen, made for the screens that have none there yet.
    func activeSurfaces() -> [Surface] {
        NSScreen.screens.compactMap { screen in
            guard let display = Self.display(of: screen) else { return nil }
            if let surface = surfaces.first(where: { $0.overlay.display == display && $0.overlay.isOnActiveSpace }) { return surface }
            let overlay = LiveInkOverlay(screen: screen, display: display)
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

    func showMarks() {
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

    /// How much line the pen keeps: `ui.inkLengthDiagonals` diagonals of the stroke's screen.
    private func longestLine(for points: [CGPoint], ui: UITweaks) -> CGFloat {
        let diagonal = strokeScreenDiagonal ?? points.first.map(Self.screenDiagonal(at:)) ?? 0
        return ui.inkLengthDiagonals * diagonal
    }
}
