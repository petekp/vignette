import AppKit
import Combine
import SwiftUI

/// Placeholder copy for setup's live ink pages, until Pete picks the words.
enum SetupInkCopy {
    static let costNote = "When you ask, Claude sees a picture of the window, its title and its URL, through your own Claude Code. An ask costs about one to four cents."
    /// macOS asks to quit and reopen an app it has just let record the screen, since the grant
    /// reaches only a new process.
    static let reopenNote = "Once you allow Screen Recording, macOS asks to quit and reopen \(Identity.name). Setup opens again on this page."
}

// MARK: The title

/// The live ink page's title, "Live Ink" in cursive: the centre lines a hand writes it along, in three
/// strokes, "Live", the i's dot, then "Ink". The page writes them in the real ink, through the pen
/// the person's own strokes are drawn with.
enum SetupInkTitle {
    /// In points, y down, from the start of the baseline, in the order the pen goes.
    static let strokes: [[CGPoint]] = [
        [(34, -46), (44, -64), (55, -80), (62, -88), (57, -92), (48, -86), (40, -70), (33, -50), (26, -30), (18, -13), (10, -3),
         (1, 2), (-7, 0), (-7, -6), (2, -9), (15, -6), (27, 0), (38, -5), (45, -16), (49, -26), (47, -14), (48, -3), (55, 0),
         (62, -8), (66, -26), (69, -10), (73, 0), (79, -10), (84, -26), (88, -21), (95, -19), (102, -21), (107, -27), (102, -31),
         (96, -25), (95, -11), (101, -1), (111, 0), (121, -6)],
        [(49, -43), (52, -44), (54, -41), (52, -38), (49, -39), (48, -41), (50, -43)],
        [(147, -36), (154, -60), (166, -78), (178, -84), (175, -72), (169, -46), (162, -18), (155, -3), (145, 2), (138, -4),
         (145, -10), (160, -9), (172, -7), (178, -14), (180, -26), (180, -12), (180, 0), (183, -13), (190, -24), (198, -26),
         (201, -17), (201, -5), (205, 0), (212, -5), (218, -24), (224, -56), (230, -80), (225, -88), (218, -76), (215, -46),
         (213, -16), (213, 0), (217, -12), (224, -22), (232, -26), (236, -20), (230, -13), (221, -11), (229, -6), (236, -1),
         (246, -3)],
    ].map { $0.map { CGPoint(x: $0.0, y: $0.1) } }

    /// Room round the lines for the ink's width and glow, in points.
    private static let margin: CGFloat = 18

    private static let extent = InkStroke.bounds(of: strokes.flatMap { ArrowBody.Curve(through: $0).samples })

    /// The room the title takes on the page.
    static var size: CGSize { CGSize(width: extent.width + 2 * margin, height: extent.height + 2 * margin) }

    /// Stroke `index` in a room whose top-left is `origin`.
    static func stroke(_ index: Int, in origin: CGPoint) -> [CGPoint] {
        let shift = CGPoint(x: origin.x + margin - extent.minX, y: origin.y + margin - extent.minY)
        return strokes[index].map { CGPoint(x: $0.x + shift.x, y: $0.y + shift.y) }
    }
}

// MARK: A hand

/// The pointer's events a hand sends as it draws along a line, each with its time from when the pen
/// landed: closer together where the line turns, as a hand slows there, and where it lands and lifts.
/// The ink's width follows their spacing, as it does for the person's own strokes.
struct HandStroke: Equatable {
    let times: [TimeInterval]
    let points: [CGPoint]

    var duration: TimeInterval { times.last ?? 0 }

