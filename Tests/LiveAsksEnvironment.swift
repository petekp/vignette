import CoreGraphics
import XCTest

/// Plays what `LiveInk` sends `LiveAsks`, in a random order, against a fake screen, and runs the
/// effects each event answers as `LiveInk` runs them. Each event goes to `observe` with the state
/// before and after it. What comes back for an ask is sent whether the ask takes it or not, so the
/// reducer's own check is what drops it.
final class LiveAsksEnvironment {
    enum Step {
        /// `begin`, with the marks on the screen it was given, the reply it followed, and the pointer of
        /// an ask about the window under it.
        case begun(LiveAsks.Begun, shown: [Mark], following: Mark.ID?, pointer: CGPoint?)
        case event(LiveAsks.Event)
    }

    struct Sent {
        let step: Step
        let before: LiveAsks
        let after: LiveAsks
        let effects: [LiveAsks.Effect]
    }

    enum Owed {
        case packet(LiveAsks.Ask.ID)
        case captureFailed(LiveAsks.Ask.ID)
        case picture(LiveAsks.Ask.ID)
        case say(LiveAsks.Ask.ID)
        case answer(LiveAsks.Ask.ID)
        case failure(LiveAsks.Ask.ID)
        case sent(LiveAsks.Ask.ID, ink: Set<Mark.ID>, refused: Bool)
        case timer(Set<Mark.ID>)
        case focus([Mark], LiveAsks.Ask.ID)

        /// Held by the responder, which fails it when it stops.
        var heldBy: LiveAsks.Ask.ID? {
            switch self {
            case .say(let id), .answer(let id), .failure(let id): id
            default: nil
            }
        }

        var isFocus: Bool { if case .focus = self { true } else { false } }
    }

    /// What `LiveInk.ask` says when the packet could not be captured.
    static let couldNotSee = "Vignette couldn't see the screen."

    private(set) var asks = LiveAsks()
    private(set) var trace: [String] = []
    /// Every mark made.
    private(set) var made: [Mark] = []
    var screen: [Mark] = []
    /// The marks set aside, by the ask from a picked button whose reply set them aside.
    var aside: [LiveAsks.Ask.ID: [Mark]] = [:]
    func aside(of id: LiveAsks.Ask.ID) -> Set<Mark.ID> { Set((aside[id] ?? []).map(\.id)) }
    var rng: SeededGenerator
    var owed: [(due: Int, owed: Owed)] = []
    var step = 0
    var names: [Mark.ID: String] = [:]
    var focusShown: (stop: [Mark], ask: LiveAsks.Ask.ID)?
    let observe: (LiveAsksEnvironment, Sent) -> Void

    init(seed: Int, observe: @escaping (LiveAsksEnvironment, Sent) -> Void) {
        rng = SeededGenerator(seed: UInt64(seed))
        self.observe = observe
    }

    func play(steps: Int = 40) {
        for step in 0..<steps {
            self.step = step
            deliverDue()
            act()
            for (id, marks) in aside where !marks.isEmpty && asks.ask(id)?.isUnderWay != true {
                XCTFail("marks stay set aside only while their ask is under way #\(id)\n" + trace.suffix(30).joined(separator: "\n"))
            }
        }
        // Drain: a clear, then every answer and timer still owed.
        step = steps
        clear()
        for step in steps..<(steps + 20) {
            self.step = step
            deliverDue()
        }
    }

    func act() {
        switch Int.random(in: 0..<22, using: &rng) {
        case 0...3: draw()
        case 4...7: ask()
        case 8...9: respond()
        case 10...11: dismissAnswer()
        case 12: erase()
        case 13: windowGone()
        case 14: pick()
        case 15: draw()
        case 16: discardNote()
        case 17: letGoOfFocus()
        case 18: clear()
        case 19: cancel()
        case 20: closeAnswer()
        default: break
        }
    }

