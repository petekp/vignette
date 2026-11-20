import XCTest

extension AnnotationRunTests {
    // MARK: Random sequences

    /// Plays random events against the run, with an environment that answers `park` with `parked`
    /// and `prepare` with `shown`, `loaded` and `arrived`, and `show` with `takesPresses`, sometimes
    /// in the same turn through `EventHold`, and one file, "x", that never opens. Late answers for
    /// openings that have gone are part of the mix. Checks the transition's invariants and the run's own.
    func testRandomSequencesKeepTheInvariants() {
        let keys: [ScreenshotKey] = ["a", "b", "c", "d"]
        var sameTurn = 0, handovers = 0, passedOver = 0, lifts = 0, staleAnswers = 0, pages = 0
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
                if case .failed(let k) = event, case .parking(k, then: .finish) = r.phase { uncopied = k }
                var answersPark = false
                if case .parked(let o) = event, case .parking(o, _) = r.phase { answersPark = true }
                var pageRefused = false
                if case .page(_, let isRepeat) = event { pageRefused = !r.takesPage(isRepeat: isRepeat) }
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
                if pageRefused { XCTAssertEqual(effects, [], fail("a repeat in flight, or a page with nothing to move on from, changes nothing")) }
                else if case .page = event { pages += 1; XCTAssertEqual(r.queue, [], fail("a page replaces the queue")) }
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
                switch Int.random(in: 0..<14, using: &rng) {
                case 0...2:
                    // A person's request starts with a file that reads, as the controller checks;
                    // the rest of the list may not.
                    events.append(.annotate([keys.randomElement(using: &rng)!] + some()))
                case 3: events.append(.cancel(.back))
                case 4: events.append(.sent)
                case 5: events.append(.finish)
                case 6: events.append(.dismiss(Bool.random(using: &rng) ? .finished : nil))
                case 7: events.append(.remove(some()))
                case 8: events.append(.newShot(ScreenshotKey(asGiven: "n\(step)")))
                case 9: events.append(.selectionChanged(added: some().filter { $0 != "x" }, removed: some()))
                case 10:
                    if let opening = seen.randomElement(using: &rng) { events.append(.failed(opening)) }
                case 11:
                    if let gone = seen.filter({ $0 != r.opening }).randomElement(using: &rng) {
                        let late: [R.Event] = [.shown(gone), .parked(gone), .loaded(gone), .takesPresses(gone), .arrived(gone)]
                        events.append(late.randomElement(using: &rng)!)
                    }
                case 12: events.append(.page(keys.randomElement(using: &rng)!, isRepeat: Bool.random(using: &rng)))
                default: break
                }
                for event in events { hold.send(event) { handle($0, at: step) } }
            }
            // Drain: a dismissal and every answer still owed end the run.
            hold.send(.dismiss(nil)) { handle($0, at: 40) }
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
        XCTAssertGreaterThan(pages, 500, "pages are part of the mix")
    }
}