    /// A hand taking `duration` to draw the curve through `controls`, sending `rate` events a second.
    init(through controls: [CGPoint], duration: TimeInterval, rate: Double = 120) {
        let path = ArrowBody.Curve(through: controls)
        let curve = path.samples
        guard curve.count > 1, duration > 0 else {
            times = curve.map { _ in 0 }
            points = curve
            return
        }
        // The time to each point of the curve, at a speed that drops where it turns and at its ends.
        let lengths = path.lengths
        let total = max(lengths.last ?? 0, .ulpOfOne)
        var reached: [Double] = [0]
        for index in 1..<curve.count {
            let along = lengths[index] / total
            let ends = min(InkHand.ease(along / 0.12), InkHand.ease((1 - along) / 0.12))
            let speed = (0.35 + 0.65 * (1 - Self.turn(at: index, in: curve))) * (0.3 + 0.7 * ends)
            reached.append(reached[index - 1] + Double(lengths[index] - lengths[index - 1]) / Double(speed))
        }
        let scale = duration / max(reached.last ?? 1, .ulpOfOne)
        var times: [TimeInterval] = []
        var points: [CGPoint] = []
        var at = 1
        for event in 0...Int((duration * rate).rounded(.up)) {
            let time = min(Double(event) / rate, duration)
            while at < curve.count - 1, reached[at] * scale < time { at += 1 }
            let before = reached[at - 1] * scale, after = reached[at] * scale
            let t = after > before ? min(max(CGFloat((time - before) / (after - before)), 0), 1) : 1
            let a = curve[at - 1], b = curve[at]
            times.append(time)
            points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        self.times = times
        self.points = points
    }

    /// The events sent by `elapsed` seconds after the pen landed.
    func events(by elapsed: TimeInterval) -> [CGPoint] {
        let count = times.firstIndex { $0 > elapsed } ?? times.count
        return Array(points.prefix(count))
    }

    /// Where the hand is `elapsed` seconds after the pen landed, between the events either side.
    func position(at elapsed: TimeInterval) -> CGPoint? {
        guard let first = points.first else { return nil }
        guard let after = times.firstIndex(where: { $0 > elapsed }) else { return points.last }
        guard after > 0 else { return first }
        let t = CGFloat((elapsed - times[after - 1]) / (times[after] - times[after - 1]))
        let a = points[after - 1], b = points[after]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// How sharply the curve turns at `index`, from 0 for straight to 1 for a right angle or more.
    private static func turn(at index: Int, in curve: [CGPoint]) -> CGFloat {
        let reach = 2
        let a = curve[max(index - reach, 0)], b = curve[index], c = curve[min(index + reach, curve.count - 1)]
        let one = CGVector(dx: b.x - a.x, dy: b.y - a.y), two = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let lengths = hypot(one.dx, one.dy) * hypot(two.dx, two.dy)
        guard lengths > 0 else { return 0 }
        let cosine = (one.dx * two.dx + one.dy * two.dy) / lengths
        return min(acos(min(max(cosine, -1), 1)) / (.pi / 2), 1)
    }
}

// MARK: The demo

/// What the live ink page shows when it appears, as steps at times from then. Pure, so a test can
/// play it without a window. The hand writes the title, circles the keys and sends a note about them
/// to a Claude Code session. The readings of that session's turn are what `NoteCardWait` reads, as
/// it reads a real note's, and its end starts the done finish.
enum SetupInkDemo {
    enum Beat: Equatable {
        /// The hand holds Control and Option, or lets go.
        case chord(down: Bool)
        /// Writes stroke `index` of the title, over `SetupInkDemo.writing[index]`.
        case write(Int)
        case circleKeys
        case openNote
        /// The note's words, as typed so far.
        case type(String)
        /// Tab: the note's target moves to the next in its list.
        case nextTarget
        case send
        /// One reading of the session's turn.
        case reading(SessionTurn)
        /// The session's change: the page's keys grow.
        case growKeys
        /// The page's words come in, once the title is written.
        case showWords
    }

    struct Step: Equatable {
        let at: TimeInterval
        let beat: Beat
    }

    static let writing: [TimeInterval] = [1.15, 0.2, 1.2]
    static let circling: TimeInterval = 0.75
    static let words = "make these keys bigger"
    /// How long the keys take to grow, at full motion: slowly, so it reads as the session's work.
    static let growing: TimeInterval = 1.4
    /// How often a session's turn is read, as `LiveNoteCards` reads it.
    static let readingEvery: TimeInterval = 0.5

    static let steps: [Step] = {
        var steps: [Step] = []
        var at: TimeInterval = 0.5
        func add(_ beat: Beat, after gap: TimeInterval = 0) {
            at += gap
            steps.append(Step(at: at, beat: beat))
        }
        add(.chord(down: true))
        add(.write(0), after: 0.15)
        add(.write(1), after: writing[0] + 0.12)
        add(.write(2), after: writing[1] + 0.16)
        add(.chord(down: false), after: writing[2] + 0.1)
        add(.showWords, after: 0.25)
        add(.chord(down: true), after: 0.9)
        add(.circleKeys, after: 0.12)
        add(.chord(down: false), after: circling + 0.08)
        add(.openNote, after: 0.05)
        at += 0.45
        for count in 1...words.count { add(.type(String(words.prefix(count))), after: 0.055) }
        add(.nextTarget, after: 0.5)
        add(.nextTarget, after: 0.6)
        add(.send, after: 0.7)
        // The session takes the note at once and works, then its turn ends. The readings run a tick
        // past `TurnWatch.idleSettle`, since they land on display refreshes rather than to the millisecond.
        let sent = at
        steps.append(Step(at: sent + 0.1, beat: .reading(.busy)))
        for tick in 0...5 { steps.append(Step(at: sent + 0.35 + Double(tick) * readingEvery, beat: .reading(.idle))) }
        steps.append(Step(at: sent + 0.7, beat: .growKeys))
        return steps.sorted { $0.at < $1.at }
    }()
}

// MARK: The stage

/// Where a page's live ink is drawn: a view over the page, in its points, y down, holding the real
/// pen layers and the marks layer live ink draws with. It takes no presses.
final class SetupInkStage: NSView {
    let marks: LiveMarksLayer
    /// Runs each display refresh while `isRunning`, with the time that refresh will show, on the ink's
    /// own clock, so the hand moves just before the ink is drawn.
    var onFrame: ((CFTimeInterval) -> Void)?
    var isRunning = false { didSet { if isRunning != oldValue { runClock() } } }
    private let scale: CGFloat

    init() {
        scale = NSScreen.main?.backingScaleFactor ?? 2
        marks = LiveMarksLayer(scale: scale)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(marks)
        marks.host = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// A new pen, above the marks.
    func pen() -> InkMarkLayer {
        let pen = InkMarkLayer(scale: scale)
        layer?.addSublayer(pen)
        return pen
    }

    /// This view's frame, in global top-left points.
    var globalFrame: CGRect? {
        guard let window else { return nil }
        return StateReport.flipped(window.convertToScreen(convert(bounds, to: nil)))
    }

    /// This view's top-left corner, in global top-left points.
    var globalOrigin: CGPoint? { globalFrame?.origin }

    /// The marks drawn over a page are the agent's light on a dark window.
    var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        runClock()
    }

    private func runClock() {
        let runs = isRunning && window != nil
        InkClock.shared.onTick(self, runs ? { [weak self] in self?.onFrame?($0) } : nil)
    }
}

/// The stage, laid over a page.
struct SetupInkCanvas: NSViewRepresentable {
    let stage: SetupInkStage

    func makeNSView(context: Context) -> SetupInkStage { stage }
    func updateNSView(_ nsView: SetupInkStage, context: Context) {}
}

/// The parts of a page the ink is drawn round, by name, for the stage laid over it.
struct SetupInkAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Names this view's bounds for the ink stage over the page, beside the names inside it.
    func inkAnchor(_ name: String) -> some View {
        transformAnchorPreference(key: SetupInkAnchors.self, value: .bounds) { $0[name] = $1 }
    }

    /// Lays `stage` over this page.
    func inkStage(_ stage: SetupInkStage) -> some View {
        overlay { SetupInkCanvas(stage: stage).allowsHitTesting(false) }
    }

    /// Lays `stage` over this page, and hands `place` the page's named parts, in the stage's points,
    /// whenever they move.
    func inkStage(_ stage: SetupInkStage, place: @escaping ([String: CGRect]) -> Void) -> some View {
        overlayPreferenceValue(SetupInkAnchors.self) { anchors in
            GeometryReader { geometry in
                let rects = anchors.mapValues { geometry[$0] }
                SetupInkCanvas(stage: stage)
                    .allowsHitTesting(false)
                    .onAppear { place(rects) }
                    .onChange(of: rects) { place(rects) }
            }
        }
    }
}

// MARK: Playing the demo

/// Plays `SetupInkDemo` on the page's stage with live ink's own parts: the pen and `InkHand` for the
/// strokes, `InkStroke` and `InkSettle` for the loop, `LiveNotePopover` for the note, `NoteCardWait`
/// for the session's turn, and `LiveMarksLayer`'s thinking light and done finish. Nothing is sent and
/// nothing is captured: the note's targets after Claude are the demo's own.
@MainActor
final class SetupInkPlayer: ObservableObject {
    @Published private(set) var keysDown = false
    @Published private(set) var keysGrown = false
    @Published private(set) var wordsShown = false
    /// How far the second line has moved down, out of the note's way.
    @Published private(set) var lineTwoDrop: CGFloat = 0
    let stage = SetupInkStage()

