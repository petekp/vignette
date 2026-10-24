import XCTest

final class AnnotatorTransitionTests: XCTestCase {
    typealias T = AnnotatorTransition

    private let a = Opening(id: 1, key: "a"), b = Opening(id: 2, key: "b")
    private let one = Opening(id: 1, key: "1"), two = Opening(id: 2, key: "2"), three = Opening(id: 3, key: "3")

    // MARK: Fixed seeds

    func testRapidSwapRaceSerializesParks() {
        // Finding 3: annotate 1, then 2 and 3 before the park of 1 completes.
        var t = T()
        XCTAssertEqual(t.reduce(.annotate(one)), [.prepare(one)])
        XCTAssertEqual(t.reduce(.shown(one)), [.show])
        XCTAssertEqual(t.reduce(.annotate(two)), [.park(one)])
        XCTAssertEqual(t.reduce(.annotate(three)), [], "a second request during the park emits nothing")
        XCTAssertEqual(t.phase, .parking(one, then: .annotate(three)))
        XCTAssertEqual(t.reduce(.parked(one)), [.returnCard(one, copied: false), .prepare(three)])
        XCTAssertEqual(t.reduce(.shown(three)), [.show])
        XCTAssertEqual(t.phase, .annotating(three))
    }

    func testClosingDuringTheFlightTurnsTheCardAroundWithoutAPark() {
        var t = T()
        XCTAssertEqual(t.reduce(.annotate(a)), [.prepare(a)])
        XCTAssertEqual(t.reduce(.close), [.abandon(a), .returnCard(a, copied: false)], "no park: the window never came up")
        XCTAssertEqual(t.phase, .idle)
        XCTAssertEqual(t.reduce(.parked(a)), [], "a park that was never asked for answers nothing")
    }

    func testAnnotatingAnotherCardDuringTheFlightSwapsAtOnce() {
        var t = T()
        _ = t.reduce(.annotate(a))
        XCTAssertEqual(t.reduce(.annotate(b)), [.abandon(a), .returnCard(a, copied: false), .prepare(b)])
        XCTAssertEqual(t.phase, .flyingOut(b))
        XCTAssertEqual(t.reduce(.annotate(Opening(id: 3, key: "b"))), [], "the file already flying out")
        XCTAssertEqual(t.phase, .flyingOut(b))
        XCTAssertEqual(t.reduce(.shown(b)), [.show])
        XCTAssertEqual(t.phase, .annotating(b))
    }

    func testAnAnswerForAnOpeningThatHasGoneChangesNothing() {
        var t = T()
        _ = t.reduce(.annotate(a))
        _ = t.reduce(.annotate(b))
        XCTAssertEqual(t.reduce(.shown(a)), [], "the window for a never comes up in place of b's")
        XCTAssertEqual(t.phase, .flyingOut(b))
        _ = t.reduce(.shown(b))
        XCTAssertEqual(t.reduce(.close), [.park(b)])
        XCTAssertEqual(t.reduce(.parked(a)), [])
        XCTAssertEqual(t.phase, .parking(b, then: .close))
        XCTAssertEqual(t.reduce(.parked(b)), [.returnCard(b, copied: false)])
    }

    func testTheSameFileOpenedAgainIsAnotherOpening() {
        var t = T()
        _ = t.reduce(.annotate(a)); _ = t.reduce(.shown(a)); _ = t.reduce(.close); _ = t.reduce(.parked(a))
        let again = Opening(id: 2, key: "a")
        XCTAssertEqual(t.reduce(.annotate(again)), [.prepare(again)])
        XCTAssertEqual(t.reduce(.shown(a)), [], "the first opening's late answer")
        XCTAssertEqual(t.reduce(.shown(again)), [.show])
    }

    func testDismissingDuringTheFlightStillParks() {
        // The panel aims the flight offscreen before this arrives, so the card stays in the layer
        // until the park answers rather than being dropped mid-slide.
        var t = T()
        _ = t.reduce(.annotate(a))
        XCTAssertEqual(t.reduce(.dismiss), [.park(a)])
        XCTAssertEqual(t.reduce(.parked(a)), [.hideAnnotator])
    }

