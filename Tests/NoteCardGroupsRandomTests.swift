import XCTest

/// The waits of grouped notes in any order of events (`NoteCardGroups`).
final class NoteCardGroupsRandomTests: XCTestCase, NoteCardGroupsTesting {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    /// Catches a group that makes two cards from one look, a card when no note that may be answered
    /// changed or none when one did in a window not in front, the first note to change not making it, a card with no note
    /// behind a late answer, a note that a card answers saying Done while the card stands, more than one
    /// Done aloud for the notes one look or one failed card ends, or a note ending twice, whatever
    /// order the events come in.
    func testAnyOrderOfGroupEventsMakesAtMostOneCardPerLook() {
        let turns: [SessionTurn?] = [.busy, .busy, .idle, .idle, .idle, .idle, .idle, .waiting, nil]
        // A session mostly runs a turn through: its request waits, the turn runs, then it is idle.
        let script: [SessionTurn] = [.waiting, .busy, .busy, .idle, .idle, .idle]
        var seedsWithGroupedCard = 0
        for seed in 0..<1000 {
            var rng = SeededGenerator(seed: UInt64(seed))
            var frontRng = SeededGenerator(seed: UInt64(seed) &+ 1_000_003)
            var waits = NoteCardGroups()
            let ids = (1...Int.random(in: 1...6, using: &rng)).map { "r\($0)" }
            var windows: [String: NoteCardGroups.SessionWindow] = [:]
            var trace: [String] = []
            func fail(_ message: String) -> String { "\(message) (seed \(seed))\n" + trace.joined(separator: "\n") }
            func sendOrder(_ group: [String]) -> [String] { group.sorted { ids.firstIndex(of: $0)! < ids.firstIndex(of: $1)! } }
            var now = t0
            var looks: [[String]] = []
            var answered = Set<Int>()
            var lookedRequests = Set<String>()
            var cardOf: [String: Int] = [:]
            var cursor: [String: Int] = [:]
            var cardsMade: [[String]] = []
            var failedCards = Set<Int>()
            var cards = 0, groupedHere = false
            var replies: [String: Int] = [:], dones: [String: Int] = [:]

            func run(_ input: NoteCardGroups.Input, changed: Set<String> = [], look: Int? = nil) {
                // What a look must answer: the notes still looking that the session has not replied to.
                var expected: (members: Set<String>, maker: String?)?
                var skipped = Set<String>()
                if case .looked(let group, let changed, let replied, let uncompared, let inFront) = input {
                    let members = sendOrder(group).filter { waits[$0]?.isLookingAgain == true && !replied.contains($0) && !uncompared.contains($0) }
                    expected = (Set(members), inFront ? nil : members.first { changed.contains($0) })
                    skipped = uncompared
                }
                let actions = waits.handle(input, at: now)
                trace.append("\(now.timeIntervalSince(t0)) \(input) -> \(actions)")
                if let look, !answered.insert(look).inserted { XCTAssertEqual(actions, [], fail("a look is answered once")) }
                var made: [[String]] = []
                var doneNow = 0, loudNow = 0
                for action in actions {
                    switch action {
                    case .watchTurn:
                        break
                    case .note(let id, let effect):
                        XCTAssertFalse([.watchTurn, .lookAgain].contains(effect), fail("a wish is merged"))
                        if effect == .replyIsTheResult { replies[id, default: 0] += 1 }
                        if effect == .sayDone || effect == .sayDoneQuietly {
                            dones[id, default: 0] += 1
                            if effect == .sayDone { loudNow += 1 }
                            if !skipped.contains(id) { doneNow += 1 }
                            XCTAssertFalse(changed.contains(id), fail("a note whose region changed says nothing more"))
                        }
                        if effect == .drawReplyOnResultCard { XCTAssertNotNil(cardOf[id], fail("no card to draw on")) }
                    case .look(let group):
                        XCTAssertEqual(group, sendOrder(group), fail("a look is in send order"))
                        XCTAssertEqual(Set(group.compactMap { windows[$0] }).count, 1, fail("a look is of one window"))
                        for id in group { XCTAssertTrue(lookedRequests.insert(id).inserted, fail("\(id) is looked at once")) }
                        looks.append(group)
                    case .makeResultCard(let group):
                        made.append(group)
                        XCTAssertEqual(Set(group.compactMap { windows[$0] }).count, 1, fail("a card is of one window"))
                        XCTAssertEqual(Array(group.dropFirst()), sendOrder(Array(group.dropFirst())), fail("a card lists its notes in send order"))
                        for id in group {
                            XCTAssertNil(cardOf[id], fail("\(id) is in one card"))
                            cardOf[id] = cards
                        }
                        cardsMade.append(group)
                        cards += 1
                        if group.count > 1 { groupedHere = true }
                    }
                }
                XCTAssertLessThanOrEqual(made.count, 1, fail("a look makes at most one card"))
                if let expected {
                    XCTAssertEqual(made.first?.first, expected.maker, fail("the first note to change makes the card, and none changed otherwise"))
                    XCTAssertEqual(Set(made.first ?? []), expected.maker == nil ? [] : expected.members, fail("the card answers every note not replied to"))
                }
                if !made.isEmpty {
                    XCTAssertEqual(doneNow, 0, fail("a note a card answers says no Done"))
                    XCTAssertEqual(loudNow, 0, fail("a card that comes up needs no Done aloud"))
                }
                switch input {
                case .looked, .cardFailed: XCTAssertLessThanOrEqual(loudNow, 1, fail("one Done aloud for the notes a look or a failed card ends"))
                default: break
                }
                for id in ids {
                    XCTAssertLessThanOrEqual(replies[id, default: 0] + dones[id, default: 0], 1, fail("\(id) ends once"))
                    if replies[id] != nil { XCTAssertNil(cardOf[id], fail("a reply is not part of a card")) }
                    if dones[id] != nil, let card = cardOf[id] { XCTAssertTrue(failedCards.contains(card), fail("\(id) says Done while its card stands")) }
                }
            }

            for id in ids {
                // Most notes share a place, since only they can be answered by one card.
                let window = onWindow(Int.random(in: 0..<4, using: &rng) == 0 ? 2 : 1, session: Int.random(in: 0..<4, using: &rng) == 0 ? "s2" : "s1")
                windows[id] = window
                run(.sent(id, window, reportsTurns: Int.random(in: 0..<5, using: &rng) > 0, canLookAgain: Int.random(in: 0..<7, using: &rng) > 0))
            }
            for _ in 0..<Int.random(in: 1...60, using: &rng) {
                // Mostly short steps, as the tick's, so waits last long enough to end together; now and then a long one.
                now += [0.5, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 5, 5, 5, 30, 1000].randomElement(using: &rng)!
                switch Int.random(in: 0...9, using: &rng) {
                case 0:
                    run(.delivered(ids.randomElement(using: &rng)!, failed: Int.random(in: 0..<8, using: &rng) == 0))
                case 1, 2, 3, 4:
                    // A session's turn is read once, so its notes on every window get the same reading.
                    var turnAt: [String: SessionTurn?] = [:]
                    var readings: [NoteCardGroups.Reading] = []
                    for id in ids where Int.random(in: 0..<12, using: &rng) > 0 {
                        let session = windows[id]!.session
                        if turnAt[session] == nil {
                            if Int.random(in: 0..<8, using: &rng) == 0 {
                                turnAt[session] = .some(turns.randomElement(using: &rng)!)
                            } else {
                                turnAt[session] = .some(script[cursor[session, default: 0] % script.count])
                                cursor[session, default: 0] += 1
                            }
                        }
                        readings.append(NoteCardGroups.Reading(request: id, turn: turnAt[session]!, replied: Int.random(in: 0..<15, using: &rng) == 0))
                    }
                    run(.turns(readings.shuffled(using: &rng)))
                case 5, 6:
                    guard let index = looks.indices.randomElement(using: &rng) else { continue }
                    let group = looks[index]
                    let changed = Set(group.filter { _ in Bool.random(using: &rng) })
                    let replied = Set(group.filter { _ in Int.random(in: 0..<5, using: &rng) == 0 })
                    let uncompared = Set(group.filter { !changed.contains($0) && Int.random(in: 0..<6, using: &rng) == 0 })
                    let inFront = Int.random(in: 0..<6, using: &frontRng) == 0
                    run(.looked(group.shuffled(using: &rng), changed: changed, replied: replied, uncompared: uncompared, inFront: inFront),
                        changed: inFront ? [] : changed, look: index)
                case 7:
                    guard let index = cardsMade.indices.randomElement(using: &rng) else { continue }
                    failedCards.insert(index)
                    run(.cardFailed(cardsMade[index].shuffled(using: &rng)))
                default:
                    run(.answer(ids.randomElement(using: &rng)!))
                }
            }
            if groupedHere { seedsWithGroupedCard += 1 }
        }
        XCTAssertGreaterThan(seedsWithGroupedCard, 80, "the mix no longer reaches cards that answer several notes: retune the generator, not the reducer")
    }
}
