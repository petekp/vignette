import XCTest

@MainActor
final class CommentDeliveryTests: XCTestCase {
    private let claude = AgentAddress.claudeSession("6d1f0a52-0000-4000-8000-000000000001")
    private let other = AgentAddress.claudeSession("6d1f0a52-0000-4000-8000-000000000002")

    private func pin(_ number: Int, _ comments: [Pin.Comment], resolved: Pin.Resolution? = nil, id: UUID = UUID()) -> Pin {
        Pin(id: id, number: number, place: .point(CGPoint(x: 10, y: 20)), comments: comments, resolved: resolved)
    }

    private func answer(_ text: String, from session: AgentAddress, at: Date = Date()) -> Pin.Comment {
        Pin.Comment(text: text, agent: true, agentName: "claude", session: session, at: at)
    }

    func testThePersonsPostsEditsDeletesResolvesAndReopensAreChangesAndAnAgentsAreNot() {
        let asked = Pin.Comment(text: "Move the date")
        let answered = answer("Moved it", from: claude)
        let before = pin(1, [asked, answered])
        var after = before
        after.comments[0].text = "Move the date up"
        after.comments.append(Pin.Comment(text: "Thanks"))
        let posted = after.comments[2].id
        XCTAssertEqual(CommentChange.between([before], [after]), [
            .edited(pin: before.id, comment: asked.id, text: "Move the date up"),
            .posted(pin: before.id, comment: posted, text: "Thanks", reopens: false),
        ])

        var agentOnly = before
        agentOnly.comments.append(answer("Also fixed the title", from: claude))
        agentOnly.resolved = Pin.Resolution(agent: true, agentName: "claude")
        XCTAssertEqual(CommentChange.between([before], [agentOnly]), [])

        var resolved = before
        resolved.resolved = .byPerson()
        XCTAssertEqual(CommentChange.between([before], [resolved]), [.resolved(pin: before.id)])
        XCTAssertEqual(CommentChange.between([resolved], [before]), [.reopened(pin: before.id)])

        var reopenedByPost = before
        reopenedByPost.comments.append(Pin.Comment(text: "Not quite"))
        XCTAssertEqual(CommentChange.between([resolved], [reopenedByPost]),
                       [.posted(pin: before.id, comment: reopenedByPost.comments[2].id, text: "Not quite", reopens: true)])

        XCTAssertEqual(CommentChange.between([before], []), [
            .deleted(pin: before.id, comment: asked.id, text: "Move the date"),
            .deleted(pin: before.id, comment: answered.id, text: "Moved it"),
        ])
    }

    func testAnEditToAnAgentsCommentIsAChangeOfThePersons() {
        let answered = answer("Moved it", from: claude)
        let before = pin(1, [answered])
        var after = before
        after.comments[0] = Pin.Comment(id: answered.id, text: "Moved it, but not far enough")
        XCTAssertEqual(CommentChange.between([before], [after]),
                       [.edited(pin: before.id, comment: answered.id, text: "Moved it, but not far enough")])
    }

    func testThePinsOwnSessionComesFirstThenTheScreenshotsLastSessionWhicheverIsRunning() {
        let mine = AgentDestination(id: claude.id, name: "vignette", address: claude)
        let theirs = AgentDestination(id: other.id, name: "docs", address: other)
        let answered = pin(1, [Pin.Comment(text: "Why?"), answer("Because", from: other)])
        let fresh = pin(2, [Pin.Comment(text: "And this")])
        XCTAssertEqual(CommentTarget.destination(for: answered, last: claude, running: [mine, theirs]), theirs)
        XCTAssertEqual(CommentTarget.destination(for: answered, last: claude, running: [mine]), mine)
        XCTAssertEqual(CommentTarget.destination(for: fresh, last: claude, running: [mine, theirs]), mine)
        XCTAssertNil(CommentTarget.destination(for: fresh, last: claude, running: [theirs]))
        XCTAssertNil(CommentTarget.destination(for: fresh, last: nil, running: [mine, theirs]))
    }

