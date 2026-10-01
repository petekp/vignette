import XCTest

final class AnnotationRunTests: XCTestCase {
    typealias R = AnnotationRun

    /// Every file opens except those named.
    private func reduce(_ run: inout R, _ event: R.Event, unreadable: Set<String> = []) -> [R.Effect] {
        run.reduce(event) { !unreadable.contains($0) }
    }

    // MARK: Rules

    func testAListOpensItsFilesInTurnAndTheLastDoneEndsTheRun() {
        var r = R()
        XCTAssertEqual(reduce(&r, .annotate(["a", "b", "c"])), [.prepare("a")])
        XCTAssertEqual(r.queue, ["b", "c"])
        _ = reduce(&r, .shown); _ = reduce(&r, .finish)
        XCTAssertEqual(reduce(&r, .parked), [.returnCard("a", copied: true), .next("b", place: 2, of: 3), .prepare("b")],
                       "the finished card goes home and the next file flies out in one batch, as a swap's do")
        _ = reduce(&r, .shown); _ = reduce(&r, .finish)
        XCTAssertEqual(reduce(&r, .parked), [.returnCard("b", copied: true), .next("c", place: 3, of: 3), .prepare("c")])
        _ = reduce(&r, .shown); _ = reduce(&r, .finish)
        XCTAssertEqual(reduce(&r, .parked), [.returnCard("c", copied: true), .endRun(restoreFocus: true)])
        XCTAssertFalse(r.isActive)
        XCTAssertEqual(r.queue, [])
    }