    static let titleAnchor = "title"
    static let keysAnchor = "keys"
    static let lineAnchors = ["line1", "line2"]

    /// The page's parts, in the stage's points.
    private var title = CGRect.zero
    private var keys = CGRect.zero
    private var lines: [CGRect] = []
    private var played = false
    private var loggedWindow = false
    private var began: CFTimeInterval = 0
    private var next = SetupInkDemo.steps.count
    private struct Writing {
        let pen: InkMarkLayer
        let hand: HandStroke
        let began: CFTimeInterval
        var writer: InkHand.Pen
    }
    private var writing: [Writing] = []
    private var titlePens: [InkMarkLayer] = []
    private var loopPen: InkMarkLayer?
    private var loop: (mark: Mark, hand: InkHand)?
    private var note: LiveNotePopover?
    private var wait = NoteCardWait(reportsTurns: true, hasWindow: true, canLookAgain: false)

    /// The demo's targets after Claude: a Codex thread, then the Claude Code session the note goes to.
    private static let sessions: [AgentDestination] = {
        let now = Date()
        return [AgentDestination(id: "setup-demo-codex", name: "inbox", address: .codexThread(uuid: "setup-demo-codex"), lastUsed: now),
                AgentDestination(id: "setup-demo-claude", name: "vignette", address: .claudeSession("setup-demo-claude"),
                                 lastUsed: now.addingTimeInterval(-60))]
    }()

