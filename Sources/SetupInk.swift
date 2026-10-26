import AppKit
import Combine
import SwiftUI

/// Placeholder copy for setup's live ink pages, until Pete picks the words.
enum SetupInkCopy {
    static let costNote = "When you ask, Claude sees a picture of the window, its title and its URL, through your own Claude Code. An ask costs about one to four cents."
    /// macOS asks to quit and reopen an app it has just let record the screen, since the grant
    /// reaches only a new process.
    static let reopenNote = "macOS then asks to quit and reopen \(Identity.name). Setup opens again on this page."
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

    private static let extent: CGRect = {
        let points = strokes.flatMap { HandStroke.curve(through: $0) }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }()

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
        let curve = Self.curve(through: controls)
        guard curve.count > 1, duration > 0 else {
            times = curve.map { _ in 0 }
            points = curve
            return
        }
        // The time to each point of the curve, at a speed that drops where it turns and at its ends.
        let lengths = InkHand.lengths(curve)
        let total = max(lengths.last ?? 0, .ulpOfOne)
        var reached: [Double] = [0]
        for index in 1..<curve.count {
            let along = lengths[index] / total
            let ends = min(Self.ease(along / 0.12), Self.ease((1 - along) / 0.12))
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
        let reach = 4
        let a = curve[max(index - reach, 0)], b = curve[index], c = curve[min(index + reach, curve.count - 1)]
        let one = CGVector(dx: b.x - a.x, dy: b.y - a.y), two = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let lengths = hypot(one.dx, one.dy) * hypot(two.dx, two.dy)
        guard lengths > 0 else { return 0 }
        let cosine = (one.dx * two.dx + one.dy * two.dy) / lengths
        return min(acos(min(max(cosine, -1), 1)) / (.pi / 2), 1)
    }

    private static func ease(_ x: CGFloat) -> CGFloat { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }

    /// The centripetal Catmull–Rom curve through `controls`, a point about every `spacing` points.
    static func curve(through controls: [CGPoint], spacing: CGFloat = 1) -> [CGPoint] {
        guard controls.count > 1 else { return controls }
        let padded = [controls[0]] + controls + [controls[controls.count - 1]]
        var curve: [CGPoint] = []
        for index in 1..<(padded.count - 2) {
            let p0 = padded[index - 1], p1 = padded[index], p2 = padded[index + 1], p3 = padded[index + 2]
            func knot(_ a: CGPoint, _ b: CGPoint) -> CGFloat { max(sqrt(hypot(b.x - a.x, b.y - a.y)), 1e-4) }
            let t1 = knot(p0, p1), t2 = t1 + knot(p1, p2), t3 = t2 + knot(p2, p3)
            func lerp(_ a: CGPoint, _ b: CGPoint, _ ta: CGFloat, _ tb: CGFloat, _ t: CGFloat) -> CGPoint {
                CGPoint(x: (tb - t) / (tb - ta) * a.x + (t - ta) / (tb - ta) * b.x, y: (tb - t) / (tb - ta) * a.y + (t - ta) / (tb - ta) * b.y)
            }
            let steps = max(Int(hypot(p2.x - p1.x, p2.y - p1.y) / spacing), 1)
            for step in 0..<steps {
                let t = t1 + (t2 - t1) * CGFloat(step) / CGFloat(steps)
                let a1 = lerp(p0, p1, 0, t1, t), a2 = lerp(p1, p2, t1, t2, t), a3 = lerp(p2, p3, t2, t3, t)
                curve.append(lerp(lerp(a1, a2, 0, t2, t), lerp(a2, a3, t1, t3, t), t1, t2, t))
            }
        }
        curve.append(controls[controls.count - 1])
        return curve
    }