    func deliverDue() {
        let due = owed.filter { $0.due <= step }
        owed.removeAll { $0.due <= step }
        for item in due {
            switch item.owed {
            case .packet(let id): packet(for: id)
            case .captureFailed(let id): failed(Self.couldNotSee, for: id)
            case .picture(let id): _ = send(.pictureSent(fresh: chance(2), for: id))
            case .say(let id): showSay(for: id)
            case .answer(let id): answered(for: id)
            case .failure(let id): failed("Claude stopped.", for: id)
            case .sent(let id, let ink, let refused): sessionAnswered(for: id, ink: ink, refused: refused)
            case .timer(let ids): finished(ids)
            case .focus(let stop, let id): nextFocus(stop, for: id)
            }
        }
    }

    // MARK: Plumbing

    func send(_ event: LiveAsks.Event) -> [LiveAsks.Effect] {
        let before = asks
        let effects = asks.reduce(event)
        trace.append("\(step): \(describe(event)) -> \(effects.map { describe($0) }) asks=\(asks.asks.map(describe).joined(separator: ", "))")
        observe(self, Sent(step: .event(event), before: before, after: asks, effects: effects))
        return effects
    }

    func chance(_ n: Int) -> Bool { Int.random(in: 0..<n, using: &rng) == 0 }

    func owe(_ item: Owed, in steps: ClosedRange<Int> = 1...3) {
        owed.append((step + Int.random(in: steps, using: &rng), item))
    }

    func make(_ geometry: Mark.Geometry, agent: Bool, _ prefix: String) -> Mark {
        let mark = Mark(geometry: geometry, agent: agent)
        names[mark.id] = "\(prefix)\(names.count)"
        made.append(mark)
        return mark
    }

    func shape(agent: Bool) -> Mark {
        let origin = CGPoint(x: CGFloat(Int.random(in: 0..<800, using: &rng)), y: CGFloat(Int.random(in: 0..<600, using: &rng)))
        return make(.ellipse(CGRect(origin: origin, size: CGSize(width: 40, height: 30))), agent: agent, agent ? "s" : "i")
    }

    func note(_ words: String, agent: Bool) -> Mark {
        make(.text(Mark.Text(origin: .zero, text: words, wrap: nil, size: 14)), agent: agent, agent ? "r" : "n")
    }

    var shown: Set<Mark.ID> { Set(screen.map(\.id)) }

    /// `put`: on the screen, in place of a mark of the same id, which keeps its part in the asks.
    func put(_ marks: [Mark]) {
        for mark in marks {
            takeOff([mark.id])
            screen.append(mark)
        }
    }

    /// `remove`: off the screen, and out of the asks.
    func remove(_ ids: Set<Mark.ID>) {
        takeOff(ids)
        run(send(.removed(ids)))
    }

    /// `takeOff`: off the screen, with no word to the asks.
    func takeOff(_ ids: Set<Mark.ID>) {
        screen.removeAll { ids.contains($0.id) }
        for id in aside.keys { aside[id]?.removeAll { ids.contains($0.id) } }
    }

    // MARK: Ink

    func draw() {
        let mark = shape(agent: false)
        _ = send(.drew(mark.id))
        put([mark])
    }

    func erase() {
        guard let mark = screen.randomElement(using: &rng) else { return }
        remove([mark.id])
    }

    /// The window's marks go with it, which `LiveWindows` does without `remove`.
    func windowGone() {
        let ids = Set((screen + aside.values.joined()).filter { _ in chance(3) }.map(\.id))
        guard !ids.isEmpty else { return }
        takeOff(ids)
        run(send(.windowGone(ids)))
    }

    func pick() {
        guard let hit = screen.filter({ $0.agent && $0.kind != .text && asks.isAnswer($0.id) }).randomElement(using: &rng) else { return }
        let own = make(hit.geometry, agent: false, "p")
        _ = send(.drew(own.id))
        put([own])
        remove([hit.id])
    }

    func discardNote() {
        run(send(.noteDiscarded))
    }