    func place(_ rects: [String: CGRect]) {
        if let title = rects[Self.titleAnchor] { self.title = title }
        lines = Self.lineAnchors.compactMap { rects[$0] }
        // The loop stays round the keys where they were, as they grow inside it.
        if let keys = rects[Self.keysAnchor], loop == nil, loopPen == nil { self.keys = keys }
        if played, next >= SetupInkDemo.steps.count, writing.isEmpty { rest() }
    }

    /// Plays the demo the first time the page appears. After that, and with motion off, shows the
    /// page as the demo leaves it.
    func play() {
        guard !played else { return rest() }
        played = true
        guard Settings.shared.motionScale > 0 else { return rest() }
        // Before the title's first stroke, which would otherwise wait for the gel's first drawing.
        InkMarkLayer.warmUp(scale: stage.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        began = CACurrentMediaTime()
        next = 0
        wait = NoteCardWait(reportsTurns: true, hasWindow: true, canLookAgain: false)
        stage.onFrame = { [weak self] in self?.refreshed(showing: $0) }
        stage.isRunning = true
        Log.write("[setup] live ink demo began")
    }

    /// The page went: the demo stops, and its ink and note leave with the page.
    func stop() {
        stage.isRunning = false
        stage.marks.hang(nil, place: nil)
        note?.fadeAway()
        note = nil
        guard next < SetupInkDemo.steps.count || loop != nil else { return }
        next = SetupInkDemo.steps.count
        writing = []
        // A title cut short is written whole the next time the page appears.
        titlePens.forEach { $0.removeFromSuperlayer() }
        titlePens = []
        loopPen?.removeFromSuperlayer()
        loopPen = nil
        loop = nil
        show([])
        keysDown = false
        lineTwoDrop = 0
        Log.write("[setup] live ink demo stopped")
    }

    /// The page as the demo leaves it: the title written, the words in and the keys grown.
    private func rest() {
        if titlePens.isEmpty, title != .zero {
            let feel = Settings.shared.data.ui.inkHandFeel
            for (index, duration) in SetupInkDemo.writing.enumerated() {
                let hand = HandStroke(through: SetupInkTitle.stroke(index, in: title.origin), duration: duration)
                let pen = stage.pen()
                pen.showPen(InkHand.stroke(hand.points, tapersEnd: true, feel: feel), settled: 0, longest: .greatestFiniteMagnitude,
                            markStyle: Settings.shared.data.ui.markStyle)
                titlePens.append(pen)
            }
        }
        wordsShown = true
        keysGrown = true
    }

    /// Each refresh, the demo as it stands at `now`, when that refresh shows: timed by the callback,
    /// the hand moved by one, two or three of its events a frame.
    private func refreshed(showing now: CFTimeInterval) {
        if !loggedWindow, let frame = stage.window.map({ StateReport.flipped($0.frame) }) {
            loggedWindow = true
            Log.write("[setup] live ink demo window=\([frame.minX, frame.minY, frame.width, frame.height].map { String(Int($0)) }.joined(separator: ","))")
        }
        while next < SetupInkDemo.steps.count, SetupInkDemo.steps[next].at <= now - began {
            run(SetupInkDemo.steps[next].beat, at: now)
            next += 1
        }
        draw(at: now)
        if next >= SetupInkDemo.steps.count, writing.isEmpty { stage.isRunning = false }
    }

    private func run(_ beat: SetupInkDemo.Beat, at now: CFTimeInterval) {
        let feel = Settings.shared.data.ui.inkHandFeel
        switch beat {
        case .chord(let down):
            keysDown = down
        case .write(let index):
            let pen = stage.pen()
            titlePens.append(pen)
            writing.append(Writing(pen: pen, hand: HandStroke(through: SetupInkTitle.stroke(index, in: title.origin),
                                                              duration: SetupInkDemo.writing[index]),
                                   began: now, writer: InkHand.Pen(feel: feel)))
        case .circleKeys:
            let pen = stage.pen()
            loopPen = pen
            // Round the room the keys take once grown, so they grow inside the loop.
            let grown = SetupInkKeys.row(height: SetupInkKeys.grown)
            let room = CGRect(x: keys.midX - grown.width / 2, y: keys.midY - grown.height / 2, width: grown.width, height: grown.height)
            writing.append(Writing(pen: pen, hand: HandStroke(through: InkSamples.handLoop(in: room.insetBy(dx: -26, dy: -11)),
                                                              duration: SetupInkDemo.circling),
                                   began: now, writer: InkHand.Pen(feel: feel)))
        case .openNote:
            openNote()
        case .type(let words):
            note?.put(words)
        case .nextTarget:
            note?.step(backward: false)
        case .send:
            note?.send()
            // Asked, it stays where it hangs until the turn ends, as live ink's does.
            stage.marks.hang(nil, place: nil)
            let effects = wait.handle(.sent, at: Date())
            if effects.contains(.watchTurn), let loop { show([loop.mark], pulsing: [loop.mark.id]) }
        case .reading(let turn):
            if wait.handle(.turn(turn, replied: false), at: Date()).contains(.sayDone) { done() }
        case .growKeys:
            keysGrown = true
        case .showWords:
            wordsShown = true
        }
    }

    /// Draws each stroke under way as far as its hand has got, and lets go of those it has finished.
    private func draw(at now: CFTimeInterval) {
        let markStyle = Settings.shared.data.ui.markStyle
        for index in writing.indices.reversed() {
            let elapsed = now - writing[index].began
            let hand = writing[index].hand
            let points = hand.events(by: elapsed)
            guard points.count > 1 else { continue }
            var stroke = writing[index].writer.stroke(through: points)
            // The pen takes whole events; its end goes on to where the hand is at this refresh.
            if let tip = hand.position(at: elapsed), let end = stroke.points.last, let width = stroke.widths.last,
               hypot(tip.x - end.x, tip.y - end.y) > 0.25 {
                stroke.points.append(tip)
                stroke.widths.append(width)
            }
            let pen = writing[index].pen
            pen.showPen(stroke, settled: writing[index].writer.settled.points.count, longest: .greatestFiniteMagnitude, markStyle: markStyle,
                        byClock: true)
            guard elapsed >= writing[index].hand.duration else { continue }
            let finished = writing.remove(at: index)
            if pen === loopPen { endLoop(finished.hand.points) }
        }
    }

    /// The loop is let go: it becomes the ellipse live ink makes of it and settles onto it, as the
    /// person's own does.
    private func endLoop(_ raw: [CGPoint]) {
        let ui = Settings.shared.data.ui
        defer {
            loopPen?.removeFromSuperlayer()
            loopPen = nil
        }
        guard case .ellipse(let frame) = InkStroke(raw, shortestArrow: ui.shortestArrow) else { return }
        let mark = Mark(geometry: .ellipse(frame))
        guard let hand = InkHand(raw: raw, mark: mark, feel: ui.inkHandFeel) else { return }
        loop = (mark, hand)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        show([mark], drawingOn: [mark.id])
        loopPen?.isHidden = true
        CATransaction.commit()
    }

    /// The note opens from the loop where live ink would hang it, with the demo's targets.
    private func openNote() {
        guard let loop, let window = stage.window, let origin = stage.globalOrigin else { return }
        let global = LiveWindows.translated(loop.mark, by: CGVector(dx: origin.x, dy: origin.y))
        // The page's words, as the glance at a window gives live ink its text: the title and the first
        // line. The second line moves out of the note's way, so it is not among them.
        let text = (lines.prefix(1) + [title]).map { $0.offsetBy(dx: origin.x, dy: origin.y) }
        // The note hangs inside the window, where the page is: with no screen, the rule keeps it in the room.
        let content = StateReport.flipped(window.convertToScreen(window.contentLayoutRect))
        let scene = LiveAnswerLayout.Scene(room: content.insetBy(dx: 8, dy: 8), ink: [global], text: text)
        guard var place = LiveAnswerLayout.noteHang(LiveNotePopover.placementSize, for: global, scene: scene) else { return }
        place.anchor = loop.mark.id
        let note = LiveNotePopover(at: place, target: .responder)
        note.setSessions(DestinationChoice.Candidates(destinations: Self.sessions, complete: true, fresh: true))
        self.note = note
        let staged = place.offsetBy(dx: -origin.x, dy: -origin.y)
        // A press on the note takes the keys, and letting go of them goes back to the setup window.
        FocusReturn.shared.sessionStarting()
        stage.marks.hang(note, place: staged, takingKeys: false)
        guard let lineTwo = lines.dropFirst().first, staged.body.intersects(lineTwo) else { return note.reveal() }
        // The line makes room first, and the note comes in once it has moved.
        lineTwoDrop = staged.body.maxY + Self.lineTwoGap - lineTwo.minY
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.makingRoom * Settings.shared.motionScale) { [weak self, weak note] in
            guard let note, self?.note === note else { return }
            note.reveal()
        }
    }

