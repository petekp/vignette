import CoreGraphics
import Foundation

/// The asks since the screen was last cleared: which ink is new, which ink has been asked about, the
/// ask under way or the last one, which marks are the answer's, and what dismiss, finish and clear do
/// to each. `LiveInk` sends what happened and runs the effects (docs/adr/0003-pure-reducers-decide.md).
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

    /// The marks that pulse: what the ask under way is about.
    var pulsing: Set<Mark.ID> {
        guard let ask else { return [] }
        return [.looking, .asking].contains(ask.phase) ? ask.about : []
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

    /// Begins an ask about `about`, looking for its packet, and answers its id. `following` is the
    /// reply whose button the person picked with `picked`: the ask is about that answer's marks too.
    mutating func begin(about: Set<Mark.ID>, leader: Mark.ID?, leaderShift: CGVector?, following reply: Mark?,
                        picked: LiveAnswerActions.Pick?) -> Ask.ID {
        add(.asked, to: about)
        lastID += 1
        var new = Ask(id: lastID, phase: .looking, about: about, leader: leader, leaderShift: leaderShift)
        if let reply {
            new.say = reply
            new.picked = picked
            new.about.formUnion(answerMarks)
        }
        ask = new
        return lastID
    }

    // MARK: Events

    enum Event: Equatable {
        /// The person drew a mark, or picked one of the answer's: it is the note's ink.
        case drew(Mark.ID)
        /// The chord went down: with no note open, the note's ink starts over.
        case inkingBegan(noteOpen: Bool)
        /// ⌘⌫ in the note.
        case noteDiscarded
        /// A tap made the answer's mark the person's, under a new id.
        case picked(Mark.ID)
        /// The marks went with their window.
        case windowGone(Set<Mark.ID>)

        // What comes back for an ask, late or not. Each answers no effects and changes nothing when
        // the ask no longer takes it.

        /// The packet was captured, for the responder or for a session.
        case packetCame(for: Ask.ID, toSession: Bool)
        /// The responder's reply streamed in further.
        case replyCame(for: Ask.ID)
        case answerCame(for: Ask.ID)
        /// `shown` is every mark on the screen, among which an answer to put back must be.
        case failed(reason: String, for: Ask.ID, shown: Set<Mark.ID>)
        /// A session took the note about `about`, with `ink` in its picture, and `carried` when its
        /// card carries the ink away.
        case sentToSession(about: Set<Mark.ID>, ink: Set<Mark.ID>, carried: Bool, for: Ask.ID)
        case notSentToSession(about: Set<Mark.ID>, reason: String, shown: Set<Mark.ID>, for: Ask.ID)

        // What LiveInk drew for an ask, in the turn its packet, reply or answer was taken.

        /// The person's words stay beside the ink as a note of theirs.
        case noted(Mark.ID, for: Ask.ID)
        /// The responder was sent the picture, or none since it has it already.
        case pictureSent(fresh: Bool, for: Ask.ID)
        case streamed(Mark)
        /// The answer was drawn: its reply, and of its other marks those `shown` now.
        case answered(reply: Mark?, actions: [LiveAnswer.Action], findings: [[Mark.ID]], shown: Set<Mark.ID>)

        /// The person picked one of the answer's buttons, an action or Reply with `words` typed, and an
        /// ask from its reply follows.
        case buttonPicked(words: String, pick: LiveAnswerActions.Pick)
        /// That ask was refused before it began.
        case askRefused(reason: String, shown: Set<Mark.ID>)
        /// Reply's field closed with `words` in it, on the panel made for `reply`.
        case drafted(String, reply: Mark.ID?)

        /// The reply was drawn again: to hang from a focus stop, or saying why in its header.
        case replyRedrawn(Mark)
        case answerShown(Set<Mark.ID>)
        case answerGone(Set<Mark.ID>)
        /// The answer went, all but `keeping`, and with it the answer a picked button would put back.
        case answerRemoved(keeping: Mark.ID?)
        /// The answer's ×.
        case dismissed
        /// The turn after a session's card took the ink, as the card starts to move.
        case carrying(Set<Mark.ID>)
        /// The time for marks to leave is up.
        case finished(Set<Mark.ID>)
        /// The screen was cleared, or live ink turned off.
        case cleared
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
        /// Say `reason` in a note beside the ink.
        case say(String)
        /// Take these marks off the screen.
        case remove(Set<Mark.ID>)
        /// Take the answer off the screen, all but this reply, and send `answerRemoved`. It lets go of
        /// the focus first, which takes the stop's marks off and reads which marks are the answer's.
        case removeAnswer(keeping: Mark.ID)
        /// These marks are leaving: show them going, and send `finished` once they have.
        case finish(Set<Mark.ID>, LiveMarksLayer.Finish)
        /// On the next turn, send `carrying`.
        case carry(Set<Mark.ID>)
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
        case .picked(let id):
            take(.answer, from: [id])
        case .windowGone(let ids):
            take([.asked, .answer], from: ids)

        // The phase decides, whichever ask the id names, so a newer ask in that phase takes a late answer.
        case .packetCame(_, let toSession):
            guard let looking = ask, looking.phase == .looking else { break }
            if toSession { return [.share(about: looking.about)] }
            ask?.phase = .asking
            return [.send]
        case .replyCame:
            guard ask?.phase == .asking else { break }
            return clearEarlierAnswer() + [.showReply]
        case .answerCame:
            guard ask != nil else { break }
            return clearEarlierAnswer() + [.drawAnswer]
        case .failed(let reason, _, let shown):
            guard ask != nil else { break }
            return fail(saying: reason, shown: shown)
        case .sentToSession(let about, let ink, let carried, _):
            guard ask?.about == about else { break }
            let ids = about.union(ink)
            return carried ? [.carry(ids)] : finish(ids, .dismissed)
        case .notSentToSession(let about, let reason, let shown, _):
            guard ask?.about == about else { break }
            return fail(saying: reason, shown: shown)

        case .noted(let note, _):
            add(.asked, to: [note])
            ask?.about.insert(note)
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

        case .buttonPicked(let words, let pick):
            guard let ask else { break }
            buttonPick = ButtonPick(answer: ask, words: words, pick: pick)
        case .askRefused(let reason, let shown):
            return restore(saying: reason, shown: shown).map { [$0] } ?? []
        case .drafted(let words, let reply):
            // Only the answer the panel was made for keeps its draft: one hidden after a new ask began
            // must not hand its words to the new answer.
            if ask?.say?.id == reply { ask?.draft = words }

        case .replyRedrawn(let reply):
            ask?.say = reply
        case .answerShown(let ids):
            add(.answer, to: ids)
        case .answerGone(let ids):
            take(.answer, from: ids)
        case .answerRemoved(let kept):
            buttonPick = nil
            let gone = answerMarks.filter { $0 != kept }
            guard !gone.isEmpty else { break }
            take(.answer, from: gone)
            return [.remove(gone)]
        case .dismissed:
            let ids = answerMarks.union(ask?.about ?? [])
            return ids.isEmpty ? [] : finish(ids, .dismissed)
        case .carrying(let ids):
            return finish(ids, .carried)
        case .finished(let ids):
            // A clear, or an earlier timer for the same marks, has ended it already.
            guard ids.contains(where: { records[$0]?.finishing != nil }) else { break }
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
        return [.removeAnswer(keeping: reply)]
    }

    /// The answer a button was picked under comes back, or else the ask fails, saying why.
    private mutating func fail(saying reason: String, shown: Set<Mark.ID>) -> [Effect] {
        if let restored = restore(saying: reason, shown: shown) { return [restored] }
        ask?.phase = .failed
        ask?.reason = reason
        return [.say(reason)]
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
