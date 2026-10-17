import CoreGraphics
import Foundation

/// The asks since the screen was last cleared: which ink is new, which ink has been asked about, the
/// ask under way or the last one, and which marks are the answer's. The × finishes the answer and the
/// ink it was about. Erasing a mark takes away its roles and its finish, but not its place in what the
/// ask is about, so the × and a session's card still finish it. A finish removes the marks that left
/// and ends the ask that was about only them. A clear forgets every ask. What comes back for an ask is
/// matched by its id, and only the current ask takes it; `pictureSent` is the exception, kept for now.
/// `LiveInk` sends what happened and runs the effects (docs/adr/0003-pure-reducers-decide.md).
struct LiveAsks: Equatable {
    /// What `[state]` says about the ask under way, or the last one.
    struct Ask: Equatable {
        typealias ID = Int
        enum Phase: String { case looking, asking, answered, failed }
        /// Higher for each ask than for the one before. An answer put back after a failure keeps its
        /// own, earlier id.
        let id: ID
        var phase: Phase
        /// The person's marks it is about, which pulse while it is under way.
        var about: Set<Mark.ID>
        var reason: String?
        var picture = false
        /// The reply as it streams in, and once it is whole. An ask from one of an answer's buttons
        /// starts with that answer's reply, which the next answer's words replace where it hangs.
        var say: Mark?
        /// The newest mark asked about, which the answer's notes stay beside, and how far its content
        /// had moved when the ask began.
        var leader: Mark.ID?
        var leaderShift: CGVector?
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

    /// The answer whose button the person picked, and the words sent, which a failure of the ask that
    /// follows puts back. Gone once that ask's reply starts to replace the answer.
    private struct ButtonPick: Equatable {
        var answer: Ask
        var words: String
        var pick: LiveAnswerActions.Pick
    }

    private struct Roles: OptionSet, Equatable {
        let rawValue: UInt8
        /// Some ask has been about it. The person's marks without it are new, and the next ask is about them.
        static let asked = Roles(rawValue: 1 << 0)
        /// Drawn for the note: since the chord went down with no note open. ⌘⌫ in the note takes it back.
        static let noteInk = Roles(rawValue: 1 << 1)
        /// One of the last answer's marks, or a failure's note: a new ask takes them off the screen.
        static let answer = Roles(rawValue: 1 << 2)
    }

    private struct Record: Equatable {
        var roles: Roles = []
        /// How the mark is leaving, until it is removed.
        var finishing: LiveMarksLayer.Finish?

        var isEmpty: Bool { roles.isEmpty && finishing == nil }
    }

    /// The ask under way, or the last one.
    private(set) var ask: Ask?
    private var buttonPick: ButtonPick?
    /// Only marks with a role or leaving have one.
    private var records: [Mark.ID: Record] = [:]
    private var lastID: Ask.ID = 0

    // MARK: Reads

    func isAnswer(_ id: Mark.ID) -> Bool { records[id]?.roles.contains(.answer) == true }

    var answerMarks: Set<Mark.ID> { marks(with: .answer) }

    var noteInk: Set<Mark.ID> { marks(with: .noteInk) }

    /// The marks leaving, and how.
    var finishing: [Mark.ID: LiveMarksLayer.Finish] { records.compactMapValues(\.finishing) }

    func isFinishing(_ id: Mark.ID) -> Bool { records[id]?.finishing != nil }

    /// The marks that pulse: what the ask under way is about, and the reply it will answer in.
    var pulsing: Set<Mark.ID> {
        guard let ask, [.looking, .asking].contains(ask.phase) else { return [] }
        return ask.about.union(ask.say.map { [$0.id] } ?? [])
    }

    var isUnderWay: Bool { ask?.phase == .looking || ask?.phase == .asking }

    /// Not while the ask from one of the answer's buttons is under way, unless its send was queued or
    /// not confirmed, when its answer may be a long time coming.
    var offersDismiss: Bool { ask?.picked == nil || ask?.say?.notice != nil }

    /// The person's own marks among `shown`, oldest first: a failure's note is in their colour, but
    /// Vignette's.
    func ink(among shown: [Mark]) -> [Mark] { shown.filter { !$0.agent && !isAnswer($0.id) } }

    /// The person's marks among `shown` no ask has been about yet, oldest first.
    func newInk(among shown: [Mark]) -> [Mark] { ink(among: shown).filter { !isAsked($0.id) } }