    /// Between the note and the second line below it, in points.
    private static let lineTwoGap: CGFloat = 10
    /// How long the second line takes to move out of the note's way, at full motion.
    static let makingRoom: CFTimeInterval = 0.3

    /// The session's turn ended: the ink turns green with its check and leaves, and the note with it.
    private func done() {
        guard let loop else { return }
        show([loop.mark], finishing: [loop.mark.id: .done])
        let leave = LiveMarksLayer.popoverLeave(.done)
        // The second line comes back once the note has gone from over its place.
        note?.fadeAway(after: leave.after, over: leave.fade) { [weak self] in
            guard let self, self.note == nil else { return }
            self.lineTwoDrop = 0
        }
        note = nil
        Log.write("[setup] live ink demo turn ended")
        DispatchQueue.main.asyncAfter(deadline: .now() + LiveMarksLayer.finishDuration(.done)) { [weak self] in
            guard let self, self.loop?.mark.id == loop.mark.id else { return }
            self.loop = nil
            self.show([])
            Log.write("[setup] live ink demo done")
        }
    }

    private func show(_ marks: [Mark], drawingOn: Set<Mark.ID> = [], pulsing: Set<Mark.ID> = [],
                      finishing: [Mark.ID: LiveMarksLayer.Finish] = [:]) {
        let ui = Settings.shared.data.ui
        stage.marks.show(marks, markStyle: ui.markStyle, textStyle: ui.textStyle, drawingOn: drawingOn, pulsing: pulsing,
                         finishing: finishing, hands: loop.map { [$0.mark.id: $0.hand] } ?? [:])
    }
}

// MARK: Pointing at the permissions

/// The setup page's pointers at what to press next, in the agent's light: a ring round the next
/// Allow button with its label, or, with both allowed, a note saying what to do now. They are laid
/// out as an answer's marks are (`LiveAnswerLayout`) and drawn by `LiveMarksLayer`.
@MainActor
final class SetupInkGuide {
    /// The next permission to allow, or, with both allowed, the page.
    enum Pointing: Equatable {
        case accessibility, screenRecording, ready