    func testTheLastSessionIsTheShowingSessionThenTheNewestExchangeThenTheOrigin() {
        let old = CommentTarget.Exchange(session: claude, at: Date(timeIntervalSince1970: 100))
        let new = CommentTarget.Exchange(session: other, at: Date(timeIntervalSince1970: 200))
        let undated = CommentTarget.Exchange(session: claude, at: nil)
        XCTAssertEqual(CommentTarget.last(showedIt: claude, exchanges: [new], origin: nil), claude)
        XCTAssertEqual(CommentTarget.last(showedIt: nil, exchanges: [old, new, undated], origin: claude), other)
        XCTAssertEqual(CommentTarget.last(showedIt: nil, exchanges: [], origin: other), other)
        XCTAssertNil(CommentTarget.last(showedIt: nil, exchanges: [], origin: nil))
    }

    func testOnlyANewCommentGoesToASessionThatNeverSawThePin() {
        let asked = Pin.Comment(text: "Move the date")
        let answered = answer("Moved it", from: claude)
        let pinned = pin(1, [asked, answered])
        let edit = CommentChange.edited(pin: pinned.id, comment: asked.id, text: "x")
        XCTAssertTrue(CommentTarget.knows(claude, .posted(pin: pinned.id, comment: UUID(), text: "x", reopens: false), pin: nil, delivered: []))
        XCTAssertFalse(CommentTarget.knows(claude, edit, pin: pinned, delivered: []))
        XCTAssertTrue(CommentTarget.knows(claude, edit, pin: pinned, delivered: [asked.id]))
        XCTAssertTrue(CommentTarget.knows(claude, .deleted(pin: pinned.id, comment: answered.id, text: "x"), pin: pinned, delivered: []))
        XCTAssertTrue(CommentTarget.knows(claude, .resolved(pin: pinned.id), pin: pinned, delivered: []))
        XCTAssertFalse(CommentTarget.knows(other, .resolved(pin: pinned.id), pin: pinned, delivered: []))
    }

    func testChangesInTheWaitMergeIntoTheWordsThatGo() {
        let pinID = UUID(), first = UUID(), second = UUID()
        var held = HeldChanges()
        held.add(.init(change: .posted(pin: pinID, comment: first, text: "Move it", reopens: false), number: 3, x: 0.42, y: 0.18))
        held.add(.init(change: .posted(pin: pinID, comment: second, text: "Typo", reopens: false), number: 3, x: 0.42, y: 0.18))
        held.add(.init(change: .edited(pin: pinID, comment: first, text: "Move it left"), number: 3, x: 0.42, y: 0.18))
        held.add(.init(change: .deleted(pin: pinID, comment: second, text: "Typo"), number: 3, x: 0.42, y: 0.18))
        XCTAssertEqual(held.comments, [first])
        let line = held.line(file: "/shots/Checkout.png")
        XCTAssertTrue(line.hasPrefix("Pin 3: Move it left. [From Vignette: comments on \"/shots/Checkout.png\". Pin 3 (id \(pinID.uuidString), comment \(first.uuidString)) at 42% across and 18% down."), line)

        var undone = HeldChanges()
        undone.add(.init(change: .resolved(pin: pinID), number: 3, x: 0, y: 0))
        undone.add(.init(change: .reopened(pin: pinID), number: 3, x: 0, y: 0))
        XCTAssertTrue(undone.isEmpty)
    }

    func testTheWorkingRowShowsForTheTurnThatStartsAfterTheLineWentIn() {
        var watch = CommentTurnWatch(since: 0)
        XCTAssertEqual(watch.look(.waiting, at: 1), .wait)
        XCTAssertEqual(watch.look(.idle, at: 2), .wait)
        XCTAssertEqual(watch.look(.busy, at: 3), .started)
        XCTAssertEqual(watch.look(.busy, at: 4), .wait)
        XCTAssertEqual(watch.look(.idle, at: 5), .ended)

        var quiet = CommentTurnWatch(since: 0)
        XCTAssertEqual(quiet.look(.idle, at: CommentTurnWatch.startWithin), .ended)
        XCTAssertFalse(quiet.working)
    }

