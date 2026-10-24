import CoreGraphics
import Foundation

/// The asks since the screen was last cleared: which ink is new, which ink has been asked about, the
/// asks under way and waiting their turn, and each answer on the screen with the marks that are its
/// own. Every ask takes its packet as it is sent. Asks to the responder then go to it one at a time,
/// in the order sent, each once the one before it has answered, failed or stopped. Asks to a session
/// do not wait for them. Each answer stays until its own × or Esc closes it: the × finishes the answer
/// and the ink only it was about. Erasing a mark takes away its roles and its finish, but not its place
/// in what an ask is about. A clear forgets every ask. What comes back for an ask is matched by its
/// id, and only an ask still under way takes it. `LiveInk` sends what happened and runs the effects
/// (docs/adr/0003-pure-reducers-decide.md).
struct LiveAsks: Equatable {
    /// What `[state]` says about an ask.
    struct Ask: Equatable {
        typealias ID = Int
        enum Phase: String {
            /// Its packet is being taken.
            case looking
            /// It has its packet and waits for the responder to answer the asks before it.
            case waiting
            case asking, answered, failed
        }
        /// Higher for each ask than for the one before. An answer put back after a failure keeps its
        /// own, earlier id.
        let id: ID
        var phase: Phase
        /// The person's marks it is about, which pulse while it is under way.
        var about: Set<Mark.ID>
        /// The marks of `about` that were new ink when the ask began, which stopping the ask makes new again.
        var fresh: Set<Mark.ID> = []
        /// It goes to a session as a note, not to the responder.
        var toSession = false
        var reason: String?
        var picture = false
        /// The reply as it streams in, and once it is whole. An ask from one of an answer's buttons
        /// starts with that answer's reply, which the next answer's words replace where it hangs.
        var say: Mark?
        /// The newest mark asked about, whose window the answer goes on.
        var leader: Mark.ID?
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

        var isUnderWay: Bool { [.looking, .waiting, .asking].contains(phase) }
    }

    /// The answer whose button the person picked, and the words sent, which a failure of the ask that
    /// follows, or Esc, puts back. Gone once that ask's answer comes.
    private struct ButtonPick: Equatable {
        var answer: Ask
        var words: String
        var pick: LiveAnswerActions.Pick
        /// The answer's marks, all but its reply, hidden where they are while the reply of the ask that
        /// follows streams.
        var aside: Set<Mark.ID> = []
    }

    private struct Roles: OptionSet, Equatable {
        let rawValue: UInt8
        /// Some ask has been about it. The person's marks without it are new, and the next ask is about them.
        static let asked = Roles(rawValue: 1 << 0)
        /// Drawn for the note: since the chord went down with no note open. Esc in the note takes it back.
        static let noteInk = Roles(rawValue: 1 << 1)
    }

    private struct Record: Equatable {
        var roles: Roles = []
        /// The ask whose answer, or failure's note, the mark is.
        var answer: Ask.ID?
        /// How the mark is leaving, until it is removed.
        var finishing: LiveMarksLayer.Finish?

        var isEmpty: Bool { roles.isEmpty && answer == nil && finishing == nil }
    }

    /// Oldest first: the asks under way or waiting, and those whose answer or failure is on the screen.
    private(set) var asks: [Ask] = []
    /// By the id of the ask from a picked button.
    private var picks: [Ask.ID: ButtonPick] = [:]
    /// Only marks with a role or leaving have one.
    private var records: [Mark.ID: Record] = [:]
    private var lastID: Ask.ID = 0
    /// The asks to a session that Esc stopped before their send was stored.
    private var withdrawn = Set<Ask.ID>()

    // MARK: Reads

    func ask(_ id: Ask.ID) -> Ask? { asks.first { $0.id == id } }

    /// The ask sent last.
    var newest: Ask? { asks.last }