    /// What the next ask is about: the new ink among `shown`, or with none, the ink asked about.
    func about(among shown: [Mark]) -> [Mark] {
        let fresh = newInk(among: shown)
        return fresh.isEmpty ? ink(among: shown).filter { isAsked($0.id) } : fresh
    }

    /// The ink leads, not the person's note: the notes follow it directly, so moving its content
    /// moves the question and the reply together.
    static func leader(of about: [Mark]) -> Mark.ID? { about.last { $0.kind != .text }?.id ?? about.last?.id }

    private func isAsked(_ id: Mark.ID) -> Bool { records[id]?.roles.contains(.asked) == true }

    private func marks(with role: Roles) -> Set<Mark.ID> {
        Set(records.compactMap { $0.value.roles.contains(role) ? $0.key : nil })
    }

    // MARK: Beginning

    /// The reply the person answered with one of its buttons, and the words sent.
    struct Following: Equatable {
        var reply: Mark
        var pick: LiveAnswerActions.Pick
        var words: String
    }

    /// Why an ask did not begin, checked in this order.
    enum Refusal: String, Equatable {
        case noInk = "There's no ink to ask about."
        case busy = "An ask is under way."

        var detail: String {
            switch self {
            case .noInk: "no ink"
            case .busy: "busy"
            }
        }
    }

    enum Begun: Equatable {
        /// `about` is oldest first and its last mark has a shape, centred on `point`. A fresh ask
        /// answers `removeAnswer`, and one following a reply nothing.
        case began(Ask.ID, about: [Mark], point: CGPoint, effects: [Effect])
        /// Following a reply, the answer it hangs from comes back, saying why.
        case refused(Refusal, effects: [Effect])
    }

    /// Begins an ask about the new ink among `shown`, or, with none, about the ink asked about last,
    /// looking for its packet. `following` is the reply whose button the person picked: the ask is
    /// about that answer's marks too. `shift` says how far a mark's content has moved, and must only
    /// read.
    mutating func begin(among shown: [Mark], following: Following?, shift: (Mark.ID) -> CGVector?) -> Begun {
        let about = about(among: shown)
        guard let shape = about.last?.shapeExtent else { return refuse(.noInk, following: following) }
        if isUnderWay { return refuse(.busy, following: following) }
        var effects: [Effect] = []
        if let following {
            if let ask { buttonPick = ButtonPick(answer: ask, words: following.words, pick: following.pick) }
        } else {
            effects = removeAnswer(keeping: nil)
        }
        let ids = Set(about.map(\.id))
        add(.asked, to: ids)
        lastID += 1
        let leader = Self.leader(of: about)
        var new = Ask(id: lastID, phase: .looking, about: ids, leader: leader, leaderShift: leader.flatMap(shift))
        if let following {
            new.say = following.reply
            new.picked = following.pick
            new.about.formUnion(answerMarks)
        }
        ask = new
        return .began(lastID, about: about, point: CGPoint(x: shape.midX, y: shape.midY), effects: effects)
    }

    /// Following a reply, the answer it hangs from comes back as it was, saying why the ask did not
    /// begin, and the words sent wait in Reply when they were typed there.
    private mutating func refuse(_ refusal: Refusal, following: Following?) -> Begun {
        guard let following, let ask else { return .refused(refusal, effects: []) }
        let before = buttonPick
        buttonPick = ButtonPick(answer: ask, words: following.words, pick: following.pick)
        guard let restored = restore(saying: refusal.rawValue, shown: [following.reply.id]) else {
            buttonPick = before
            return .refused(refusal, effects: [])
        }
        return .refused(refusal, effects: [restored])
    }

    // MARK: Events

    enum Event: Equatable {
        /// The person drew a mark, or picked one of the answer's: it is the note's ink.
        case drew(Mark.ID)
        /// The chord went down: with no note open, the note's ink starts over.
        case inkingBegan(noteOpen: Bool)
        /// ⌘⌫ in the note.
        case noteDiscarded
        /// The marks were taken off the screen: erased, picked, a step or a focus stop done, the
        /// marks of a display unplugged, or anything else that leaves. Each loses its roles and its finish. The ask, and the marks it is about, stay
        /// as they are.
        case removed(Set<Mark.ID>)
        /// The marks went with their window. They keep the note's ink and their finish.
        case windowGone(Set<Mark.ID>)
        /// Something came back for ask `for`, late or not. Unless that is the current ask, it changes
        /// nothing and answers no effects.
        case arrived(Arrival, for: Ask.ID)

