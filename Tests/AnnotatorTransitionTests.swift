import XCTest

final class AnnotatorTransitionTests: XCTestCase {
    typealias T = AnnotatorTransition

    // MARK: Fixed seeds

    func testRapidSwapRaceSerializesParks() {
        // Finding 3: annotate 1, then 2 and 3 before the park of 1 completes.
        var t = T()
        XCTAssertEqual(t.reduce(.annotate("1", from: .stack)), [.prepare("1")])
        XCTAssertEqual(t.reduce(.shown), [.show])
        XCTAssertEqual(t.reduce(.annotate("2", from: .stack)), [.park("1")])
        XCTAssertEqual(t.reduce(.annotate("3", from: .stack)), [], "a second request during the park emits nothing")
        XCTAssertEqual(t.phase, .parking("1", then: .annotate("3")))
        XCTAssertEqual(t.reduce(.parked), [.returnCard("1"), .prepare("3")])
        XCTAssertEqual(t.reduce(.shown), [.show])
        XCTAssertEqual(t.phase, .annotating("3"))
    }

    func testNewShotDuringALoneAnnotationJoinsInsteadOfClosing() {
        // Finding 4.
        var t = T()
        _ = t.reduce(.annotate("a", from: .thumbnail))
        _ = t.reduce(.shown)
        XCTAssertEqual(t.reduce(.newShot("b")), [.join("b")])
        XCTAssertEqual(t.phase, .annotating("a"))
        XCTAssertEqual(t.reduce(.close), [.park("a")])
        XCTAssertEqual(t.reduce(.parked), [.hideAnnotator], "a lone card has no slot to return to")
        XCTAssertEqual(t.phase, .idle)
    }

    func testCloseFromTheStackReturnsTheCard() {
        var t = T()
        _ = t.reduce(.annotate("a", from: .stack)); _ = t.reduce(.shown)
        XCTAssertEqual(t.reduce(.close), [.park("a")])
        XCTAssertEqual(t.reduce(.parked), [.returnCard("a")])
        XCTAssertEqual(t.phase, .idle)
    }

    func testDismissWinsOverALaterAnnotate() {
        var t = T()
        _ = t.reduce(.annotate("a", from: .stack)); _ = t.reduce(.shown)
        _ = t.reduce(.dismiss)
        XCTAssertEqual(t.reduce(.annotate("b", from: .stack)), [])
        XCTAssertEqual(t.reduce(.parked), [.hideAnnotator])
        XCTAssertEqual(t.phase, .idle)
    }

    func testRemovingTheAnnotatedFileHidesWithoutReturn() {
        var t = T()
        _ = t.reduce(.annotate("a", from: .stack)); _ = t.reduce(.shown)
        XCTAssertEqual(t.reduce(.remove("other")), [])
        XCTAssertEqual(t.reduce(.remove("a")), [.park("a")])
        XCTAssertEqual(t.reduce(.parked), [.hideAnnotator])
    }

    func testRemovingTheSwapTargetTurnsTheSwapIntoAClose() {
        var t = T()
        _ = t.reduce(.annotate("a", from: .stack)); _ = t.reduce(.shown)
        _ = t.reduce(.annotate("b", from: .stack))
        _ = t.reduce(.remove("b"))
        XCTAssertEqual(t.reduce(.parked), [.returnCard("a")])
    }

    func testStrayEventsDoNothing() {
        var t = T()
        for e in [T.Event.shown, .parked, .close, .finish, .dismiss, .remove("x"), .newShot("y")] { XCTAssertEqual(t.reduce(e), [], "\(e)") }
        XCTAssertEqual(t.phase, .idle)
    }

    func testFinishReturnsTheCardMarkedCopiedFromEitherOrigin() {
        for origin in [T.Origin.stack, .thumbnail] {
            var t = T()
            _ = t.reduce(.annotate("a", from: origin)); _ = t.reduce(.shown)
            XCTAssertEqual(t.reduce(.finish), [.park("a")], "\(origin)")
            XCTAssertEqual(t.reduce(.parked), [.returnCard("a"), .markCopied("a")], "\(origin): Done brings the card back, even a lone thumbnail")
            XCTAssertEqual(t.phase, .idle)
        }
    }