    func testCommentsPostedInTheWaitGoAsOneLineAndADeletedOneNeverGoes() {
        var timers: [@MainActor @Sendable () -> Void] = []
        let connection = Catcher()
        let deliveries = CommentDeliveries(store: nil, connections: [.claude: connection], now: { 0 }, schedule: { _, work in timers.append(work) })
        let file = ScreenshotKey(asGiven: "Checkout.png")
        let destination = AgentDestination(id: claude.id, name: "vignette", address: claude)
        let pinID = UUID(), kept = UUID(), dropped = UUID()
        deliveries.add(.init(change: .posted(pin: pinID, comment: kept, text: "Move it", reopens: false), number: 1, x: 0, y: 0),
                       on: file, to: destination, grace: 3)
        deliveries.add(.init(change: .posted(pin: pinID, comment: dropped, text: "Oops", reopens: false), number: 1, x: 0, y: 0),
                       on: file, to: destination, grace: 3)
        deliveries.add(.init(change: .deleted(pin: pinID, comment: dropped, text: "Oops"), number: 1, x: 0, y: 0),
                       on: file, to: destination, grace: 3)
        XCTAssertEqual(deliveries.shown(comment: kept, on: file)?.state, .sending)
        XCTAssertNil(deliveries.shown(comment: dropped, on: file))
        XCTAssertEqual(timers.count, 1)
        timers.removeFirst()()
        runTheMainQueue()
        XCTAssertEqual(connection.lines.count, 1)
        XCTAssertTrue(connection.lines[0].hasPrefix("Pin 1: Move it. [From Vignette"))
        XCTAssertEqual(deliveries.shown(comment: kept, on: file), CommentDeliveries.Shown(state: .sent, client: .claude, reason: nil))
        XCTAssertEqual(deliveries.delivered(on: file, to: claude), [kept])
    }

    func testALineTheSessionRefusedSaysWhyOnTheComment() {
        let connection = Catcher(answer: .destinationChanged(detail: "gone", reason: ClaudeCodeConnection.closed))
        let deliveries = CommentDeliveries(store: nil, connections: [.claude: connection], now: { 0 }, schedule: { _, work in work() })
        let file = ScreenshotKey(asGiven: "Checkout.png")
        let comment = UUID()
        deliveries.add(.init(change: .posted(pin: UUID(), comment: comment, text: "Move it", reopens: false), number: 1, x: 0, y: 0),
                       on: file, to: AgentDestination(id: claude.id, name: "vignette", address: claude), grace: 0)
        runTheMainQueue()
        XCTAssertEqual(deliveries.shown(comment: comment, on: file),
                       CommentDeliveries.Shown(state: .failed, client: .claude, reason: ClaudeCodeConnection.closed))
        XCTAssertTrue(deliveries.delivered(on: file, to: claude).isEmpty)
    }

    func testDeliveriesAreReadBackAfterARelaunchAndOneStillGoingMayHaveReached() throws {
        let store = FileManager.default.temporaryDirectory.appendingPathComponent("comment-deliveries-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: store) }
        let file = ScreenshotKey(asGiven: "Checkout.png")
        let comment = UUID()
        let going = CommentDeliveries.Delivery(id: "a", file: file.path, client: .claude, session: claude.id, sessionName: "vignette",
                                               comments: [comment], pins: [UUID()], at: Date(), status: .sending)
        try JSONEncoder().encode([going]).write(to: store)
        let deliveries = CommentDeliveries(store: store, connections: [:])
        XCTAssertEqual(deliveries.shown(comment: comment, on: file)?.state, .uncertain)
        deliveries.renamed([(from: file, to: ScreenshotKey(asGiven: "Total.png"))])
        XCTAssertEqual(CommentDeliveries(store: store, connections: [:]).shown(comment: comment, on: ScreenshotKey(asGiven: "Total.png"))?.state, .uncertain)
    }
}

private final class Catcher: AgentConnection, @unchecked Sendable {
    let client = AgentClient.claude
    private let lock = NSLock()
    private var sent: [String] = []
    private let answer: SubmissionOutcome

    init(answer: SubmissionOutcome = .accepted(detail: "")) { self.answer = answer }

    var lines: [String] { lock.lock(); defer { lock.unlock() }; return sent }
    func destinations() -> [AgentDestination] { [] }
    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome {
        lock.lock(); sent.append(line); lock.unlock()
        return answer
    }

    func submit(_ line: String, to destination: AgentDestination, watchingTurn: Bool,
                completion: @escaping @Sendable (SubmissionOutcome) -> Void) {
        completion(submit(line, to: destination))
    }
}