    /// The ask whose reply is `reply`.
    func ask(withReply reply: Mark.ID) -> Ask? { asks.first { $0.say?.id == reply } }

    func isAnswer(_ id: Mark.ID) -> Bool { records[id]?.answer != nil }

    /// The ask whose answer the mark is.
    func answer(of id: Mark.ID) -> Ask.ID? { records[id]?.answer }

    var answerMarks: Set<Mark.ID> { Set(records.compactMap { $0.value.answer == nil ? nil : $0.key }) }

    func answerMarks(of ask: Ask.ID) -> Set<Mark.ID> { Set(records.compactMap { $0.value.answer == ask ? $0.key : nil }) }

    /// A mark of an answer that has come, or of a failure, which Esc can close.
    func isSettledAnswer(_ id: Mark.ID) -> Bool {
        guard let owner = records[id]?.answer else { return false }
        return ask(owner).map { !$0.isUnderWay } ?? true
    }

    var noteInk: Set<Mark.ID> { marks(with: .noteInk) }

    /// The marks leaving, and how.
    var finishing: [Mark.ID: LiveMarksLayer.Finish] { records.compactMapValues(\.finishing) }

    func isFinishing(_ id: Mark.ID) -> Bool { records[id]?.finishing != nil }

    /// The marks that pulse: what each ask under way or waiting is about, and the reply it will answer in.
    var pulsing: Set<Mark.ID> {
        asks.filter(\.isUnderWay).reduce(into: Set()) { pulsing, ask in
            pulsing.formUnion(ask.about)
            if let say = ask.say { pulsing.insert(say.id) }
        }
    }

    var isUnderWay: Bool { asks.contains(where: \.isUnderWay) }

    /// The asks to the responder that wait for an earlier one, in the order sent.
    var queued: [Ask.ID] { asks.filter { $0.isUnderWay && !$0.toSession }.dropFirst().map(\.id) }

    /// The ask Esc stops next: the newest under way that can be. One to a session only when
    /// `sendsWait`, since what stops it is taking the send back in its grace.
    func cancellable(sendsWait: Bool) -> Ask.ID? {
        asks.last { $0.isUnderWay && (!$0.toSession || sendsWait) }?.id
    }

    /// Not while the ask from one of the answer's buttons is under way, unless its send was queued or
    /// not confirmed, when its answer may be a long time coming.
    func offersDismiss(_ id: Ask.ID) -> Bool {
        guard let ask = ask(id) else { return false }
        return ask.picked == nil || ask.say?.notice != nil
    }

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

    /// The ink leads, not the person's note: the answer goes on the window the ink is on.
    static func leader(of about: [Mark]) -> Mark.ID? { about.last { $0.kind != .text }?.id ?? about.last?.id }

    private func isAsked(_ id: Mark.ID) -> Bool { records[id]?.roles.contains(.asked) == true }

    private func marks(with role: Roles) -> Set<Mark.ID> {
        Set(records.compactMap { $0.value.roles.contains(role) ? $0.key : nil })
    }

    private func index(of id: Ask.ID) -> Int? { asks.firstIndex { $0.id == id } }

    // MARK: Beginning

    /// The reply the person answered with one of its buttons, and the words sent.
    struct Following: Equatable {
        var reply: Mark
        var pick: LiveAnswerActions.Pick
        var words: String
    }

    /// Why an ask did not begin.
    enum Refusal: String, Equatable {
        case noInk = "There's no ink to ask about."

        var detail: String {
            switch self {
            case .noInk: "no ink"
            }
        }
    }

    enum Begun: Equatable {
        /// `about` is oldest first and its last mark has a shape, centred on `point`. The ask looks for
        /// its packet at once, whatever else is under way.
        case began(Ask.ID, about: [Mark], point: CGPoint)
        /// Following a reply, the answer it hangs from comes back, saying why.
        case refused(Refusal, effects: [Effect])
    }