    /// A hand's loop round `rect`, from its upper left and a little past where it began.
    static func loop(round rect: CGRect) -> [CGPoint] {
        let first: CGFloat = -0.8 * .pi, turn: CGFloat = 2 * .pi + 0.45
        return (0...16).map { step in
            let angle = first + turn * CGFloat(step) / 16
            let wobble = 1 + 0.04 * sin(3 * angle + 1)
            return CGPoint(x: rect.midX + rect.width / 2 * wobble * cos(angle), y: rect.midY + rect.height / 2 * wobble * sin(angle))
        }
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

    /// This view's top-left corner, in global top-left points.
    var globalOrigin: CGPoint? {
        guard let window else { return nil }
        return StateReport.flipped(window.convertToScreen(convert(CGRect(x: 0, y: 0, width: 1, height: 1), to: nil))).origin
    }

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

/// Views a page's ink is drawn round, by name, asked where they are on the screen when the ink is
/// laid out. Unlike an anchor, it reaches out of a `Form`'s rows, which are hosted views of their own.
@MainActor
final class SetupInkSpots {
    private var views: [String: () -> NSView?] = [:]

    func register(_ name: String, _ view: NSView) { views[name] = { [weak view] in view } }

    /// Where `name` is, in global top-left points, while it is on the screen.
    func global(_ name: String) -> CGRect? {
        guard let view = views[name]?(), let window = view.window, view.bounds.width > 0 else { return nil }
        return StateReport.flipped(window.convertToScreen(view.convert(view.bounds, to: nil)))
    }
}

private struct SetupInkSpot: NSViewRepresentable {
    let name: String
    let spots: SetupInkSpots

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        spots.register(name, view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// Names this view for `spots`.
    func inkSpot(_ name: String, in spots: SetupInkSpots?) -> some View {
        background { if let spots { SetupInkSpot(name: name, spots: spots) } }
    }
}

private extension Settings {
    var answerSizes: LiveAnswerLayout.Sizes {
        let ui = data.ui
        return LiveAnswerLayout.Sizes(textSize: ui.liveInkTextSize, textWidth: ui.liveInkTextWidth, style: ui.textStyle)
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
            writing.append(Writing(pen: pen, hand: HandStroke(through: HandStroke.loop(round: room.insetBy(dx: -26, dy: -11)),
                                                              duration: SetupInkDemo.circling),
                                   began: now, writer: InkHand.Pen(feel: feel)))
        case .openNote:
            openNote()
        case .type(let words):
            note?.type(words)
        case .nextTarget:
            note?.nextTarget()
        case .send:
            note?.send()
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
            pen.showPen(stroke, settled: writing[index].writer.settled.points.count, longest: .greatestFiniteMagnitude, markStyle: markStyle)
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
        guard let place = LiveAnswerLayout.noteHang(LiveNotePopover.placementSize, for: global, scene: scene) else { return }
        let note = LiveNotePopover(at: place, target: .responder, takesKeys: false)
        note.offer(Self.sessions)
        self.note = note
        let body = place.body.offsetBy(dx: -origin.x, dy: -origin.y)
        guard let lineTwo = lines.dropFirst().first, body.intersects(lineTwo) else { return note.reveal() }
        // The line makes room first, and the note comes in once it has moved.
        lineTwoDrop = body.maxY + Self.lineTwoGap - lineTwo.minY
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
        let gone = (LiveMarksLayer.doneHold + LiveMarksLayer.doneAway) * Settings.shared.motionScale + 0.15
        DispatchQueue.main.asyncAfter(deadline: .now() + gone) { [weak self] in
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
    enum Pointing: Equatable { case accessibility, screenRecording, ready }

    let stage = SetupInkStage()
    let spots = SetupInkSpots()
    static let accessibilityButton = "accessibilityButton"
    static let screenRecordingButton = "screenRecordingButton"
    static let accessibilityRow = "accessibilityRow"
    static let screenRecordingRow = "screenRecordingRow"
    static let accessibilityWords = "accessibilityWords"
    static let screenRecordingWords = "screenRecordingWords"
    static let footer = "footer"

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
        guard target != pointing || moved, let origin = stage.globalOrigin, let window = stage.window else { return }
        let new = marks(for: target, origin: origin, window: window)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + LiveMarksLayer.doneAway * Settings.shared.motionScale + 0.15) { [weak self] in
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
        switch target {
        case .accessibility: spots.global(Self.accessibilityButton)
        case .screenRecording: spots.global(Self.screenRecordingButton)
        case .ready: [Self.accessibilityRow, Self.screenRecordingRow].compactMap(spots.global).reduce(CGRect.null) { $0.union($1) }
        }
    }

    private func draw(drawingOn: Set<Mark.ID> = []) {
        let ui = Settings.shared.data.ui
        stage.marks.show(shown, markStyle: ui.markStyle, textStyle: ui.textStyle, drawingOn: drawingOn, pulsing: [],
                         finishing: leaving, overDark: dark)
    }

    /// The marks for `target`, in the stage's points.
    private func marks(for target: Pointing, origin: CGPoint, window: NSWindow) -> [Mark] {
        let back = CGVector(dx: -origin.x, dy: -origin.y)
        let room = StateReport.flipped(window.frame).insetBy(dx: 12, dy: 12)
        // The labels keep off the other row and the words of their own, as an answer keeps off the
        // person's notes, and cover the line under the rows as little as they can.
        let rows = [Self.accessibilityRow, Self.screenRecordingRow].compactMap(spots.global)
        let ownWords = target == .accessibility ? Self.accessibilityWords : Self.screenRecordingWords
        let other = target == .accessibility ? Self.screenRecordingRow : Self.accessibilityRow
        let footer = [Self.footer].compactMap(spots.global)
        let keptOff = target == .ready ? [] : [other, ownWords].compactMap(spots.global)
        let scene = LiveAnswerLayout.Scene(room: room, ink: [], text: footer, notes: keptOff, screen: nil)
        let sizes = Settings.shared.answerSizes
        let placed: [Mark]
        switch target {
        case .accessibility, .screenRecording:
            let name = target == .accessibility ? Self.accessibilityButton : Self.screenRecordingButton
            guard let button = spots.global(name) else { return [] }
            let answer = LiveAnswer(say: "", marks: [AnswerMark(kind: .circle, label: target == .accessibility ? "Start here" : "Then this")])
            // The first mark is the reply, which no agent wrote here.
            placed = Array(LiveAnswerLayout.placed(for: answer, targets: [button], asked: button, scene: scene, sizes: sizes,
                                                   focusable: false).marks.dropFirst())
        case .ready:
            // Under the line below the rows, the room nothing else on the page takes.
            let page = (rows + footer).reduce(CGRect.null) { $0.union($1) }
            guard !page.isNull else { return [] }
            placed = [LiveAnswerLayout.note("Hold ⌃⌥ and draw anywhere", near: page, scene: scene, obstacles: rows + footer, sizes: sizes)]
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
    /// Screen Recording was asked for, which macOS answers by asking to quit and reopen the app.
    let askedForScreenRecording: () -> Void
    @State private var trusted = ModifierTap.trusted(prompt: false)
    @State private var screenRecording = ScreenRecording.granted
    @State private var askedScreenRecording = false
    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("Set Up Live Ink").font(.title).bold()
                Text("macOS asks for two permissions.").foregroundStyle(.secondary)
            }
            .padding(.top, 60)
            Form {
                Section {
                    PermissionRow(symbol: "hand.draw", title: "Accessibility", reason: "So you can draw while holding ⌃⌥.",
                                  status: trusted ? .granted : .ask, isDefault: !trusted,
                                  spot: (SetupInkGuide.accessibilityButton, SetupInkGuide.accessibilityWords, guide.spots)) {
                        Accessibility.request()
                    }
                    .inkSpot(SetupInkGuide.accessibilityRow, in: guide.spots)
                    PermissionRow(symbol: "rectangle.dashed.badge.record", title: "Screen Recording",
                                  reason: screenRecording ? screenRecordingReason : "\(screenRecordingReason) \(SetupInkCopy.reopenNote)",
                                  status: screenRecording ? .granted : .ask,
                                  isDefault: trusted && !screenRecording, button: askedScreenRecording ? "Open Settings…" : "Allow…",
                                  spot: (SetupInkGuide.screenRecordingButton, SetupInkGuide.screenRecordingWords, guide.spots)) {
                        if askedScreenRecording { ScreenRecording.openSystemSettings() } else { ScreenRecording.request() }
                        askedScreenRecording = true
                        askedForScreenRecording()
                    }
                    .inkSpot(SetupInkGuide.screenRecordingRow, in: guide.spots)
                }
                Section {} footer: {
                    Text(SetupInkCopy.costNote).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .inkSpot(SetupInkGuide.footer, in: guide.spots)
                        // Room under the rows for the label pointing at the next Allow button.
                        .padding(.top, 30)
                }
            }
            .formStyle(.grouped).scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .inkStage(guide.stage) { _ in }
        .onReceive(poll) { _ in
            trusted = ModifierTap.trusted(prompt: false)
            screenRecording = ScreenRecording.granted
            guide.point(at: pointing)
        }
        .onDisappear { guide.leave() }
    }

    private let screenRecordingReason = "So Claude can see the window you drew on."

    private var pointing: SetupInkGuide.Pointing {
        !trusted ? .accessibility : !screenRecording ? .screenRecording : .ready
    }
}