    func testNewShotDuringALoneAnnotationJoinsInsteadOfClosing() {
        // Finding 4.
        var t = T()
        _ = t.reduce(.annotate(a))
        _ = t.reduce(.shown(a))
        XCTAssertEqual(t.reduce(.newShot("b")), [.join("b")])
        XCTAssertEqual(t.phase, .annotating(a))
        XCTAssertEqual(t.reduce(.close), [.park(a)])
        XCTAssertEqual(t.reduce(.parked(a)), [.returnCard(a, copied: false)], "a lone thumbnail flies back to the corner")
        XCTAssertEqual(t.phase, .idle)
    }

    func testDismissWinsOverALaterAnnotate() {
        var t = T()
        _ = t.reduce(.annotate(a)); _ = t.reduce(.shown(a))
        _ = t.reduce(.dismiss)
        XCTAssertEqual(t.reduce(.annotate(b)), [])
        XCTAssertEqual(t.reduce(.parked(a)), [.hideAnnotator])
        XCTAssertEqual(t.phase, .idle)
    }

    func testRemovingTheAnnotatedFileHidesWithoutReturn() {
        var t = T()
        _ = t.reduce(.annotate(a)); _ = t.reduce(.shown(a))
        XCTAssertEqual(t.reduce(.remove("other")), [])
        XCTAssertEqual(t.reduce(.remove("a")), [.park(a)])
        XCTAssertEqual(t.reduce(.parked(a)), [.hideAnnotator])
    }

    func testRemovingTheSwapTargetTurnsTheSwapIntoAClose() {
        var t = T()
        _ = t.reduce(.annotate(a)); _ = t.reduce(.shown(a))
        _ = t.reduce(.annotate(b))
        _ = t.reduce(.remove("b"))
        XCTAssertEqual(t.reduce(.parked(a)), [.returnCard(a, copied: false)])
    }

    func testStrayEventsDoNothing() {
        var t = T()
        for e in [T.Event.shown(a), .parked(a), .close, .finish, .dismiss, .remove("x"), .newShot("y")] { XCTAssertEqual(t.reduce(e), [], "\(e)") }
        XCTAssertEqual(t.phase, .idle)
    }

    func testFinishReturnsTheCardMarkedCopied() {
        var t = T()
        _ = t.reduce(.annotate(a)); _ = t.reduce(.shown(a))
        XCTAssertEqual(t.reduce(.finish), [.park(a)])
        XCTAssertEqual(t.reduce(.parked(a)), [.returnCard(a, copied: true)])
        XCTAssertEqual(t.phase, .idle)
    }

    func testRemovingTheFileDuringAFinishHidesWithoutReturn() {
        var t = T()
        _ = t.reduce(.annotate(a)); _ = t.reduce(.shown(a)); _ = t.reduce(.finish)
        XCTAssertEqual(t.reduce(.remove("a")), [])
        XCTAssertEqual(t.reduce(.parked(a)), [.hideAnnotator])
    }

    func testAnnotatingAnotherKeyDuringAFinishSwaps() {
        var t = T()
        _ = t.reduce(.annotate(a)); _ = t.reduce(.shown(a)); _ = t.reduce(.finish)
        XCTAssertEqual(t.reduce(.annotate(Opening(id: 2, key: "a"))), [], "the finishing file is coming back anyway")
        XCTAssertEqual(t.reduce(.parked(a)), [.returnCard(a, copied: true)])
        let again = Opening(id: 3, key: "a"), next = Opening(id: 4, key: "b")
        _ = t.reduce(.annotate(again)); _ = t.reduce(.shown(again)); _ = t.reduce(.finish)
        _ = t.reduce(.annotate(next))
        XCTAssertEqual(t.reduce(.parked(again)), [.returnCard(again, copied: false), .prepare(next)])
    }

    // MARK: Random sequences

