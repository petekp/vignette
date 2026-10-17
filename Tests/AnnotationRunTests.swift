import XCTest

final class AnnotationRunTests: XCTestCase {
    typealias R = AnnotationRun

    /// Every file opens except those named.
    private func reduce(_ run: inout R, _ event: R.Event, unreadable: Set<ScreenshotKey> = []) -> [R.Effect] {
        run.reduce(event) { !unreadable.contains($0) }
    }

    private func o(_ key: ScreenshotKey, _ id: Int) -> Opening { Opening(id: id, key: key) }

    private func shown(_ run: inout R) -> [R.Effect] { reduce(&run, .shown(run.opening!)) }

    private func parked(_ run: inout R, unreadable: Set<ScreenshotKey> = []) -> [R.Effect] {
        reduce(&run, .parked(run.opening!), unreadable: unreadable)
    }

    func testARenameReKeysTheOpenImageAndTheQueueAndKeepsTheOpeningIds() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b", "c"])); _ = shown(&r)
        let before = r.opening!
        XCTAssertEqual(reduce(&r, .renamed(from: "a", to: "a2")), [])
        _ = reduce(&r, .renamed(from: "b", to: "b2"))
        XCTAssertEqual(r.opening?.id, before.id)
        XCTAssertEqual(r.key, "a2")
        XCTAssertEqual(r.queue, ["b2", "c"])
        XCTAssertEqual(r.phase, .annotating(o("a2", 1)))

        XCTAssertEqual(reduce(&r, .loaded(before)), [], "an answer carrying the old key is still this opening's")
        XCTAssertEqual(reduce(&r, .takesPresses(before)), [.handOverPresses(o("a2", 1))])
        XCTAssertEqual(reduce(&r, .arrived(before)), [.landed(o("a2", 1)), .liftFlight(o("a2", 1))])

