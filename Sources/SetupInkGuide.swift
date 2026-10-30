import AppKit

// MARK: Pointing at the next step

/// The setup page's pointers at what to press next, in the agent's light: a ring round the next
/// Allow or Sign In button with its label, or, with every step taken, a note saying what to do now. They are laid
/// out as an answer's marks are (`LiveAnswerLayout`) and drawn by `LiveMarksLayer`.
@MainActor
final class SetupInkGuide {
    /// The next step: a permission to allow, then Codex's sign-in where it is offered
    /// (`ResponderStatus.codexSignInLeft`), or, with all taken, the page. Nothing is pointed at while
    /// the sign-in waits in the browser, since its button then cancels it.
    enum Pointing: Equatable {
        case accessibility, screenRecording, codexSignIn, signingIn, ready

        init(trusted: Bool, screenRecording: Bool, codexSignIn: Bool = false, signingIn: Bool = false) {
            self = !trusted ? .accessibility : !screenRecording ? .screenRecording
                : !codexSignIn ? .ready : signingIn ? .signingIn : .codexSignIn
        }

        /// The step pointed at, and the other steps' rows, which its label keeps off.
        var steps: (next: Step, others: [Step])? {
            switch self {
            case .accessibility: (.accessibility, [.screenRecording])
            case .screenRecording: (.screenRecording, [.accessibility])
            case .codexSignIn: (.codexSignIn, [.accessibility, .screenRecording])
            case .signingIn, .ready: nil
            }
        }
    }

    /// The names a step's row, the row's words and its button are found by, and the label written
    /// beside the button.
    struct Step {
        let row: String
        let words: String
        let button: String
        let label: String

        static let accessibility = Step(row: "accessibilityRow", words: "accessibilityWords",
                                        button: "accessibilityButton", label: "Start here")
        static let screenRecording = Step(row: "screenRecordingRow", words: "screenRecordingWords",
                                          button: "screenRecordingButton", label: "Then this")
        static let codexSignIn = Step(row: "codexSignInRow", words: "codexSignInWords",
                                      button: "codexSignInButton", label: "Then this")
    }

    let stage = SetupInkStage()
    let spots = ScreenSpots()
    static let footer = "footer"
    static let header = "header"
    private static let rows = [Step.accessibility.row, Step.screenRecording.row]

    /// What the marks shown point at, and where it was then, in global top-left points, and the agent
    /// they are drawn as.
    private var pointing: Pointing?
    private var aimedAt: CGRect?
    private var agent: String?
    private var shown: [Mark] = []
    private var leaving: [Mark.ID: LiveMarksLayer.Finish] = [:]
    private var dark = Set<Mark.ID>()

    /// Points at `target` as `agent` once the page is on the screen, asked again until it is, and
    /// again when what it points at changes size, as a button does when its title changes.
    func point(at target: Pointing, as agent: String) {
        let aim = aim(of: target)
        let moved = aim.map { aim in aimedAt.map { abs($0.width - aim.width) > 2 || abs($0.height - aim.height) > 2 } ?? true } ?? false
        guard target != pointing || moved || agent != self.agent, let frame = stage.globalFrame else { return }
        let new = target == .signingIn ? [] : marks(for: target, as: agent, onStageAt: frame)
        // An empty answer for a target that has marks means the page is not laid out yet.
        guard !new.isEmpty || target == .signingIn else { return }
        pointing = target
        aimedAt = aim
        self.agent = agent
        let old = shown.filter { leaving[$0.id] == nil }
        for mark in old { leaving[mark.id] = .dismissed }
        shown = shown + new
        if stage.isDark { dark.formUnion(new.filter { $0.kind != .text }.map(\.id)) }
        draw(drawingOn: Set(new.map(\.id)))
        Log.write("[setup] live ink pointing at \(target) marks=\(new.count) agent=\(agent)")
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
        agent = nil
        draw()
    }

    /// What `target`'s marks are laid out round, in global top-left points. The note's takes in
    /// Codex's row, so the note is laid out again when the row changes.
    private func aim(of target: Pointing) -> CGRect? {
        if let next = target.steps?.next { return spots.global(next.button) }
        guard target == .ready else { return nil }
        return (Self.rows + [Step.codexSignIn.row]).compactMap(spots.global).reduce(CGRect.null) { $0.union($1) }
    }

    private func draw(drawingOn: Set<Mark.ID> = []) {
        let ui = Settings.shared.data.ui
        stage.marks.show(shown, markStyle: ui.markStyle, textStyle: ui.textStyle, drawingOn: drawingOn, pulsing: [],
                         finishing: leaving, overDark: dark)
    }

    /// The marks for `target`, drawn as `agent`, in the stage's points, with the stage at `frame` in
    /// global top-left points.
    private func marks(for target: Pointing, as agent: String, onStageAt frame: CGRect) -> [Mark] {
        let back = CGVector(dx: -frame.minX, dy: -frame.minY)
        // The stage's frame rather than the window's: the first pointing can come while the page is
        // still sliding in, or before a new window's first layout, and the marks move with the page.
        let room = frame.insetBy(dx: 12, dy: 12)
        // The labels keep off the other steps' rows, the words of their own row and Codex's row, as
        // an answer keeps off the person's notes, and cover the title and the line under the rows as
        // little as they can.
        let rows = Self.rows.compactMap(spots.global)
        let footer = [Self.footer].compactMap(spots.global)
        let header = [Self.header].compactMap(spots.global)
        let codex = [Step.codexSignIn.row].compactMap(spots.global)
        let steps = target.steps
        let ownRow = steps?.next.row == Step.codexSignIn.row
        let keptOff = (steps.map { ($0.others.map(\.row) + [$0.next.words]).compactMap(spots.global) } ?? []) + (ownRow ? [] : codex)
        let scene = LiveAnswerLayout.Scene(room: room, ink: [], text: footer + header, notes: keptOff, screen: nil)
        let sizes = LiveAnswerLayout.Sizes(ui: Settings.shared.data.ui)
        let placed: [Mark]
        if let steps {
            guard let button = spots.global(steps.next.button) else { return [] }
            placed = LiveAnswerLayout.pointer(.circle, label: steps.next.label, at: button, scene: scene, sizes: sizes)
        } else {
            // Under the line below the rows, the room nothing else on the page takes.
            let page = (rows + footer).reduce(CGRect.null) { $0.union($1) }
            guard !page.isNull else { return [] }
            placed = [LiveAnswerLayout.note("Hold \(Settings.shared.data.liveInkChordChoice.glyphs) and draw anywhere", near: page, scene: scene,
                                            obstacles: rows + footer + header + codex, sizes: sizes, agent: agent)]
        }
        return placed.map { mark in
            var mark = LiveWindows.translated(mark, by: back)
            if mark.agent { mark.agentName = agent }
            return mark
        }
    }
}
