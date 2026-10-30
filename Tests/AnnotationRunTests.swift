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
        XCTAssertEqual(parked(&r), [.returnCard(o("c", 3), copied: true), .endRun(.finished)])
        XCTAssertFalse(r.isActive)
        XCTAssertEqual(r.queue, [])
    }

    func testEscEndsTheRun() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b"])); _ = shown(&r)
        XCTAssertEqual(reduce(&r, .cancel(.back)), [.park(o("a", 1))])
        XCTAssertEqual(r.queue, [], "the rest of the list is dropped at once")
        XCTAssertEqual(parked(&r), [.returnCard(o("a", 1), copied: false), .endRun(.back)])
    }

    func testSendGoesOnToTheNextFile() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b"])); _ = shown(&r)
        XCTAssertEqual(reduce(&r, .sent), [.park(o("a", 1))])
        XCTAssertEqual(parked(&r), [.returnCard(o("a", 1), copied: false), .next("b", place: 2, of: 2), .prepare(o("b", 2))])
        _ = shown(&r); _ = reduce(&r, .sent)
        XCTAssertEqual(parked(&r), [.returnCard(o("b", 2), copied: false), .endRun(.sent)])

        var early = R()
        _ = reduce(&early, .annotate(["a", "b"]))
        XCTAssertEqual(reduce(&early, .sent),
                       [.abandon(o("a", 1)), .returnCard(o("a", 1), copied: false), .next("b", place: 2, of: 2), .prepare(o("b", 2))],
                       "a Send before the flight lands goes on too")
    }

    func testADismissalEndsTheRunAndSaysWhetherAHandEndedIt() {
        var quick = R()
        _ = reduce(&quick, .annotate(["a", "b"])); _ = shown(&quick)
        XCTAssertEqual(reduce(&quick, .dismiss(.finished)), [.park(o("a", 1))])
        XCTAssertEqual(parked(&quick), [.hideAnnotator, .endRun(.finished)])

        var hotkey = R()
        _ = reduce(&hotkey, .annotate(["a", "b"])); _ = shown(&hotkey)
        _ = reduce(&hotkey, .dismiss(nil))
        XCTAssertEqual(parked(&hotkey), [.hideAnnotator, .endRun(nil)])
    }

    func testADismissalWhoseParkAnswersInTheSameTurnOpensNothing() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b"])); _ = shown(&r)
        let hold = EventHold<R.Event>()
        var effects: [R.Effect] = []
        hold.send(.dismiss(nil)) { event in
            let batch = reduce(&r, event)
            effects += batch
            if batch.contains(.park(o("a", 1))) { hold.send(.parked(o("a", 1))) { _ in } }
        }
        XCTAssertEqual(effects, [.park(o("a", 1)), .hideAnnotator, .endRun(nil)])
    }

    func testAListRequestedDuringADismissalOpensNothing() {
        var r = R()
        _ = reduce(&r, .annotate(["a"])); _ = shown(&r)
        _ = reduce(&r, .dismiss(nil))
        XCTAssertEqual(reduce(&r, .annotate(["b", "c"])), [])
        XCTAssertEqual(reduce(&r, .parked(o("a", 1))), [.hideAnnotator, .endRun(nil)])
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
        XCTAssertEqual(parked(&none, unreadable: ["b", "c"]), [.returnCard(o("a", 1), copied: true), .endRun(.finished)],
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
        XCTAssertEqual(parked(&r), [.hideAnnotator, .endRun(nil)])
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

    func testAPageOpensItsFileAsAClickWouldAndARepeatWaitsForTheImageBeforeIt() {
        var r = R()
        _ = reduce(&r, .annotate(["a", "b", "c"]))
        XCTAssertEqual(reduce(&r, .page("d", isRepeat: true)), [], "a repeat while the first image flies in")
        XCTAssertEqual(reduce(&r, .page("d", isRepeat: false)),
                       [.abandon(o("a", 1)), .returnCard(o("a", 1), copied: false), .prepare(o("d", 2))])
        XCTAssertEqual(r.queue, [])
        XCTAssertEqual(r.opening?.paged, true)
        _ = shown(&r)
        XCTAssertEqual(reduce(&r, .page("e", isRepeat: true)), [], "a repeat while the flight is still over the editor")
        _ = reduce(&r, .loaded(o("d", 2))); _ = reduce(&r, .takesPresses(o("d", 2))); _ = reduce(&r, .arrived(o("d", 2)))
        XCTAssertEqual(reduce(&r, .page("e", isRepeat: true)), [.park(o("d", 2))], "a repeat once the flight has lifted")
        XCTAssertEqual(r.heading, "e")
        XCTAssertEqual(reduce(&r, .page("f", isRepeat: true)), [], "a repeat during the park")
        XCTAssertEqual(parked(&r), [.returnCard(o("d", 2), copied: false), .prepare(o("e", 3))])
        _ = shown(&r)
        _ = reduce(&r, .finish)
        XCTAssertNil(r.heading)
        XCTAssertEqual(reduce(&r, .page("a", isRepeat: false)), [], "nothing to move on from while Done parks")
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
        XCTAssertEqual(parked(&r), [.returnCard(o("a", 1), copied: false), .endRun(.finished)])

        _ = reduce(&r, .copyFailed(o("a", 1)))
        _ = reduce(&r, .annotate(["a"])); _ = shown(&r); _ = reduce(&r, .finish)
        XCTAssertEqual(parked(&r), [.returnCard(o("a", 2), copied: true), .endRun(.finished)],
                       "a failure reported after the card came home says nothing about its next copy")

        _ = reduce(&r, .annotate(["a"])); _ = shown(&r); _ = reduce(&r, .finish)
        XCTAssertEqual(reduce(&r, .copyFailed(o("a", 2))), [])
        XCTAssertEqual(parked(&r), [.returnCard(o("a", 3), copied: true), .endRun(.finished)],
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
        _ = reduce(&r, .annotate(["a"])); _ = shown(&r); _ = reduce(&r, .cancel(.back)); _ = parked(&r)
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
        XCTAssertEqual(parked(&r), [.returnCard(a, copied: true), .endRun(.finished)])
        XCTAssertEqual(reduce(&r, .arrived(a)), [], "nothing is open once the card is home")
    }
}