        init(trusted: Bool, screenRecording: Bool) {
            self = !trusted ? .accessibility : !screenRecording ? .screenRecording : .ready
        }

        /// The permission pointed at, and the other one.
        var permissions: (next: Permission, other: Permission)? {
            switch self {
            case .accessibility: (.accessibility, .screenRecording)
            case .screenRecording: (.screenRecording, .accessibility)
            case .ready: nil
            }
        }
    }

    /// The names a permission's row, the row's words and its Allow button are found by, and the label
    /// written beside the button.
    struct Permission {
        let row: String
        let words: String
        let button: String
        let label: String

        static let accessibility = Permission(row: "accessibilityRow", words: "accessibilityWords",
                                              button: "accessibilityButton", label: "Start here")
        static let screenRecording = Permission(row: "screenRecordingRow", words: "screenRecordingWords",
                                                button: "screenRecordingButton", label: "Then this")
    }

    let stage = SetupInkStage()
    let spots = ScreenSpots()
    static let footer = "footer"
    private static let rows = [Permission.accessibility.row, Permission.screenRecording.row]

    /// What the marks shown point at, and where it was then, in global top-left points.
    private var pointing: Pointing?
    private var aimedAt: CGRect?
    private var shown: [Mark] = []
    private var leaving: [Mark.ID: LiveMarksLayer.Finish] = [:]
    private var dark = Set<Mark.ID>()

    /// Points at `target` once the page is on the screen, asked again until it is, and again when what
    /// it points at changes size, as a button does when its title changes.
    func point(at target: Pointing) {
        let aim = aim(of: target)
        let moved = aim.map { aim in aimedAt.map { abs($0.width - aim.width) > 2 || abs($0.height - aim.height) > 2 } ?? true } ?? false
        guard target != pointing || moved, let frame = stage.globalFrame else { return }
        let new = marks(for: target, onStageAt: frame)
        guard !new.isEmpty else { return }
        pointing = target
        aimedAt = aim
        let old = shown.filter { leaving[$0.id] == nil }
        for mark in old { leaving[mark.id] = .dismissed }
        shown = shown + new
        if stage.isDark { dark.formUnion(new.filter { $0.kind != .text }.map(\.id)) }
        draw(drawingOn: Set(new.map(\.id)))
        Log.write("[setup] live ink pointing at \(target) marks=\(new.count)")
        guard !old.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + LiveMarksLayer.finishDuration(.dismissed)) { [weak self] in
            guard let self else { return }
            let gone = Set(old.map(\.id))
            self.shown.removeAll { gone.contains($0.id) }
            for id in gone { self.leaving[id] = nil }
            self.draw()
        }
    }