        /// The responder was sent the picture, or none since it has it already. Unlike `arrived`, it is
        /// recorded on whichever ask is current, whatever ask `for` names.
        case pictureSent(fresh: Bool, for: Ask.ID)

        // What LiveInk drew for the current ask, in the turn its packet, reply or answer was taken.

        /// The note the person asked in became the conversation: the reply, with no words yet, under
        /// their question, which carries the thinking light and takes the answer's words.
        case conversed(Mark)
        case streamed(Mark)
        /// The answer was drawn: its reply, and of its other marks those `shown` now.
        case answered(reply: Mark?, actions: [LiveAnswer.Action], findings: [[Mark.ID]], shown: Set<Mark.ID>)

        /// Reply's field closed with `words` in it, on the panel made for `reply`.
        case drafted(String, reply: Mark.ID?)

        /// The reply was drawn again: to hang from a focus stop, or saying why in its header.
        case replyRedrawn(Mark)
        case answerShown(Set<Mark.ID>)
        /// The answer's ×. It finishes the answer's marks and the marks the ask is about, erased or not.
        case dismissed
        /// The time for marks to leave is up. It ends the ask when the ask was about only these marks.
        case finished(Set<Mark.ID>)
        /// The screen was cleared, or live ink turned off.
        case cleared
    }

    /// What comes back for an ask.
    enum Arrival: Equatable {
        /// The packet was captured, for the responder or for a session. Taken only while looking.
        case packetCame(toSession: Bool)
        /// The responder's reply streamed in further. Taken only while asking.
        case replyCame
        case answerCame
        /// The packet could not be captured, the responder failed, or a session refused the note.
        /// `shown` is every mark on the screen, among which an answer to put back must be.
        case failed(reason: String, shown: Set<Mark.ID>)
        /// A session took the note, with `ink` in its picture.
        case sentToSession(ink: Set<Mark.ID>)
    }

    enum Effect: Equatable {
        /// Ask the responder, with the packet.
        case send
        /// Send the note to the session, as a card of the ink `about`.
        case share(about: Set<Mark.ID>)
        /// Lay out the reply so far and draw it, then send `streamed`.
        case showReply
        /// Lay out the answer and draw it, then send `answered`.
        case drawAnswer
        /// The answer is back as it was before its button was picked. Draw `reply` again, saying
        /// `reason` in its header, and send `replyRedrawn`.
        case restore(reply: Mark.ID, reason: String)
        /// Say `reason` in a reply hung from the ink.
        case say(String)
        /// Say `reason` in `reply`'s row, in place of its words, and send `replyRedrawn`.
        case notice(reply: Mark.ID, reason: String)
        /// Take these marks off the screen.
        case remove(Set<Mark.ID>)
        /// Let go of the steps, the focus and the answer's buttons, then take these marks off. The ask
        /// has already taken their part as the answer's. May be empty.
        case removeAnswer(Set<Mark.ID>)
        /// These marks are leaving: show them going, and send `finished` once they have.
        case finish(Set<Mark.ID>, LiveMarksLayer.Finish)
    }

    mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case .drew(let id):
            add(.noteInk, to: [id])
        case .inkingBegan(let noteOpen):
            if !noteOpen { take(.noteInk, from: Set(records.keys)) }
        case .noteDiscarded:
            let ink = noteInk
            guard !ink.isEmpty else { break }
            take(.noteInk, from: ink)
            return [.remove(ink)]
        case .removed(let ids):
            for id in ids { records[id] = nil }
        case .windowGone(let ids):
            take([.asked, .answer], from: ids)

        // What comes back for any ask but the current one, or after a clear or a finish, changes nothing.
        case .arrived(let arrival, let id):
            guard let current = ask, current.id == id else { break }
            switch arrival {
            case .packetCame(let toSession):
                guard current.phase == .looking else { break }
                if toSession { return [.share(about: current.about)] }
                ask?.phase = .asking
                return [.send]
            case .replyCame:
                guard current.phase == .asking else { break }
                return clearEarlierAnswer() + [.showReply]
            case .answerCame:
                return clearEarlierAnswer() + [.drawAnswer]
            case .failed(let reason, let shown):
                return fail(saying: reason, shown: shown)
            case .sentToSession(let ink):
                return finish(current.about.union(ink).union(current.say.map { [$0.id] } ?? []), .dismissed)
            }