    /// Begins an ask about the new ink among `shown`, or, with none, about the ink asked about,
    /// looking for its packet. `following` is the reply whose button the person picked: the ask takes
    /// that answer's place, and is about its marks too.
    mutating func begin(among shown: [Mark], following: Following?, toSession: Bool = false) -> Begun {
        let about = about(among: shown)
        guard let shape = about.last?.shapeExtent else { return refuse(.noInk, following: following) }
        let ids = Set(about.map(\.id))
        let fresh = ids.filter { !isAsked($0) }
        add(.asked, to: ids)
        lastID += 1
        let leader = Self.leader(of: about)
        var new = Ask(id: lastID, phase: .looking, about: ids, fresh: fresh, toSession: toSession, leader: leader)
        if let following {
            new.say = following.reply
            new.picked = following.pick
            if let answered = ask(withReply: following.reply.id) {
                picks[lastID] = ButtonPick(answer: answered, words: following.words, pick: following.pick)
                let marks = answerMarks(of: answered.id)
                new.about.formUnion(marks)
                own(marks, by: lastID)
                asks.removeAll { $0.id == answered.id }
            }
        }
        asks.append(new)
        return .began(lastID, about: about, point: CGPoint(x: shape.midX, y: shape.midY))
    }

    /// Following a reply, the answer it hangs from comes back as it was, saying why the ask did not
    /// begin, and the words sent wait in Reply when they were typed there.
    private mutating func refuse(_ refusal: Refusal, following: Following?) -> Begun {
        guard let following, let at = asks.firstIndex(where: { $0.say?.id == following.reply.id }) else {
            return .refused(refusal, effects: [])
        }
        asks[at].reason = refusal.rawValue
        if following.pick == .reply { asks[at].draft = following.words }
        return .refused(refusal, effects: [.restore(reply: following.reply.id, reason: refusal.rawValue, aside: [])])
    }

    // MARK: Events

    enum Event: Equatable {
        /// The person drew a mark, or picked one of an answer's: it is the note's ink.
        case drew(Mark.ID)
        /// The chord went down: with no note open, the note's ink starts over.
        case inkingBegan(noteOpen: Bool)
        /// Esc in the note.
        case noteDiscarded
        /// The marks were taken off the screen: erased, picked, a step or a focus stop done, the
        /// marks of a display unplugged, or anything else that leaves. Each loses its roles and its
        /// finish. The asks, and the marks they are about, stay as they are, but an answer with no
        /// marks left ends.
        case removed(Set<Mark.ID>)
        /// The marks went with their window. They keep the note's ink and their finish.
        case windowGone(Set<Mark.ID>)
        /// Something came back for ask `for`, late or not. Unless that ask is under way, it changes
        /// nothing and answers no effects.
        case arrived(Arrival, for: Ask.ID)

        /// The responder was sent the picture of ask `for`, or none since it has it already.
        case pictureSent(fresh: Bool, for: Ask.ID)

        // What LiveInk drew for ask `for`, in the turn its packet, reply or answer was taken.

        /// The note the person asked in became the conversation: the reply, with no words yet, under
        /// their question, which carries the thinking light and takes the answer's words.
        case conversed(Mark, for: Ask.ID)
        case streamed(Mark, for: Ask.ID)
        /// The answer was drawn: its reply, and of its other marks those `shown` now. The next ask
        /// waiting goes to the responder.
        case answered(reply: Mark?, actions: [LiveAnswer.Action], findings: [[Mark.ID]], shown: Set<Mark.ID>, for: Ask.ID)

        /// Reply's field closed with `words` in it, on the panel made for `reply`.
        case drafted(String, reply: Mark.ID?)