    /// Plays random events against the reducer with an environment that answers `park` with
    /// `parked` and `prepare` with `shown` after a random delay, and checks the invariants. A delay
    /// of 0 is an answer in the same turn: it arrives while its event is still being handled, and
    /// `EventHold` runs it right after, before anything else, as `ThumbnailController` does. Late
    /// answers for openings that have gone are part of the mix.
    func testRandomSequencesKeepTheInvariants() {
        let keys: [ScreenshotKey] = ["a", "b", "c"]
        var sameTurn = 0
        for seed in 0..<500 {
            var rng = SeededGenerator(seed: UInt64(seed))
            var t = T()
            var pending: [(due: Int, event: T.Event)] = []
            var parksInFlight = 0
            var prepared: Opening?
            var minted: [Opening] = []
            var trace: [String] = []
            let hold = EventHold<T.Event>()
            for step in 0..<40 {
                // Deliver environment answers whose time has come.
                let due = pending.filter { $0.due <= step }
                pending.removeAll { $0.due <= step }
                var events = due.map(\.event)
                switch Int.random(in: 0..<8, using: &rng) {
                case 0...2:
                    let opening = Opening(id: minted.count + 1, key: keys.randomElement(using: &rng)!)
                    minted.append(opening)
                    events.append(.annotate(opening))
                case 3: events.append(Bool.random(using: &rng) ? .close : .finish)
                case 4: events.append(.newShot(ScreenshotKey(asGiven: "n\(step)")))
                case 5: events.append(.dismiss)
                case 6: events.append(.remove(keys.randomElement(using: &rng)!))
                case 7:
                    if let stale = minted.randomElement(using: &rng), stale != t.opening {
                        events.append(Bool.random(using: &rng) ? .shown(stale) : .parked(stale))
                    }
                default: break
                }
                for sent in events {
                    hold.send(sent) { event in
                        // When the environment answers an effect: in a later step, or in this
                        // one, which the hold runs right after the event being handled.
                        func answer(_ answer: T.Event) {
                            let delay = Int.random(in: 0...3, using: &rng)
                            if delay == 0 { hold.send(answer) { _ in XCTFail("a held event runs in the loop that holds it") }; sameTurn += 1 }
                            else { pending.append((step + delay, answer)) }
                        }
                        var answersPark = false
                        if case .parked(let o) = event, case .parking(o, _) = t.phase { answersPark = true }
                        var stale = false
                        switch event {
                        case .shown(let o), .parked(let o): stale = o != t.opening
                        default: break
                        }
                        let effects = t.reduce(event)
                        trace.append("\(event) -> \(effects) [\(t.phase)]")
                        if answersPark { parksInFlight -= 1 }
                        if stale { XCTAssertEqual(effects, [], "an answer for another opening changes nothing (seed \(seed))") }
                        for effect in effects {
                            switch effect {
                            case .park(let k):
                                parksInFlight += 1
                                XCTAssertEqual(parksInFlight, 1, "at most one park in flight (seed \(seed))\n" + trace.joined(separator: "\n"))
                                XCTAssertEqual(k, prepared, "park is for the opening that was prepared (seed \(seed))")
                                answer(.parked(k))
                            case .prepare(let k):
                                XCTAssertEqual(parksInFlight, 0, "no prepare while a park is in flight (seed \(seed))\n" + trace.joined(separator: "\n"))
                                prepared = k
                                answer(.shown(k))
                            case .show:
                                XCTAssertEqual(prepared, t.opening, "a visible annotator shows the prepared image (seed \(seed))")
                            case .abandon(let k):
                                XCTAssertEqual(k, prepared, "abandon is for the opening that was prepared (seed \(seed))")
                                prepared = nil
                            case .returnCard, .hideAnnotator:
                                prepared = nil
                            case .join:
                                break
                            }
                        }
                    }
                }
                if case .annotating(let k) = t.phase { XCTAssertEqual(prepared, k, "annotating implies the image is loaded (seed \(seed))") }
            }
            // Drain: a dismiss followed by every pending answer ends idle with nothing loaded.
            _ = t.reduce(.dismiss)
            for _ in 0..<6 {
                for answer in pending.map(\.event) { _ = t.reduce(answer) }
                pending.removeAll()
                if case .parking(let o, _) = t.phase { _ = t.reduce(.parked(o)) }
            }
            XCTAssertEqual(t.phase, .idle, "dismiss ends with everything hidden (seed \(seed))")
        }
        XCTAssertGreaterThan(sameTurn, 1000, "answers in the same turn are part of the mix")
    }
}

/// A tiny deterministic generator so failures name a seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