    func testEscEndsTheRun() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b"])); _ = reduce(&r, .shown)
        XCTAssertEqual(reduce(&r, .cancel), [.park("a")])
        XCTAssertEqual(r.queue, [], "the rest of the list is dropped at once")
        XCTAssertEqual(reduce(&r, .parked), [.returnCard("a", copied: false), .endRun(restoreFocus: true)])
    }

    func testSendGoesOnToTheNextFile() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b"])); _ = reduce(&r, .shown)
        XCTAssertEqual(reduce(&r, .sent), [.park("a")])
        XCTAssertEqual(reduce(&r, .parked), [.returnCard("a", copied: false), .next("b", place: 2, of: 2), .prepare("b")])

        var early = R()
        _ = reduce(&early, .annotate(["a", "b"]))
        XCTAssertEqual(reduce(&early, .sent), [.abandon("a"), .returnCard("a", copied: false), .next("b", place: 2, of: 2), .prepare("b")],
                       "a Send before the flight lands goes on too")
    }

    func testADismissalEndsTheRunAndOnlyAHandReturnsTheFocus() {
        var quick = R()
        _ = reduce(&quick, .annotate(["a", "b"])); _ = reduce(&quick, .shown)
        XCTAssertEqual(reduce(&quick, .dismiss(byHand: true)), [.park("a")])
        XCTAssertEqual(reduce(&quick, .parked), [.hideAnnotator, .endRun(restoreFocus: true)])

        var hotkey = R()
        _ = reduce(&hotkey, .annotate(["a", "b"])); _ = reduce(&hotkey, .shown)
        _ = reduce(&hotkey, .dismiss(byHand: false))
        XCTAssertEqual(reduce(&hotkey, .parked), [.hideAnnotator, .endRun(restoreFocus: false)])
    }

    func testADismissalWhoseParkAnswersInTheSameTurnOpensNothing() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b"])); _ = reduce(&r, .shown)
        let hold = EventHold<R.Event>()
        var effects: [R.Effect] = []
        hold.send(.dismiss(byHand: false)) { event in
            let batch = reduce(&r, event)
            effects += batch
            if batch.contains(.park("a")) { hold.send(.parked) { _ in } }
        }
        XCTAssertEqual(effects, [.park("a"), .hideAnnotator, .endRun(restoreFocus: false)])
    }

    func testAListRequestedDuringADismissalOpensNothing() {
        var r = R()
        _ = reduce(&r, .annotate(["a"])); _ = reduce(&r, .shown)
        _ = reduce(&r, .dismiss(byHand: false))
        XCTAssertEqual(reduce(&r, .annotate(["b", "c"])), [])
        XCTAssertEqual(reduce(&r, .parked), [.hideAnnotator, .endRun(restoreFocus: false)])
        XCTAssertEqual(r.queue, [])
    }

    func testAQueuedFileThatDoesNotOpenIsPassedOver() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b", "c"])); _ = reduce(&r, .shown); _ = reduce(&r, .finish)
        XCTAssertEqual(reduce(&r, .parked, unreadable: ["b"]), [.returnCard("a", copied: true), .next("c", place: 2, of: 3), .prepare("c")])
        XCTAssertEqual(r.phase, .flyingOut("c"))

        var none = R()
        _ = reduce(&none, .annotate(["a", "b", "c"])); _ = reduce(&none, .shown); _ = reduce(&none, .finish)
        XCTAssertEqual(reduce(&none, .parked, unreadable: ["b", "c"]), [.returnCard("a", copied: true), .endRun(restoreFocus: true)],
                       "with no file left to open, the run ends rather than staying open with nothing in it")
        XCTAssertFalse(none.isActive)
    }

    func testAFileGoneFromTheQueueSkipsNoNumber() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b", "c"])); _ = reduce(&r, .shown)
        XCTAssertEqual(reduce(&r, .remove(["b"])), [])
        _ = reduce(&r, .finish)
        XCTAssertEqual(reduce(&r, .parked), [.returnCard("a", copied: true), .next("c", place: 2, of: 3), .prepare("c")])
    }

    func testRemovingTheOpenFileEndsTheRun() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b"])); _ = reduce(&r, .shown)
        XCTAssertEqual(reduce(&r, .remove(["a"])), [.park("a")])
        XCTAssertEqual(r.queue, [])
        XCTAssertEqual(reduce(&r, .parked), [.hideAnnotator, .endRun(restoreFocus: false)])
    }

    func testASelectionQueuesAndUnqueuesFilesButNeverTheOpenOne() {
        var idle = R()
        XCTAssertEqual(reduce(&idle, .selectionChanged(added: ["a"], removed: [])), [], "nothing is open to queue behind")

        var r = R()
        _ = reduce(&r, .annotate(["a"])); _ = reduce(&r, .shown)
        XCTAssertEqual(reduce(&r, .selectionChanged(added: ["a", "b", "c"], removed: [])),
                       [.queued("b", place: 2, of: 2), .queued("c", place: 3, of: 3)])
        XCTAssertEqual(reduce(&r, .selectionChanged(added: [], removed: ["b"])), [])
        XCTAssertEqual(r.queue, ["c"])
        _ = reduce(&r, .finish)
        XCTAssertEqual(reduce(&r, .parked), [.returnCard("a", copied: true), .next("c", place: 2, of: 2), .prepare("c")])
    }

    func testAFailedCopyTakesTheMarkOffTheCardOnItsWayHome() {
        var r = R()
        _ = reduce(&r, .annotate(["a"])); _ = reduce(&r, .shown); _ = reduce(&r, .finish)
        XCTAssertEqual(reduce(&r, .copyFailed("a")), [])
        XCTAssertEqual(reduce(&r, .parked), [.returnCard("a", copied: false), .endRun(restoreFocus: true)])

        _ = reduce(&r, .copyFailed("a"))
        _ = reduce(&r, .annotate(["a"])); _ = reduce(&r, .shown); _ = reduce(&r, .finish)
        XCTAssertEqual(reduce(&r, .parked), [.returnCard("a", copied: true), .endRun(restoreFocus: true)],
                       "a failure reported after the card came home says nothing about its next copy")
    }

    // MARK: Random sequences

    /// Plays random events against the run, with an environment that answers `park` with `parked`
    /// and `prepare` with `shown`, sometimes in the same turn through `EventHold`, and one file, "x",
    /// that never opens. Checks the transition's invariants and the run's own.
    func testRandomSequencesKeepTheInvariants() {
        let keys = ["a", "b", "c", "d"]
        var sameTurn = 0, handovers = 0, passedOver = 0
        for seed in 0..<1000 {
            var rng = SeededGenerator(seed: UInt64(seed))
            var r = R()
            let hold = EventHold<R.Event>()
            var pending: [(due: Int, event: R.Event)] = []
            var parksInFlight = 0
            var prepared: String?
            var running = false      // a prepare has run since the last endRun
            var dismissing = false   // a dismissal reached an open run, which is now ending
            var uncopied: String?    // a copy failed while this card was parking after Done
            var trace: [String] = []
            func fail(_ message: String) -> String { "\(message) (seed \(seed))\n" + trace.joined(separator: "\n") }

            func handle(_ event: R.Event, at step: Int) {
                func answer(_ answer: R.Event) {
                    if Int.random(in: 0...3, using: &rng) == 0 { hold.send(answer) { _ in }; sameTurn += 1 }
                    else { pending.append((step + Int.random(in: 1...3, using: &rng), answer)) }
                }
                let wasActive = r.isActive
                if case .dismiss = event, wasActive { dismissing = true }
                if case .copyFailed(let k) = event, case .parking(k, then: .finish) = r.phase { uncopied = k }
                let effects = r.reduce(event) { key in
                    if key == "x" { passedOver += 1; return false }
                    return true
                }
                trace.append("\(event) -> \(effects) [\(r)]")
                if event == .parked { parksInFlight -= 1 }
                for effect in effects {
                    switch effect {
                    case .park(let k):
                        parksInFlight += 1
                        XCTAssertEqual(parksInFlight, 1, fail("at most one park in flight"))
                        XCTAssertEqual(k, prepared, fail("park is for the key that was prepared"))
                        answer(.parked)
                    case .prepare(let k):
                        XCTAssertEqual(parksInFlight, 0, fail("no prepare while a park is in flight"))
                        XCTAssertFalse(dismissing, fail("nothing opens while a dismissal ends the run"))
                        XCTAssertNotEqual(k, "x", fail("a file that does not open is never prepared"))
                        prepared = k
                        running = true
                        answer(.shown)
                    case .abandon(let k):
                        XCTAssertEqual(k, prepared, fail("abandon is for the key that was prepared"))
                        prepared = nil
                    case .returnCard(let k, let copied):
                        if uncopied == k { XCTAssertFalse(copied, fail("a failed copy leaves the card unmarked")) }
                        uncopied = nil
                        prepared = nil
                    case .hideAnnotator:
                        prepared = nil
                    case .next(_, let place, let total):
                        handovers += 1
                        XCTAssertTrue((1...total).contains(place), fail("next counts within its run"))
                    case .queued(_, let place, let total):
                        XCTAssertTrue((1...total).contains(place), fail("queued counts within its run"))
                    case .endRun:
                        XCTAssertTrue(running, fail("endRun comes once per run"))
                        running = false
                        dismissing = false
                    case .show, .join:
                        break
                    }
                }
                let ended = effects.contains { if case .endRun = $0 { return true }; return false }
                XCTAssertEqual(ended, wasActive && !r.isActive, fail("endRun comes exactly when the run goes idle"))
                switch event {
                case .cancel, .dismiss: XCTAssertEqual(r.queue, [], fail("Esc and a dismissal drop the rest of the list"))
                default: break
                }
                if !r.isActive { XCTAssertEqual(r.queue, [], fail("an idle run queues nothing")) }
                if case .annotating(let k) = r.phase { XCTAssertEqual(prepared, k, fail("annotating implies the image is loaded")) }
            }

            for step in 0..<40 {
                let due = pending.filter { $0.due <= step }
                pending.removeAll { $0.due <= step }
                var events = due.map(\.event)
                func some() -> [String] { (keys + ["x"]).filter { _ in Int.random(in: 0..<3, using: &rng) == 0 } }
                switch Int.random(in: 0..<12, using: &rng) {
                case 0...2:
                    // A person's request starts with a file that reads, as the controller checks;
                    // the rest of the list may not.
                    events.append(.annotate([keys.randomElement(using: &rng)!] + some()))
                case 3: events.append(.cancel)
                case 4: events.append(.sent)
                case 5: events.append(.finish)
                case 6: events.append(.dismiss(byHand: Bool.random(using: &rng)))
                case 7: events.append(.remove(some()))
                case 8: events.append(.newShot("n\(step)"))
                case 9: events.append(.selectionChanged(added: some().filter { $0 != "x" }, removed: some()))
                case 10: events.append(.copyFailed(keys.randomElement(using: &rng)!))
                default: break
                }
                for event in events { hold.send(event) { handle($0, at: step) } }
            }
            // Drain: a dismissal and every answer still owed end the run.
            hold.send(.dismiss(byHand: false)) { handle($0, at: 40) }
            for step in 41..<60 {
                let due = pending.filter { $0.due <= step }
                pending.removeAll { $0.due <= step }
                for event in due.map(\.event) { hold.send(event) { handle($0, at: step) } }
            }
            XCTAssertEqual(r.phase, .idle, fail("a dismissal ends with everything hidden"))
            XCTAssertFalse(running, fail("the run ended"))
        }
        XCTAssertGreaterThan(sameTurn, 1000, "answers in the same turn are part of the mix")
        XCTAssertGreaterThan(handovers, 500, "the queue hands over")
        XCTAssertGreaterThan(passedOver, 100, "files that do not open are part of the mix")
    }
}