        /// A reply was drawn again: to hang from a focus stop, or saying why in its header.
        case replyRedrawn(Mark)
        /// More of ask `for`'s answer, or its failure's note, came on the screen.
        case answerShown(Set<Mark.ID>, for: Ask.ID)
        /// An answer's ×. It finishes the answer's marks, and the marks the ask is about, erased or
        /// not, that no other ask is about. The ask ends, and the responder's turn stops when it was
        /// this ask's.
        case dismissed(Ask.ID)
        /// Esc on ask `id`, under way: it stops, and its ink is as it was before it began. A reply to
        /// put back must be among `shown`. Nothing is said, since the person stopped it. A session's
        /// note stored after this is withdrawn.
        case cancelled(Ask.ID, shown: Set<Mark.ID>)
        /// Esc with no ask to stop: the newest answer's marks leave, and the person's ink stays.
        case answerClosed
        /// The time for marks to leave is up.
        case finished(Set<Mark.ID>)
        /// The screen was cleared, or live ink turned off.
        case cleared
    }

    /// What comes back for an ask.
    enum Arrival: Equatable {
        /// The packet was captured. Taken only while looking.
        case packetCame
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
        /// Ask the responder, with ask `id`'s packet. Every ask before it to the responder has ended.
        case send(Ask.ID)
        /// Stop the responder's turn: the ask it was answering was stopped or dismissed.
        case interrupt
        /// Send the note to the session, as a card of the ink `about`.
        case share(about: Set<Mark.ID>)
        /// Lay out the reply so far and draw it, then send `streamed`.
        case showReply
        /// Lay out the answer and draw it, then send `answered`.
        case drawAnswer
        /// The answer is back as it was before its button was picked. Show its set-aside marks `aside`
        /// again, then draw `reply` again, saying `reason` in its header when there is one, and send
        /// `replyRedrawn`.
        case restore(reply: Mark.ID, reason: String?, aside: Set<Mark.ID>)
        /// Say `reason` in a reply hung from ask `id`'s ink, and send `answerShown`.
        case say(Ask.ID, String)
        /// Say `reason` in `reply`'s row, in place of its words, and send `replyRedrawn`.
        case notice(reply: Mark.ID, reason: String)
        /// Take these marks off the screen.
        case remove(Set<Mark.ID>)
        /// The note of an ask Esc stopped was stored after all: take the send back.
        case withdraw
        /// Let go of ask `id`'s steps, focus and buttons, then take these marks off. The ask has already
        /// taken their part as its answer. May be empty.
        case removeAnswer(Ask.ID, Set<Mark.ID>)
        /// Let go of ask `id`'s steps, focus and buttons, and hide these marks where they are. The ask
        /// has already taken their part as its answer.
        case setAside(Ask.ID, Set<Mark.ID>)
        /// These marks are leaving: show them going, and send `finished` once they have.
        case finish(Set<Mark.ID>, LiveMarksLayer.Finish)
    }

    mutating func reduce(_ event: Event) -> [Effect] {
        apply(event) + sendNext()
    }