    func leave() {
        shown = []
        leaving = [:]
        pointing = nil
        aimedAt = nil
        draw()
    }

    /// What `target`'s marks are laid out round, in global top-left points.
    private func aim(of target: Pointing) -> CGRect? {
        if let next = target.permissions?.next { return spots.global(next.button) }
        return Self.rows.compactMap(spots.global).reduce(CGRect.null) { $0.union($1) }
    }

    private func draw(drawingOn: Set<Mark.ID> = []) {
        let ui = Settings.shared.data.ui
        stage.marks.show(shown, markStyle: ui.markStyle, textStyle: ui.textStyle, drawingOn: drawingOn, pulsing: [],
                         finishing: leaving, overDark: dark)
    }

    /// The marks for `target`, in the stage's points, with the stage at `frame` in global top-left points.
    private func marks(for target: Pointing, onStageAt frame: CGRect) -> [Mark] {
        let back = CGVector(dx: -frame.minX, dy: -frame.minY)
        // The stage's frame rather than the window's: the first pointing can come while the page is
        // still sliding in, or before a new window's first layout, and the marks move with the page.
        let room = frame.insetBy(dx: 12, dy: 12)
        // The labels keep off the other row and the words of their own, as an answer keeps off the
        // person's notes, and cover the line under the rows as little as they can.
        let rows = Self.rows.compactMap(spots.global)
        let footer = [Self.footer].compactMap(spots.global)
        let permissions = target.permissions
        let keptOff = permissions.map { [$0.other.row, $0.next.words].compactMap(spots.global) } ?? []
        let scene = LiveAnswerLayout.Scene(room: room, ink: [], text: footer, notes: keptOff, screen: nil)
        let sizes = LiveAnswerLayout.Sizes(ui: Settings.shared.data.ui)
        let placed: [Mark]
        if let permissions {
            guard let button = spots.global(permissions.next.button) else { return [] }
            placed = LiveAnswerLayout.pointer(.circle, label: permissions.next.label, at: button, scene: scene, sizes: sizes)
        } else {
            // Under the line below the rows, the room nothing else on the page takes.
            let page = (rows + footer).reduce(CGRect.null) { $0.union($1) }
            guard !page.isNull else { return [] }
            placed = [LiveAnswerLayout.note("Hold \(Settings.shared.data.liveInkChordChoice.glyphs) and draw anywhere", near: page, scene: scene, obstacles: rows + footer, sizes: sizes)]
        }
        return placed.map { mark in
            var mark = LiveWindows.translated(mark, by: back)
            if mark.agent { mark.agentName = LiveAnswerLayout.agentName }
            return mark
        }
    }
}

// MARK: The pages

/// The page's ⌃ and ⌥ caps, side by side, before and after the session makes them bigger.
enum SetupInkKeys {
    static let size: CGFloat = 24
    static let grown: CGFloat = 40
    static let padding: CGFloat = 5

    static func width(height: CGFloat) -> CGFloat { height * 1.12 }
    static func spacing(height: CGFloat) -> CGFloat { height * 0.16 }

    /// The two caps with the gap between them and the padding either side.
    static func row(height: CGFloat) -> CGSize {
        CGSize(width: 2 * width(height: height) + spacing(height: height) + 2 * padding, height: height)
    }
}

/// Setup's live ink page: the title written in ink, what live ink is, and whether to use it. The
/// demo plays once when it appears.
struct LiveInkPage: View {
    @ObservedObject var player: SetupInkPlayer
    /// Why Claude cannot answer, or nil when it can. Setup says so under the line about asking Claude.
    let claudeProblem: String?
    @ObservedObject private var settings = Settings.shared
    @StateObject private var held = HeldModifiers()

