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
    /// The working sessions Send can reach, newest first; it may answer twice, with a kept list and
    /// then a fresh one.
    var listSessions: ((@escaping ([AgentDestination]) -> Void) -> Void)?
    /// Sends a picture and a message to a session through today's Send: the request's id, or why it
    /// was refused.
    var sendToSession: ((Data, AgentDestination, String) -> Result<String, ScreenshotRequests.Refusal>)?
    /// The request ids of sends from live ink still waiting for their client's answer.
    private var sending: [String: AgentDestination] = [:]
    /// The person's marks some ask has been about. The rest are new, and the next ask is about them.
    private var asked = Set<Mark.ID>()
    /// A mark was drawn since the chord went down, so letting it go opens the note.
    private var drewWhileInking = false
    private var note: LiveNotePanel?
    /// The ask under way, or the last one.
    private var asking: AskState?
    /// The marks of the last answer, and of a failure's note: a new ask takes them off the screen.
    private var answerMarks = Set<Mark.ID>()
    /// The picture the responder's conversation has, so a follow-up about the same window, showing
    /// the same text, sends none.
    private var lastPicture: (conversation: Int, windowID: CGWindowID?, text: String)?
    /// Marks that draw themselves on at the next `showMarks`.
    private var drawingOn = Set<Mark.ID>()

    /// What `[state]` says about the ask under way, or the last one.
    private struct AskState {
        enum Phase: String { case looking, asking, answered, failed }
        var phase: Phase
        /// The person's marks it is about, which pulse while it is under way.
        var about: Set<Mark.ID>
        var reason: String?
        var picture = false
        /// The reply as it streams in, and once it is whole.
        var say: Mark?
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
        endConversation()
        showMarks()
        closeEmpty(fade: 0)
        Log.write("[live-ink] cleared \(count)")
        return count
    }

    /// The stack or the annotator is coming up under the raised overlays: inking stops, the stroke
    /// under way is dropped, and the chord must be pressed again to ink.
    func standAside() {
        closeNote()
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
                return ["type": mark.kind.rawValue, "frame": frame, "agent": mark.agent]
            },
            "new": newInk.count,
            "note": note.map { panel -> Any in StateReport.topLeft(panel.frame, primaryHeight: StateReport.primaryHeight) } ?? NSNull(),
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
            add(Mark(geometry: .ellipse(frame)), on: surface, among: among, markStyle: ui.markStyle)
            outcome = .drew(.ellipse)
            drewWhileInking = true
        case .arrow(let arrow):
            add(Mark(geometry: .arrow(arrow)), on: surface, among: among, markStyle: ui.markStyle)
            outcome = .drew(.arrow)
            drewWhileInking = true
        case .tap(let point):
            let sizes = answerSizes
            if let index = Self.markToErase(at: point, in: surface.marks, markStyle: ui.markStyle,
                                            noteBox: { LiveAnswerLayout.noteBox($0, sizes: sizes) }) {
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

    // MARK: Asking

    /// The person's own marks, oldest first: a failure's note is in their colour, but Vignette's.
    private var ink: [Mark] { marks.filter { !$0.agent && !answerMarks.contains($0.id) } }

    /// The person's marks no ask has been about yet, oldest first.
    private var newInk: [Mark] { ink.filter { !asked.contains($0.id) } }

    var responderState: LiveResponder.State { responder.state }

    private var answerSizes: LiveAnswerLayout.Sizes {
        let ui = Settings.shared.data.ui
        return LiveAnswerLayout.Sizes(textSize: ui.liveInkTextSize, textWidth: ui.liveInkTextWidth, style: ui.textStyle)
    }

    private func openNote() {
        let ink = newInk.compactMap(\.shapeExtent)
        guard let newest = ink.last else { return }
        closeNote()
        let ui = Settings.shared.data.ui
        let panel = LiveNotePanel(beside: newest, style: ui.textStyle, color: ui.markStyle.color(.person), edge: ui.markStyle.edgeColor.cgColor)
        panel.onAsk = { [weak self] words, target in
            self?.note = nil
            switch target {
            case .responder: self?.ask(words)
            case .session(let destination): self?.ask(words, sendingTo: destination)
            }
        }
        listSessions? { [weak panel] list in panel?.setSessions(list) }
        panel.onClose = { [weak self] in
            self?.note = nil
            Log.write("[live-ink] note closed")
        }
        note = panel
        Log.write("[live-ink] note open")
    }

    private func closeNote() {
        note?.dismiss()
        note = nil
    }

    /// Asks the responder about the new ink, with `words` as its note, or about the ink asked about
    /// last when there is none new, as a follow-up. With `session`, sends the picture and the words to
    /// that working session instead, whose reply comes back as a card. Answers whether an ask
    /// started, and why not.
    @discardableResult
    func ask(_ words: String, sendingTo session: AgentDestination? = nil) -> Result<Void, LiveResponder.Failure> {
        closeNote()
        let person = ink
        let fresh = newInk
        let about = fresh.isEmpty ? person.filter { asked.contains($0.id) } : fresh
        guard let point = about.last?.shapeExtent.map({ CGPoint(x: $0.midX, y: $0.midY) }) else {
            return .failure(LiveResponder.Failure(reason: "There's no ink to ask about.", detail: "no ink"))
        }
        if case .looking = asking?.phase { return .failure(LiveResponder.Failure(reason: "An ask is under way.", detail: "busy")) }
        if case .asking = asking?.phase { return .failure(LiveResponder.Failure(reason: "An ask is under way.", detail: "busy")) }
        removeAnswer()
        let ids = Set(about.map(\.id))
        asked.formUnion(ids)
        asking = AskState(phase: .looking, about: ids)
        showMarks()
        let started = Date()
        let ui = Settings.shared.data.ui
        Log.write("[live-ink] asking new=\(fresh.count) words=\(words.count)")
        Task { @MainActor [weak self] in
            do {
                let packet = try await LivePacket.build(at: point, ink: person, style: ui.textStyle, markStyle: ui.markStyle)
                if let session {
                    self?.share(packet, words: words, with: session)
                } else {
                    self?.send(packet, words: words, about: about, new: Set(fresh.map(\.id)), started: started)
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

    private func send(_ packet: LivePacket, words: String, about: [Mark], new: Set<Mark.ID>, started: Date) {
        guard asking?.phase == .looking else { return }
        asking?.phase = .asking
        let person = ink.filter { packet.frame.intersects($0.shapeExtent ?? .null) }
        Log.write("[live-ink] packet ms=\(Int(Date().timeIntervalSince(started) * 1000)) app=\(packet.app ?? "none") lines=\(packet.lines.count) bytes=\(packet.picture.count)\(packet.detail == nil ? "" : " detail")")
        let asked = about.compactMap(\.shapeExtent).reduce(CGRect.null) { $0.union($1) }
        responder.ask(LiveResponder.Ask(
            content: { [weak self] conversation in
                let same = self?.lastPicture.map { $0.conversation == conversation && $0.windowID == packet.windowID && $0.text == packet.textSignature } ?? false
                self?.lastPicture = (conversation, packet.windowID, packet.textSignature)
                self?.asking?.picture = !same
                var content: [[String: Any]] = []
                if !same {
                    content.append(Self.image(packet.picture))
                    if let detail = packet.detail { content.append(Self.image(detail.png)) }
                }
                content.append(["type": "text", "text": packet.message(note: words, ink: person, new: new, freshPicture: !same)])
                return content
            },
            onSay: { [weak self] say in self?.showSay(say, near: asked, packet: packet) },
            onAnswer: { [weak self] result in
                switch result {
                case .success(let answer): self?.answered(answer, packet: packet, near: asked)
                case .failure(let failure): self?.failed(failure)
                }
            }))
    }

    /// Hands the picture to a working session through today's Send, with the words and where the ink
    /// is in the message (decision 6), and says on the ink that it went.
    private func share(_ packet: LivePacket, words: String, with session: AgentDestination) {
        guard asking?.phase == .looking, let sendToSession else { return }
        var place = [packet.app, packet.title.map { "\"\($0)\"" }, packet.location].compactMap { $0 }.joined(separator: ", ")
        if place.isEmpty { place = "the screen" }
        let message = (words.isEmpty ? "" : words + "\n\n") + "Drawn with Vignette's live ink on \(place)."
        switch sendToSession(packet.picture, session, message) {
        case .success(let request):
            sending[request] = session
            asking?.phase = .answered
            Log.write("[live-ink] sent to a session request=\(request)")
            say("Sending to \(session.project)")
        case .failure(let refusal):
            failed(LiveResponder.Failure(reason: "Not sent. " + refusal.reason, detail: "send refused"))
        }
    }

    /// A send's client answered: the note on the ink says how it went.
    func delivered(request: String, _ state: SendNotice.State, reason: String?) {
        guard let session = sending.removeValue(forKey: request) else { return }
        switch state {
        case .sent: say("Sent to \(session.project). Its reply comes back as a card.")
        case .queued: say("Queued for \(session.project). " + (reason ?? ""))
        case .uncertain: say("Check \(session.project). " + (reason ?? ""))
        default: say("Not sent. " + (reason ?? ""))
        }
    }

    /// Vignette's own note beside the ink asked about, in the person's colour, replacing the last.
    private func say(_ words: String) {
        guard let about = asking?.about else { return }
        removeAnswer()
        let near = marks.filter { about.contains($0.id) }.compactMap(\.shapeExtent).reduce(CGRect.null) { $0.union($1) }
        guard !near.isNull else { showMarks(); return }
        let screen = activeSurfaces().map(\.overlay.globalFrame).first { $0.intersects(near) } ?? near
        let scene = LiveAnswerLayout.Scene(room: screen.insetBy(dx: 8, dy: 8), ink: ink, text: [])
        var note = LiveAnswerLayout.note(words.trimmingCharacters(in: .whitespaces), near: near, scene: scene,
                                         obstacles: scene.ink.compactMap(\.shapeExtent), sizes: answerSizes)
        note.agent = false
        note.agentName = nil
        answerMarks.insert(note.id)
        drawingOn.insert(note.id)
        put([note])
    }

    private static func image(_ png: Data) -> [String: Any] {
        ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]]
    }

    private func scene(for packet: LivePacket) -> LiveAnswerLayout.Scene {
        let screen = activeSurfaces().map(\.overlay.globalFrame).first { $0.intersects(packet.frame) } ?? packet.frame
        let room = packet.frame.intersection(screen).insetBy(dx: 8, dy: 8)
        return LiveAnswerLayout.Scene(room: room.isNull ? packet.frame : room, ink: ink,
                                      text: packet.lines.map { packet.global($0.box) })
    }

    /// The reply so far, as a note beside the ink. It keeps the spot it first took, so it grows in
    /// place rather than jumping as words arrive.
    private func showSay(_ say: String, near asked: CGRect, packet: LivePacket) {
        guard asking?.phase == .asking else { return }
        let scene = scene(for: packet)
        let note: Mark
        if let shown = asking?.say {
            note = LiveAnswerLayout.grown(shown, to: say, near: asked, scene: scene, sizes: answerSizes)
        } else {
            note = LiveAnswerLayout.note(say, near: asked, scene: scene, obstacles: LiveAnswerLayout.obstacles(in: scene), sizes: answerSizes)
            drawingOn.insert(note.id)
        }
        asking?.say = note
        answerMarks.insert(note.id)
        put([note])
    }

    private func answered(_ answer: LiveAnswer, packet: LivePacket, near asked: CGRect) {
        guard asking != nil else { return }
        let targets = answer.marks.map { target(of: $0, in: packet) }
        let placed = LiveAnswerLayout.marks(for: answer, targets: targets, asked: asked, scene: scene(for: packet), sizes: answerSizes,
                                            streamed: asking?.say)
        // A reply that streamed in is on the screen already, so only the rest draw themselves on.
        drawingOn.formUnion(placed.map(\.id).filter { $0 != asking?.say?.id })
        asking?.phase = .answered
        asking?.say = placed.first
        answerMarks.formUnion(placed.map(\.id))
        Log.write("[live-ink] drew answer marks=\(placed.count - 1) dropped=\(targets.filter { $0 == nil }.count)")
        put(placed)
    }

    /// Where an answer's mark points, in global top-left points: a line, the words within it that the
    /// mark names, or its box. Words Vision gives no box for fall back to the line.
    private func target(of mark: AnswerMark, in packet: LivePacket) -> CGRect? {
        if let id = mark.line, let line = packet.lines.first(where: { $0.id == id }) {
            if let words = mark.words, let range = line.recognized.string.range(of: words, options: [.caseInsensitive]),
               let box = try? line.recognized.boundingBox(for: range)?.boundingBox {
                return packet.global(CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
            }
            return packet.global(line.box)
        }
        return mark.box.map(packet.global)
    }

    /// The note says why beside the ink, in the person's colour, since Vignette says it, not the agent.
    private func failed(_ failure: LiveResponder.Failure) {
        guard asking != nil else { return }
        Log.write("[live-ink] error ask \(failure.detail)")
        asking?.phase = .failed
        asking?.reason = failure.reason
        say(failure.reason)
    }

    /// Adds `placed` to the active Space's surfaces, replacing marks of the same id.
    private func put(_ placed: [Mark]) {
        let active = activeSurfaces()
        let markStyle = Settings.shared.data.ui.markStyle
        for mark in placed {
            for surface in surfaces { surface.marks.removeAll { $0.id == mark.id } }
            let centre = mark.shapeExtent ?? LiveAnswerLayout.noteBox(mark, sizes: answerSizes) ?? .zero
            let home = active.first { $0.overlay.globalFrame.contains(CGPoint(x: centre.midX, y: centre.midY)) } ?? active.first
            if let home { add(mark, on: home, among: active, markStyle: markStyle) }
        }
        showMarks()
        closeEmpty(fade: 0)
    }

    /// Takes the last answer's marks, or the last failure's note, off the screen.
    private func removeAnswer() {
        guard !answerMarks.isEmpty else { return }
        for surface in surfaces { surface.marks.removeAll { answerMarks.contains($0.id) } }
        answerMarks = []
    }

    /// Ends the responder's conversation and forgets what was asked, as clearing the screen does.
    private func endConversation() {
        closeNote()
        responder.stop()
        asked = []
        answerMarks = []
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
            responder.prepare()
            startInking()
        case .ended:
            guard isInking else { return }
            if inking.contains(where: \.overlay.isTracking) { watchRelease() } else { finishInking() }
        }
    }

    private func startInking() {
        isInking = true
        drewWhileInking = false
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
        if releaseWatch != nil { finishInking() }
    }

    /// The chord was let go: inking stops, and ink drawn while it was held gets the note.
    private func finishInking() {
        stopInking()
        if drewWhileInking, !newInk.isEmpty { openNote() }
        drewWhileInking = false
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
        let ui = Settings.shared.data.ui
        let pulsing = asking.map { $0.phase == .looking || $0.phase == .asking ? $0.about : [] } ?? []
        for surface in surfaces {
            surface.overlay.show(surface.marks, markStyle: ui.markStyle, textStyle: ui.textStyle, drawingOn: drawingOn, pulsing: pulsing)
        }
        drawingOn = []
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