        _ = reduce(&r, .finish)
        XCTAssertEqual(reduce(&r, .parked(before)), [.returnCard(o("a2", 1), copied: true), .next("b2", place: 2, of: 3), .prepare(o("b2", 2))])
        XCTAssertEqual(r.opening?.key, "b2")
    }

    func testARenameDuringAParkReKeysTheOpeningThatFollows() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b"])); _ = shown(&r)
        _ = reduce(&r, .annotate(["c"]))
        _ = reduce(&r, .renamed(from: "c", to: "c2"))
        _ = reduce(&r, .renamed(from: "a", to: "a2"))
        XCTAssertEqual(r.phase, .parking(o("a2", 1), then: .annotate(o("c2", 2))))
        XCTAssertEqual(parked(&r), [.returnCard(o("a2", 1), copied: false), .prepare(o("c2", 2))])
        XCTAssertEqual(r.key, "c2")
    }

    // MARK: Rules

    func testAListOpensItsFilesInTurnAndTheLastDoneEndsTheRun() {
        var r = R()
        XCTAssertEqual(reduce(&r, .annotate(["a", "b", "c"])), [.prepare(o("a", 1))])
        XCTAssertEqual(r.queue, ["b", "c"])
        _ = shown(&r); _ = reduce(&r, .finish)
        XCTAssertEqual(parked(&r), [.returnCard(o("a", 1), copied: true), .next("b", place: 2, of: 3), .prepare(o("b", 2))],
                       "the finished card goes home and the next file flies out in one batch, as a swap's do")
        _ = shown(&r); _ = reduce(&r, .finish)
        XCTAssertEqual(parked(&r), [.returnCard(o("b", 2), copied: true), .next("c", place: 3, of: 3), .prepare(o("c", 3))])
        _ = shown(&r); _ = reduce(&r, .finish)
        XCTAssertEqual(parked(&r), [.returnCard(o("c", 3), copied: true), .endRun(restoreFocus: true)])
        XCTAssertFalse(r.isActive)
        XCTAssertEqual(r.queue, [])
    }

    func testEscEndsTheRun() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b"])); _ = shown(&r)
        XCTAssertEqual(reduce(&r, .cancel), [.park(o("a", 1))])
        XCTAssertEqual(r.queue, [], "the rest of the list is dropped at once")
        XCTAssertEqual(parked(&r), [.returnCard(o("a", 1), copied: false), .endRun(restoreFocus: true)])
    }

    func testSendGoesOnToTheNextFile() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b"])); _ = shown(&r)
        XCTAssertEqual(reduce(&r, .sent), [.park(o("a", 1))])
        XCTAssertEqual(parked(&r), [.returnCard(o("a", 1), copied: false), .next("b", place: 2, of: 2), .prepare(o("b", 2))])

        var early = R()
        _ = reduce(&early, .annotate(["a", "b"]))
        XCTAssertEqual(reduce(&early, .sent),
                       [.abandon(o("a", 1)), .returnCard(o("a", 1), copied: false), .next("b", place: 2, of: 2), .prepare(o("b", 2))],
                       "a Send before the flight lands goes on too")
    }

    func testADismissalEndsTheRunAndOnlyAHandReturnsTheFocus() {
        var quick = R()
        _ = reduce(&quick, .annotate(["a", "b"])); _ = shown(&quick)
        XCTAssertEqual(reduce(&quick, .dismiss(byHand: true)), [.park(o("a", 1))])
        XCTAssertEqual(parked(&quick), [.hideAnnotator, .endRun(restoreFocus: true)])

        var hotkey = R()
        _ = reduce(&hotkey, .annotate(["a", "b"])); _ = shown(&hotkey)
        _ = reduce(&hotkey, .dismiss(byHand: false))
        XCTAssertEqual(parked(&hotkey), [.hideAnnotator, .endRun(restoreFocus: false)])
    }

    func testADismissalWhoseParkAnswersInTheSameTurnOpensNothing() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b"])); _ = shown(&r)
        let hold = EventHold<R.Event>()
        var effects: [R.Effect] = []
        hold.send(.dismiss(byHand: false)) { event in
            let batch = reduce(&r, event)
            effects += batch
            if batch.contains(.park(o("a", 1))) { hold.send(.parked(o("a", 1))) { _ in } }
        }
        XCTAssertEqual(effects, [.park(o("a", 1)), .hideAnnotator, .endRun(restoreFocus: false)])
    }

    func testAListRequestedDuringADismissalOpensNothing() {
        var r = R()
        _ = reduce(&r, .annotate(["a"])); _ = shown(&r)
        _ = reduce(&r, .dismiss(byHand: false))
        XCTAssertEqual(reduce(&r, .annotate(["b", "c"])), [])
        XCTAssertEqual(reduce(&r, .parked(o("a", 1))), [.hideAnnotator, .endRun(restoreFocus: false)])
        XCTAssertEqual(r.queue, [])
    }

    func testAQueuedFileThatDoesNotOpenIsPassedOver() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b", "c"])); _ = shown(&r); _ = reduce(&r, .finish)
        let effects = parked(&r, unreadable: ["b"])
        XCTAssertEqual(effects.first, .returnCard(o("a", 1), copied: true))
        XCTAssertEqual(Array(effects.dropFirst()), [.next("c", place: 2, of: 3), .prepare(r.opening!)])
        XCTAssertEqual(r.opening?.key, "c")
        XCTAssertEqual(r.phase, .flyingOut(r.opening!))

        var none = R()
        _ = reduce(&none, .annotate(["a", "b", "c"])); _ = shown(&none); _ = reduce(&none, .finish)
        XCTAssertEqual(parked(&none, unreadable: ["b", "c"]), [.returnCard(o("a", 1), copied: true), .endRun(restoreFocus: true)],
                       "with no file left to open, the run ends rather than staying open with nothing in it")
        XCTAssertFalse(none.isActive)
    }

    func testAFileGoneFromTheQueueSkipsNoNumber() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b", "c"])); _ = shown(&r)
        XCTAssertEqual(reduce(&r, .remove(["b"])), [])
        _ = reduce(&r, .finish)
        XCTAssertEqual(parked(&r), [.returnCard(o("a", 1), copied: true), .next("c", place: 2, of: 3), .prepare(o("c", 2))])
    }

    func testRemovingTheOpenFileEndsTheRun() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b"])); _ = shown(&r)
        XCTAssertEqual(reduce(&r, .remove(["a"])), [.park(o("a", 1))])
        XCTAssertEqual(r.queue, [])
        XCTAssertEqual(parked(&r), [.hideAnnotator, .endRun(restoreFocus: false)])
    }

    func testASelectionQueuesAndUnqueuesFilesButNeverTheOpenOne() {
        var idle = R()
        XCTAssertEqual(reduce(&idle, .selectionChanged(added: ["a"], removed: [])), [], "nothing is open to queue behind")

        var r = R()
        _ = reduce(&r, .annotate(["a"])); _ = shown(&r)
        XCTAssertEqual(reduce(&r, .selectionChanged(added: ["a", "b", "c"], removed: [])),
                       [.queued("b", place: 2, of: 2), .queued("c", place: 3, of: 3)])
        XCTAssertEqual(reduce(&r, .selectionChanged(added: [], removed: ["b"])), [])
        XCTAssertEqual(r.queue, ["c"])
        _ = reduce(&r, .finish)
        XCTAssertEqual(parked(&r), [.returnCard(o("a", 1), copied: true), .next("c", place: 2, of: 2), .prepare(o("c", 2))])
    }

    func testRequestingTheOpenFileAgainKeepsItsOpening() {
        var r = R()
        _ = reduce(&r, .annotate(["a"]))
        XCTAssertEqual(reduce(&r, .annotate(["a"])), [], "while it flies out")
        XCTAssertEqual(r.opening, o("a", 1))
        _ = shown(&r)
        XCTAssertEqual(reduce(&r, .annotate(["a"])), [], "while it is open")
        XCTAssertEqual(r.phase, .annotating(o("a", 1)))
    }

    func testAFailedCopyTakesTheMarkOffTheCardOnItsWayHome() {
        var r = R()
        _ = reduce(&r, .annotate(["a"])); _ = shown(&r); _ = reduce(&r, .finish)
        XCTAssertEqual(reduce(&r, .copyFailed(o("a", 1))), [])
        XCTAssertEqual(parked(&r), [.returnCard(o("a", 1), copied: false), .endRun(restoreFocus: true)])

        _ = reduce(&r, .copyFailed(o("a", 1)))
        _ = reduce(&r, .annotate(["a"])); _ = shown(&r); _ = reduce(&r, .finish)
        XCTAssertEqual(parked(&r), [.returnCard(o("a", 2), copied: true), .endRun(restoreFocus: true)],
                       "a failure reported after the card came home says nothing about its next copy")

        _ = reduce(&r, .annotate(["a"])); _ = shown(&r); _ = reduce(&r, .finish)
        XCTAssertEqual(reduce(&r, .copyFailed(o("a", 2))), [])
        XCTAssertEqual(parked(&r), [.returnCard(o("a", 3), copied: true), .endRun(restoreFocus: true)],
                       "a late failure from the same file's last Done says nothing about this one")
    }

    func testAnAnswerForAnOpeningThatHasGoneChangesNothing() {
        var r = R()
        _ = reduce(&r, .annotate(["a"]))
        XCTAssertEqual(reduce(&r, .annotate(["b"])), [.abandon(o("a", 1)), .returnCard(o("a", 1), copied: false), .prepare(o("b", 2))])
        for late in [R.Event.shown(o("a", 1)), .parked(o("a", 1)), .loaded(o("a", 1)), .takesPresses(o("a", 1)), .arrived(o("a", 1))] {
            XCTAssertEqual(reduce(&r, late), [], "\(late)")
        }
        XCTAssertEqual(r.phase, .flyingOut(o("b", 2)))
        XCTAssertEqual(reduce(&r, .shown(o("b", 2))), [.show])
    }

    func testTheSameFileOpenedAgainTakesNoAnswerFromTheFirstOpening() {
        var r = R()
        _ = reduce(&r, .annotate(["a"])); _ = shown(&r); _ = reduce(&r, .cancel); _ = parked(&r)
        XCTAssertEqual(reduce(&r, .annotate(["a"])), [.prepare(o("a", 2))])
        XCTAssertEqual(reduce(&r, .loaded(o("a", 1))), [])
        XCTAssertEqual(reduce(&r, .arrived(o("a", 1))), [])
        XCTAssertEqual(reduce(&r, .takesPresses(o("a", 1))), [])
        XCTAssertFalse(r.takesPresses)
        XCTAssertEqual(reduce(&r, .shown(o("a", 1))), [])
        XCTAssertEqual(r.phase, .flyingOut(o("a", 2)))
    }

    func testTheFlightLiftsOnceTheEditorHasItsImageTakesPressesAndTheFlightArrived() {
        let a = o("a", 1)
        var r = R()
        _ = reduce(&r, .annotate(["a"]))
        XCTAssertEqual(reduce(&r, .loaded(a)), [])
        XCTAssertEqual(shown(&r), [.show])
        XCTAssertEqual(reduce(&r, .takesPresses(a)), [.handOverPresses(a)])
        XCTAssertTrue(r.takesPresses)
        XCTAssertEqual(reduce(&r, .arrived(a)), [.landed(a), .liftFlight(a)])

        var late = R()
        _ = reduce(&late, .annotate(["a"])); _ = shown(&late)
        _ = reduce(&late, .takesPresses(a)); _ = reduce(&late, .arrived(a))
        XCTAssertEqual(reduce(&late, .loaded(a)), [.liftFlight(a)], "an editor still waiting for its image is never seen")
    }

    func testAFlightThatArrivesDuringThePark() {
        let a = o("a", 1)
        var r = R()
        _ = reduce(&r, .annotate(["a"])); _ = reduce(&r, .loaded(a)); _ = shown(&r); _ = reduce(&r, .takesPresses(a))
        _ = reduce(&r, .finish)
        XCTAssertEqual(reduce(&r, .arrived(a)), [.landed(a), .liftFlight(a)],
                       "Done between the window coming up and the arrival leaves the window up through the park, owed its shadow")
        XCTAssertEqual(parked(&r), [.returnCard(a, copied: true), .endRun(restoreFocus: true)])
        XCTAssertEqual(reduce(&r, .arrived(a)), [], "nothing is open once the card is home")
    }

    // MARK: Random sequences

    /// Plays random events against the run, with an environment that answers `park` with `parked`
    /// and `prepare` with `shown`, `loaded` and `arrived`, and `show` with `takesPresses`, sometimes
    /// in the same turn through `EventHold`, and one file, "x", that never opens. Late answers for
    /// openings that have gone are part of the mix. Checks the transition's invariants and the run's own.
    func testRandomSequencesKeepTheInvariants() {
        let keys: [ScreenshotKey] = ["a", "b", "c", "d"]
        var sameTurn = 0, handovers = 0, passedOver = 0, lifts = 0, staleAnswers = 0
        for seed in 0..<1000 {
            var rng = SeededGenerator(seed: UInt64(seed))
            var r = R()
            let hold = EventHold<R.Event>()
            var pending: [(due: Int, event: R.Event)] = []
            var parksInFlight = 0
            var prepared: Opening?
            var seen: [Opening] = []
            var lifted: Set<Opening> = []
            var running = false      // a prepare has run since the last endRun
            var dismissing = false   // a dismissal reached an open run, which is now ending
            var uncopied: Opening?   // a copy failed while this card was parking after Done
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
                var answersPark = false
                if case .parked(let o) = event, case .parking(o, _) = r.phase { answersPark = true }
                var stale = false
                switch event {
                case .shown(let o), .parked(let o), .loaded(let o), .takesPresses(let o), .arrived(let o): stale = o != r.opening
                default: break
                }
                let effects = r.reduce(event) { key in
                    if key == "x" { passedOver += 1; return false }
                    return true
                }
                trace.append("\(event) -> \(effects) [\(r)]")
                if answersPark { parksInFlight -= 1 }
                if stale { staleAnswers += 1; XCTAssertEqual(effects, [], fail("an answer for another opening changes nothing")) }
                for effect in effects {
                    switch effect {
                    case .park(let k):
                        parksInFlight += 1
                        XCTAssertEqual(parksInFlight, 1, fail("at most one park in flight"))
                        XCTAssertEqual(k, prepared, fail("park is for the opening that was prepared"))
                        answer(.parked(k))
                    case .prepare(let k):
                        XCTAssertEqual(parksInFlight, 0, fail("no prepare while a park is in flight"))
                        XCTAssertFalse(dismissing, fail("nothing opens while a dismissal ends the run"))
                        XCTAssertNotEqual(k.key, "x", fail("a file that does not open is never prepared"))
                        XCTAssertFalse(seen.contains(k), fail("every opening is new"))
                        seen.append(k)
                        prepared = k
                        running = true
                        answer(.shown(k)); answer(.loaded(k)); answer(.arrived(k))
                    case .abandon(let k):
                        XCTAssertEqual(k, prepared, fail("abandon is for the opening that was prepared"))
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
                    case .show:
                        if let prepared { answer(.takesPresses(prepared)) }
                    case .landed(let k), .handOverPresses(let k):
                        XCTAssertEqual(k, prepared, fail("the handover is for the opening in the editor"))
                    case .liftFlight(let k):
                        XCTAssertEqual(k, prepared, fail("the lift is for the opening in the editor"))
                        XCTAssertFalse(lifted.contains(k), fail("a flight lifts once"))
                        lifted.insert(k)
                        lifts += 1
                    case .join:
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
                func some() -> [ScreenshotKey] { (keys + ["x"]).filter { _ in Int.random(in: 0..<3, using: &rng) == 0 } }
                switch Int.random(in: 0..<13, using: &rng) {
                case 0...2:
                    // A person's request starts with a file that reads, as the controller checks;
                    // the rest of the list may not.
                    events.append(.annotate([keys.randomElement(using: &rng)!] + some()))
                case 3: events.append(.cancel)
                case 4: events.append(.sent)
                case 5: events.append(.finish)
                case 6: events.append(.dismiss(byHand: Bool.random(using: &rng)))
                case 7: events.append(.remove(some()))
                case 8: events.append(.newShot(ScreenshotKey(asGiven: "n\(step)")))
                case 9: events.append(.selectionChanged(added: some().filter { $0 != "x" }, removed: some()))
                case 10:
                    if let opening = seen.randomElement(using: &rng) { events.append(.copyFailed(opening)) }
                case 11:
                    if let gone = seen.filter({ $0 != r.opening }).randomElement(using: &rng) {
                        let late: [R.Event] = [.shown(gone), .parked(gone), .loaded(gone), .takesPresses(gone), .arrived(gone)]
                        events.append(late.randomElement(using: &rng)!)
                    }
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
        XCTAssertGreaterThan(lifts, 500, "flights lift")
        XCTAssertGreaterThan(staleAnswers, 500, "late answers for gone openings are part of the mix")
    }
}