    // MARK: Asking

    @discardableResult
    func ask(following reply: Mark? = nil, picked: LiveAnswerActions.Pick = .reply) -> Bool {
        let before = asks
        let given = screen
        let toSession = reply == nil && chance(5)
        let pointer = reply == nil && chance(6) ? CGPoint(x: CGFloat(Int.random(in: 0..<800, using: &rng)), y: 300) : nil
        let begun = asks.begin(among: given, following: reply.map { LiveAsks.Following(reply: $0, pick: picked, words: "and this?") },
                               toSession: toSession, at: pointer)
        let effects: [LiveAsks.Effect]
        switch begun {
        case .began(let id, let about, _, let ended):
            effects = ended
            trace.append("\(step): began #\(id) about=\(list(Set(about.map(\.id)))) following=\(name(reply?.id)) session=\(toSession) pointer=\(pointer != nil) -> \(effects.map { describe($0) })")
        case .refused(let refusal, let refused):
            effects = refused
            trace.append("\(step): refused \(refusal) following=\(name(reply?.id)) -> \(effects.map { describe($0) })")
        }
        observe(self, Sent(step: .begun(begun, shown: given, following: reply?.id, pointer: pointer), before: before, after: asks, effects: effects))
        run(effects)
        guard case .began(let id, _, _, _) = begun else { return false }
        if let reply {
            put([reply])
        } else if chance(2) {
            var conversation = note("", agent: true)
            conversation.quote = "What is this?"
            _ = send(.conversed(conversation, for: id))
            put([conversation])
        }
        // A capture that fails can take a while, and `ask`'s task then fails the ask it began, whatever
        // has happened since.
        if chance(10) { owe(.captureFailed(id), in: 2...12) } else { owe(.packet(id)) }
        return true
    }

    func packet(for id: LiveAsks.Ask.ID) {
        let effects = send(.arrived(.packetCame, for: id))
        if effects.contains(where: { if case .share = $0 { true } else { false } }) {
            let ink = Set(asks.ink(among: screen).filter { _ in chance(2) }.map(\.id))
            owe(.sent(id, ink: ink, refused: chance(4)))
        }
        run(effects)
    }

    /// `LiveResponder` takes the ask: the picture goes, the reply streams, and the answer or a failure comes.
    func responderTakes(_ id: LiveAsks.Ask.ID) {
        if chance(2) { _ = send(.pictureSent(fresh: chance(2), for: id)) } else { owe(.picture(id), in: 1...2) }
        // The responder can shut down as it is asked, which fails the ask in the same turn.
        if chance(8) { return failed("The responder ended.", for: id) }
        let says = Int.random(in: 0...3, using: &rng)
        for n in 0..<says { owe(.say(id), in: (n + 1)...(n + 1)) }
        owe(chance(4) ? .failure(id) : .answer(id), in: (says + 1)...(says + 3))
    }

    func sessionAnswered(for id: LiveAsks.Ask.ID, ink: Set<Mark.ID>, refused: Bool) {
        if refused { return failed("Not sent.", for: id) }
        run(send(.arrived(.sentToSession(ink: ink), for: id)))
    }

    /// A press on an answer's panel. Its buttons are enabled only on an answer, and the panel shows
    /// only while the reply does (`shownReply`).
    func respond() {
        let answers = asks.asks.filter { ask in
            guard ask.phase == .answered, let said = ask.say else { return false }
            return screen.contains { $0.id == said.id } && asks.answer(of: said.id) == ask.id && !asks.isFinishing(said.id)
        }
        guard let answer = answers.randomElement(using: &rng), let said = answer.say else { return }
        let pick: LiveAnswerActions.Pick = chance(2) ? .reply : .action("Fix it")
        guard var reply = screen.first(where: { $0.id == said.id }) else { return }
        reply.quote = "and this?"
        reply.notice = nil
        ask(following: reply, picked: pick)
    }
}