    func testRemovingTheFileDuringAFinishHidesWithoutReturn() {
        var t = T()
        _ = t.reduce(.annotate("a", from: .thumbnail)); _ = t.reduce(.shown); _ = t.reduce(.finish)
        XCTAssertEqual(t.reduce(.remove("a")), [])
        XCTAssertEqual(t.reduce(.parked), [.hideAnnotator])
    }

    func testAnnotatingAnotherKeyDuringAFinishSwaps() {
        var t = T()
        _ = t.reduce(.annotate("a", from: .stack)); _ = t.reduce(.shown); _ = t.reduce(.finish)
        XCTAssertEqual(t.reduce(.annotate("a", from: .stack)), [], "the finishing key is coming back anyway")
        XCTAssertEqual(t.reduce(.parked), [.returnCard("a"), .markCopied("a")])
        _ = t.reduce(.annotate("a", from: .stack)); _ = t.reduce(.shown); _ = t.reduce(.finish)
        _ = t.reduce(.annotate("b", from: .stack))
        XCTAssertEqual(t.reduce(.parked), [.returnCard("a"), .prepare("b")])
    }

    // MARK: Random sequences

    /// Plays random events against the reducer with an environment that answers `park` with
    /// `parked` and `prepare` with `shown` after a random delay, and checks the invariants.
    func testRandomSequencesKeepTheInvariants() {
        let keys = ["a", "b", "c"]
        for seed in 0..<500 {
            var rng = SeededGenerator(seed: UInt64(seed))
            var t = T()
            var pending: [(due: Int, event: T.Event)] = []
            var parksInFlight = 0
            var preparedKey: String?
            var trace: [String] = []
            for step in 0..<40 {
                // Deliver environment answers whose time has come.
                let due = pending.filter { $0.due <= step }
                pending.removeAll { $0.due <= step }
                var events = due.map(\.event)
                switch Int.random(in: 0..<8, using: &rng) {
                case 0...2: events.append(.annotate(keys.randomElement(using: &rng)!, from: Bool.random(using: &rng) ? .stack : .thumbnail))
                case 3: events.append(Bool.random(using: &rng) ? .close : .finish)
                case 4: events.append(.newShot("n\(step)"))
                case 5: events.append(.dismiss)
                case 6: events.append(.remove(keys.randomElement(using: &rng)!))
                default: break
                }
                for event in events {
                    let effects = t.reduce(event)
                    trace.append("\(event) -> \(effects) [\(t.phase)]")
                    if event == .parked { parksInFlight -= 1 }
                    for effect in effects {
                        switch effect {
                        case .park(let k):
                            parksInFlight += 1
                            XCTAssertEqual(parksInFlight, 1, "at most one park in flight (seed \(seed))\n" + trace.joined(separator: "\n"))
                            XCTAssertEqual(k, preparedKey, "park is for the key that was prepared (seed \(seed))")
                            pending.append((step + Int.random(in: 0...3, using: &rng), .parked))
                        case .prepare(let k):
                            XCTAssertEqual(parksInFlight, 0, "no prepare while a park is in flight (seed \(seed))\n" + trace.joined(separator: "\n"))
                            preparedKey = k
                            pending.append((step + Int.random(in: 0...3, using: &rng), .shown))
                        case .show:
                            XCTAssertEqual(preparedKey, t.key, "a visible annotator shows the prepared image (seed \(seed))")
                        case .returnCard, .hideAnnotator:
                            preparedKey = nil
                        case .join, .markCopied:
                            break
                        }
                    }
                }
                if case .annotating(let k) = t.phase { XCTAssertEqual(preparedKey, k, "annotating implies the image is loaded (seed \(seed))") }
            }
            // Drain: a dismiss followed by every pending answer ends idle with nothing loaded.
            _ = t.reduce(.dismiss)
            for _ in 0..<6 {
                for answer in pending.map(\.event) { _ = t.reduce(answer) }
                pending.removeAll()
                if case .parking = t.phase { _ = t.reduce(.parked) }
            }
            XCTAssertEqual(t.phase, .idle, "dismiss ends with everything hidden (seed \(seed))")
        }
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