    private mutating func apply(_ event: Event) -> [Effect] {
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
            forgetAside(ids)
            endAnswersWithNoMarks()
        case .windowGone(let ids):
            take(.asked, from: ids)
            disown(ids)
            forgetAside(ids)
            endAnswersWithNoMarks()

        // What comes back for an ask no longer under way, or after a clear or a finish, changes nothing.
        case .arrived(let arrival, let id):
            if withdrawn.remove(id) != nil {
                if case .sentToSession = arrival { return [.withdraw] }
                break
            }
            guard let at = index(of: id), asks[at].isUnderWay else { break }
            let current = asks[at]
            switch arrival {
            case .packetCame:
                guard current.phase == .looking else { break }
                if current.toSession { return [.share(about: current.about)] }
                asks[at].phase = .waiting
            case .replyCame:
                guard current.phase == .asking else { break }
                return setAsideEarlierAnswer(of: id) + [.showReply]
            case .answerCame:
                guard current.phase == .asking else { break }
                return clearEarlierAnswer(of: id) + [.drawAnswer]
            case .failed(let reason, let shown):
                return fail(id, saying: reason, shown: shown)
            case .sentToSession(let ink):
                // The ink in the card's picture leaves with the note, but not ink another ask is about.
                let others = otherAsks(than: id).reduce(into: Set<Mark.ID>()) { $0.formUnion($1.about) }
                let leaving = current.about.union(ink).subtracting(others).union(answerMarks(of: id))
                end(id)
                return finish(leaving, .dismissed)
            }

        case .conversed(let reply, let id), .streamed(let reply, let id):
            guard let at = index(of: id) else { break }
            asks[at].say = reply
            own([reply.id], by: id)
        case .pictureSent(let fresh, let id):
            guard let at = index(of: id) else { break }
            asks[at].picture = fresh
        case .answered(let reply, let actions, let findings, let shown, let id):
            guard let at = index(of: id) else { break }
            asks[at].phase = .answered
            asks[at].say = reply
            asks[at].actions = actions
            asks[at].picked = nil
            asks[at].findings = findings
            own(shown, by: id)

        case .drafted(let words, let reply):
            // Only the answer the panel was made for keeps its draft: one hidden after its answer was
            // replaced must not hand its words to the next.
            guard let reply, let at = asks.firstIndex(where: { $0.say?.id == reply }) else { break }
            asks[at].draft = words

        case .replyRedrawn(let reply):
            guard let at = asks.firstIndex(where: { $0.say?.id == reply.id }) else { break }
            asks[at].say = reply
        case .answerShown(let ids, let id):
            guard ask(id) != nil else { break }
            own(ids, by: id)
        case .dismissed(let id):
            guard let ask = ask(id) else { break }
            let others = otherAsks(than: id).reduce(into: Set<Mark.ID>()) { $0.formUnion($1.about) }
            let ids = answerMarks(of: id).union(ask.about.subtracting(others)).union(picks[id]?.aside ?? [])
            let interrupt: [Effect] = ask.phase == .asking ? [.interrupt] : []
            end(id)
            return interrupt + (ids.isEmpty ? [] : finish(ids, .dismissed))
        case .cancelled(let id, let shown):
            guard let current = ask(id), current.isUnderWay else { break }
            if current.toSession { withdrawn.insert(id) }
            take(.asked, from: current.fresh)
            let interrupt: [Effect] = current.phase == .asking ? [.interrupt] : []
            if let restored = restore(id, saying: nil, shown: shown) { return interrupt + [restored] }
            let gone = answerMarks(of: id).union(picks[id]?.aside ?? [])
            disown(gone)
            end(id)
            return interrupt + [.removeAnswer(id, gone)]
        case .answerClosed:
            guard let ask = asks.last(where: { !$0.isUnderWay && answerMarks(of: $0.id).contains { !isFinishing($0) } }) else { break }
            let ids = answerMarks(of: ask.id)
            end(ask.id)
            return finish(ids, .dismissed)
        case .finished(let ids):
            // A clear, or an earlier timer for the same marks, has ended it already.
            guard ids.contains(where: { records[$0]?.finishing != nil }) else { break }
            for id in ids { records[id]?.finishing = nil }
            take(.asked, from: ids)
            disown(ids)
            endAnswersWithNoMarks()
            return [.remove(ids)]
        case .cleared:
            asks = []
            picks = [:]
            for id in records.keys {
                records[id]?.roles.subtract(.asked)
                records[id]?.answer = nil
                records[id]?.finishing = nil
            }
            records = records.filter { !$0.value.isEmpty }
        }
        return []
    }

    /// The oldest ask to the responder still under way goes to it, once it has its packet. Answers
    /// nothing while that ask is still looking, or is with the responder already.
    private mutating func sendNext() -> [Effect] {
        guard let at = asks.firstIndex(where: { $0.isUnderWay && !$0.toSession }), asks[at].phase == .waiting else { return [] }
        asks[at].phase = .asking
        return [.send(asks[at].id)]
    }

    private func otherAsks(than id: Ask.ID) -> [Ask] { asks.filter { $0.id != id } }

    /// The ask is over: it leaves the list, with the answer its button was picked under.
    private mutating func end(_ id: Ask.ID) {
        asks.removeAll { $0.id == id }
        picks[id] = nil
    }

    /// An answer or a failure with none of its marks left on the screen has nothing to close.
    private mutating func endAnswersWithNoMarks() {
        let owners = Set(records.values.compactMap(\.answer))
        asks.removeAll { !$0.isUnderWay && !owners.contains($0.id) }
    }

    /// Once the reply of an ask from a picked button starts, the answer it was picked under is set
    /// aside, all but that reply, whose words the new ones replace where it hangs.
    private mutating func setAsideEarlierAnswer(of id: Ask.ID) -> [Effect] {
        guard picks[id] != nil, let reply = ask(id)?.say?.id else { return [] }
        let aside = answerMarks(of: id).filter { $0 != reply }
        disown(aside)
        picks[id]?.aside.formUnion(aside)
        return [.setAside(id, aside)]
    }

    /// Once the answer of an ask from a picked button comes, the answer it was picked under goes, all
    /// but its reply, which the new answer draws over.
    private mutating func clearEarlierAnswer(of id: Ask.ID) -> [Effect] {
        guard let pick = picks[id] else { return [] }
        picks[id] = nil
        let reply = ask(id)?.say?.id
        let gone = answerMarks(of: id).filter { $0 != reply }.union(pick.aside)
        disown(gone)
        return [.removeAnswer(id, gone)]
    }

    /// The answer a button was picked under comes back, or else the ask fails, saying why in the
    /// conversation's row when it is on the screen, and else in a reply of its own beside its ink.
    private mutating func fail(_ id: Ask.ID, saying reason: String, shown: Set<Mark.ID>) -> [Effect] {
        if let restored = restore(id, saying: reason, shown: shown) { return [restored] }
        guard let at = index(of: id) else { return [] }
        asks[at].phase = .failed
        asks[at].reason = reason
        let reply = asks[at].say?.id
        let aside = picks[id]?.aside ?? []
        picks[id] = nil
        if let reply, shown.contains(reply) {
            let gone = answerMarks(of: id).filter { $0 != reply }.union(aside)
            disown(gone)
            return [.removeAnswer(id, gone), .notice(reply: reply, reason: reason)]
        }
        let gone = answerMarks(of: id).union(aside)
        disown(gone)
        return [.removeAnswer(id, gone), .say(id, reason)]
    }

    /// The answer a button was picked under, while ask `id`, which followed it, still hangs from its
    /// reply and that reply is among `shown`, comes back in that ask's place with its buttons, and
    /// typed words wait in Reply.
    private mutating func restore(_ id: Ask.ID, saying reason: String?, shown: Set<Mark.ID>) -> Effect? {
        guard let pick = picks[id], let reply = pick.answer.say?.id, ask(id)?.say?.id == reply, shown.contains(reply),
              let at = index(of: id) else { return nil }
        var answer = pick.answer
        answer.reason = reason
        if pick.pick == .reply { answer.draft = pick.words }
        own(answerMarks(of: id).union(pick.aside), by: answer.id)
        asks[at] = answer
        picks[id] = nil
        return .restore(reply: reply, reason: reason, aside: pick.aside)
    }

    private mutating func forgetAside(_ ids: Set<Mark.ID>) {
        for id in picks.keys { picks[id]?.aside.subtract(ids) }
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

    private mutating func own(_ ids: Set<Mark.ID>, by ask: Ask.ID) {
        for id in ids { records[id, default: Record()].answer = ask }
    }

    private mutating func disown(_ ids: Set<Mark.ID>) {
        for id in ids {
            records[id]?.answer = nil
            if records[id]?.isEmpty == true { records[id] = nil }
        }
    }
}
