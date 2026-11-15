import AppKit
import Combine
import SwiftUI

// MARK: Playing the demo

/// Plays `SetupInkDemo` on the page's stage with live ink's own parts: the pen and `InkHand` for the
/// strokes, `InkStroke` and `InkSettle` for the loop, `LiveNotePopover` for the note, `NoteCardWait`
/// for the session's turn, and `LiveMarksLayer`'s thinking light and done finish. Nothing is sent and
/// nothing is captured: the note's targets after its responder are the demo's own.
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
    /// Which agent the note starts on: Codex where only Codex can answer, else Claude.
    var responders: ResponderStatus?

    /// The demo's targets after its responder: a Codex thread, then the note's Claude Code session.
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

    /// The page went: the demo stops, and its ink and note leave with it.
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
        let note = LiveNotePopover(at: place)
        let agent = responders?.namedAgent ?? .claude
        note.offer([.able(agent)], conversing: nil)
        note.setSessions(DestinationChoice.Candidates(destinations: Self.sessions, complete: true, fresh: true))
        Log.write("[setup] live ink demo note responder=\(agent.rawValue)")
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
    /// How long the second line takes to move out of the note's way at full motion.
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

// MARK: The pages

/// Setup's live ink page: the title written in ink, what live ink is, and whether to use it. The
/// demo plays once when it appears.
struct LiveInkPage: View {
    @ObservedObject var player: SetupInkPlayer
    /// Says which agent to ask, or why Claude cannot answer when neither can (`askLine`).
    @ObservedObject var responders: ResponderStatus
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
                // With no room for a third line, why Claude cannot answer takes this one's place.
                Text(responders.askLine)
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 340)
                    .contentTransition(.opacity)
                    .opacity(words)
                    .inkAnchor(SetupInkPlayer.lineAnchors[1])
                    .offset(y: player.lineTwoDrop)
                    .animation(Anim.spring(SetupInkPlayer.makingRoom * settings.motionScale), value: player.lineTwoDrop)
            }
            .animation(Anim.spring(0.5 * settings.motionScale), value: player.wordsShown)
            .animation(Anim.spring(0.5 * settings.motionScale), value: responders.askLine)
            .animation(Anim.spring(SetupInkDemo.growing * settings.motionScale, bounce: 0.2), value: player.keysGrown)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .inkStage(player.stage) { player.place($0) }
        .onAppear {
            held.start()
            player.responders = responders
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
        let pair = settings.data.liveInkChordChoice.keys
        return HStack(spacing: SetupInkKeys.spacing(height: size)) {
            ForEach(pair, id: \.glyph) { cap in
                key(cap.glyph, down: player.keysDown || held.flags.contains(cap.flag), size: size)
            }
        }
        .padding(.horizontal, SetupInkKeys.padding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pair.map(\.name).joined(separator: " and "))
    }

    /// A key, lit in the ink's colour while it is held, since holding it is what lets the ink draw.
    private func key(_ glyph: String, down: Bool, size: CGFloat) -> some View {
        let ink = (SRGB(hex: settings.data.ui.inkGelLight) ?? SRGB(hex: UITweaks().inkGelLight)!).cgColor
        return KeyboardKey(width: SetupInkKeys.width(height: size), height: size, down: down, motion: settings.motionScale, inset: 0, light: Color(cgColor: ink)) {
            Text(glyph).font(.system(size: size * 0.5, weight: .medium))
        }
    }
}