        case .conversed(let reply):
            ask?.say = reply
            add(.answer, to: [reply.id])
        case .pictureSent(let fresh, _):
            ask?.picture = fresh
        case .streamed(let reply):
            ask?.say = reply
            add(.answer, to: [reply.id])
        case .answered(let reply, let actions, let findings, let shown):
            ask?.phase = .answered
            ask?.say = reply
            ask?.actions = actions
            ask?.picked = nil
            ask?.findings = findings
            add(.answer, to: shown)

        case .drafted(let words, let reply):
            // Only the answer the panel was made for keeps its draft: one hidden after a new ask began
            // must not hand its words to the new answer.
            if ask?.say?.id == reply { ask?.draft = words }

        case .replyRedrawn(let reply):
            ask?.say = reply
        case .answerShown(let ids):
            add(.answer, to: ids)
        case .dismissed:
            let ids = answerMarks.union(ask?.about ?? [])
            return ids.isEmpty ? [] : finish(ids, .dismissed)
        case .finished(let ids):
            // A clear, or an earlier timer for the same marks, has ended it already. Marks erased while
            // leaving have lost their finish, but the ask about them still ends.
            let ends = !ids.isEmpty && ask.map { $0.about.isSubset(of: ids) } == true
            guard ends || ids.contains(where: { records[$0]?.finishing != nil }) else { break }
            for id in ids { records[id]?.finishing = nil }
            take([.asked, .answer], from: ids)
            if ask?.about.isSubset(of: ids) == true { ask = nil }
            return [.remove(ids)]
        case .cleared:
            ask = nil
            buttonPick = nil
            for id in records.keys {
                records[id]?.roles.subtract([.asked, .answer])
                records[id]?.finishing = nil
            }
            records = records.filter { !$0.value.isEmpty }
        }
        return []
    }

    /// Once the reply of an ask from a picked button starts, the answer it was picked under goes, all
    /// but that reply, whose words the new ones replace where it hangs.
    private mutating func clearEarlierAnswer() -> [Effect] {
        buttonPick = nil
        guard let reply = ask?.say?.id else { return [] }
        return removeAnswer(keeping: reply)
    }

    /// The answer goes, all but `kept`, and with it the answer a picked button would put back.
    /// LiveInk lets go of the steps, the focus and the buttons even when no mark goes.
    private mutating func removeAnswer(keeping kept: Mark.ID?) -> [Effect] {
        buttonPick = nil
        let gone = answerMarks.filter { $0 != kept }
        take(.answer, from: gone)
        return [.removeAnswer(gone)]
    }

    /// The answer a button was picked under comes back, or else the ask fails, saying why in the
    /// conversation's row when it is on the screen, and else in a reply of its own.
    private mutating func fail(saying reason: String, shown: Set<Mark.ID>) -> [Effect] {
        if let restored = restore(saying: reason, shown: shown) { return [restored] }
        ask?.phase = .failed
        ask?.reason = reason
        if let reply = ask?.say?.id, shown.contains(reply) {
            return removeAnswer(keeping: reply) + [.notice(reply: reply, reason: reason)]
        }
        return removeAnswer(keeping: nil) + [.say(reason)]
    }

    /// The answer a button was picked under, while the ask that followed still hangs from its reply
    /// and that reply is among `shown`, comes back with its buttons, and typed words wait in Reply.
    private mutating func restore(saying reason: String, shown: Set<Mark.ID>) -> Effect? {
        guard let buttonPick, let reply = buttonPick.answer.say?.id, ask?.say?.id == reply, shown.contains(reply) else { return nil }
        var answer = buttonPick.answer
        answer.reason = reason
        if buttonPick.pick == .reply { answer.draft = buttonPick.words }
        ask = answer
        self.buttonPick = nil
        return .restore(reply: reply, reason: reason)
    }

    private mutating func finish(_ ids: Set<Mark.ID>, _ how: LiveMarksLayer.Finish) -> [Effect] {
        for id in ids { records[id, default: Record()].finishing = how }
        return [.finish(ids, how)]
    }

    private mutating func add(_ roles: Roles, to ids: Set<Mark.ID>) {
        for id in ids { records[id, default: Record()].roles.formUnion(roles) }
    }

    private mutating func take(_ roles: Roles, from ids: Set<Mark.ID>) {
        for id in ids {
            records[id]?.roles.subtract(roles)
            if records[id]?.isEmpty == true { records[id] = nil }
        }
    }
}