    var body: some View {
        VStack(spacing: 14) {
            Color.clear
                .frame(width: SetupInkTitle.size.width, height: SetupInkTitle.size.height)
                .inkAnchor(SetupInkPlayer.titleAnchor)
                .accessibilityElement()
                .accessibilityLabel("Live Ink")
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 52)
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    Text("Hold ").opacity(words)
                    keys.inkAnchor(SetupInkPlayer.keysAnchor)
                    Text(" and draw on anything on your screen.").opacity(words)
                }
                .font(.system(size: 15))
                // As tall as the grown keys from the start, so only the line's words move as they grow.
                .frame(height: SetupInkKeys.grown)
                .inkAnchor(SetupInkPlayer.lineAnchors[0])
                Text("Then ask Claude about it, or send it to a Claude Code or Codex session.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 340)
                    .opacity(words)
                    .inkAnchor(SetupInkPlayer.lineAnchors[1])
                    .offset(y: player.lineTwoDrop)
                    .animation(Anim.spring(SetupInkPlayer.makingRoom * settings.motionScale), value: player.lineTwoDrop)
                if let claudeProblem {
                    Text(claudeProblem)
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 340)
                        .opacity(words)
                }
            }
            .animation(Anim.spring(0.5 * settings.motionScale), value: player.wordsShown)
            .animation(Anim.spring(SetupInkDemo.growing * settings.motionScale, bounce: 0.2), value: player.keysGrown)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .inkStage(player.stage) { player.place($0) }
        .onAppear {
            held.start()
            player.play()
        }
        .onDisappear {
            held.stop()
            player.stop()
        }
    }

    private var words: Double { player.wordsShown ? 1 : 0 }

    private var keys: some View {
        let size = player.keysGrown ? SetupInkKeys.grown : SetupInkKeys.size
        return HStack(spacing: SetupInkKeys.spacing(height: size)) {
            key("⌃", down: player.keysDown || held.flags.contains(.control), size: size)
            key("⌥", down: player.keysDown || held.flags.contains(.option), size: size)
        }
        .padding(.horizontal, SetupInkKeys.padding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Control and Option")
    }

    /// A key, lit in the ink's colour while it is held, since holding it is what lets the ink draw.
    private func key(_ glyph: String, down: Bool, size: CGFloat) -> some View {
        let ink = (SRGB(hex: settings.data.ui.inkGelLight) ?? SRGB(hex: UITweaks().inkGelLight)!).cgColor
        return KeyboardKey(width: SetupInkKeys.width(height: size), height: size, down: down, motion: settings.motionScale, inset: 0, light: Color(cgColor: ink)) {
            Text(glyph).font(.system(size: size * 0.5, weight: .medium))
        }
    }
}

/// Setup's page for live ink's two permissions, after Use Live Ink. Each is asked for from its own
/// Allow button, and the agent's light points at the next one.
struct LiveInkSetupPage: View {
    let guide: SetupInkGuide
    let trusted: Bool
    let screenRecording: Bool
    /// Where the Allow buttons go: macOS, or the Setup Lab.
    let callbacks: SetupWindowController.Callbacks
    @State private var askedScreenRecording = false
    private let accessibility = SetupInkGuide.Permission.accessibility
    private let recording = SetupInkGuide.Permission.screenRecording

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("Set Up Live Ink").font(.title).bold()
                Text("macOS asks for two permissions.").foregroundStyle(.secondary)
            }
            .padding(.top, 60)
            Form {
                Section {
                    PermissionRow(symbol: "hand.draw", title: "Accessibility", reason: "So you can draw while holding \(Settings.shared.data.liveInkChordChoice.glyphs).",
                                  status: trusted ? .granted : .ask, isDefault: !trusted,
                                  spot: (guide.spots, accessibility.button, accessibility.words)) {
                        callbacks.askAccessibility()
                    }
                    .screenSpot(accessibility.row, in: guide.spots)
                    PermissionRow(symbol: "rectangle.dashed.badge.record", title: "Screen Recording",
                                  reason: "So Claude can see the window you drew on.",
                                  status: screenRecording ? .granted : .ask,
                                  isDefault: trusted && !screenRecording, button: askedScreenRecording ? "Open Settings…" : "Allow…",
                                  spot: (guide.spots, recording.button, recording.words)) {
                        if askedScreenRecording { callbacks.openScreenRecordingSettings() } else { callbacks.askScreenRecording() }
                        askedScreenRecording = true
                        callbacks.askedForScreenRecording()
                    }
                    .screenSpot(recording.row, in: guide.spots)
                }
                Section {} footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if !screenRecording { Text(SetupInkCopy.reopenNote) }
                        Text(SetupInkCopy.costNote)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .screenSpot(SetupInkGuide.footer, in: guide.spots)
                    // Room under the rows for the label pointing at the next Allow button.
                    .padding(.top, 30)
                }
            }
            .formStyle(.grouped).scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .inkStage(guide.stage)
        .onDisappear { guide.leave() }
    }
}
