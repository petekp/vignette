import XCTest

final class CornerPresentationTests: XCTestCase {
    private typealias P = CornerPresentation

    private func after(_ events: P.Event...) -> P {
        var p = P()
        for event in events { _ = p.reduce(event) }
        return p
    }

    private let closes: [P.Effect] = [.releaseKeys]
    private let card = UUID()

    func testLoneThumbnailsNeverTakeTheKeys() {
        var p = P()
        XCTAssertEqual(p.reduce(.cardsShown), [.releaseKeys])
        XCTAssertEqual(p.mode, .thumbnails)
        XCTAssertFalse(p.isKeyed)
        XCTAssertTrue(p.leavesOnItsOwn)
    }

    func testTheShortcutTakesTheKeysBeforeItListsThenOpensTheRecentStack() {
        var p = P()
        XCTAssertEqual(p.reduce(.shortcut(.shortcut)), [.holdKeys, .listRecent])
        XCTAssertEqual(p.reduce(.listed(found: true)),
                       [.takeKeys(.current)])
        XCTAssertEqual(p.mode, .stack(recent: true))
        XCTAssertTrue(p.isKeyed)
        XCTAssertFalse(p.leavesOnItsOwn)
    }

    func testTheShortcutWithNothingToShowLetsTheKeysGo() {
        var p = after(.shortcut(.url))
        XCTAssertEqual(p.reduce(.listed(found: false)), [.releaseKeys])
        XCTAssertEqual(p.mode, .hidden)
    }

    func testTheShortcutClosesTheRecentStack() {
        var p = after(.shortcut(.shortcut), .listed(found: true))
        XCTAssertEqual(p.reduce(.shortcut(.shortcut)), closes + [.slideOut(.shortcut)])
        XCTAssertEqual(p.mode, .hidden)
    }

    func testTheShortcutSendsTheCornersEditorHomeAndOpensTheStackWithTheKeys() {
        var p = after(.cardsShown, .editorOpened)
        XCTAssertEqual(p.reduce(.shortcut(.shortcut)),
                       [.holdKeys, .closeEditor, .listRecent])
        XCTAssertFalse(p.leavesOnItsOwn, "the card coming home stays for the stack")
        XCTAssertEqual(p.reduce(.editorClosed(.shortcut)), [], "the focus stays for the stack")
        XCTAssertEqual(p.reduce(.listed(found: true)),
                       [.takeKeys(.current)])
        XCTAssertEqual(p.mode, .stack(recent: true))
    }

    func testSelectingInTheCornerMakesItAKeyedStackOfItsOwnCards() {
        var p = after(.cardsShown)
        XCTAssertEqual(p.reduce(.selected), [.takeKeys(.current)])
        XCTAssertEqual(p.mode, .stack(recent: false))
        XCTAssertTrue(p.isKeyed)
    }

    func testTheShortcutBringsTheOlderCardsIntoAStackMadeFromTheCornerThenClosesIt() {
        var p = after(.cardsShown, .selected)
        XCTAssertEqual(p.reduce(.shortcut(.shortcut)), [.holdKeys, .listRecent])
        XCTAssertEqual(p.reduce(.listed(found: true)), [.takeKeys(.current)])
        XCTAssertEqual(p.mode, .stack(recent: true))
        XCTAssertEqual(p.reduce(.shortcut(.shortcut)), closes + [.slideOut(.shortcut)])
    }

    func testTheShortcutClosesAStackMadeFromTheCornerWhileItsEditorIsOpen() {
        var p = after(.cardsShown, .selected, .editorOpened)
        XCTAssertEqual(p.reduce(.shortcut(.shortcut)), closes + [.slideOut(.shortcut)])
    }

    func testEscFromTheCornersEditorMakesTheCornerAKeyedStackOfItsOwnCards() {
        var p = after(.cardsShown)
        XCTAssertEqual(p.reduce(.editorOpened), [.releaseKeys])
        XCTAssertEqual(p.reduce(.editorClosed(.back)), [.restoreFocus(reason: "annotator closed")])
        XCTAssertEqual(p.reduce(.cardLanded(card, others: true)),
                       [.takeKeys(.card(card))])
        XCTAssertEqual(p.mode, .stack(recent: false))
        XCTAssertTrue(p.isKeyed)
        XCTAssertEqual(p.reduce(.dismiss(.esc)), closes + [.slideOut(.esc)])
    }

    func testEscFromTheEditorOfACardAloneInTheCornerLeavesItLoneThumbnails() {
        var p = after(.cardsShown, .editorOpened, .editorClosed(.back))
        XCTAssertEqual(p.reduce(.cardLanded(card, others: false)), [])
        XCTAssertEqual(p.mode, .thumbnails)
    }

    func testAClickOutsideTheCornersEditorLeavesTheKeysWhereTheClickWent() {
        var p = after(.cardsShown, .editorOpened)
        XCTAssertEqual(p.reduce(.editorClosed(.clickedAway)), [.restoreFocus(reason: "annotator closed")])
        XCTAssertEqual(p.reduce(.cardLanded(card, others: true)), [])
        XCTAssertEqual(p.mode, .thumbnails)
    }

    func testDoneAndSendFromTheCornerHandTheKeysBackToTheFrontApp() {
        for ending in [RunEnding.finished, .sent] {
            var p = after(.cardsShown, .editorOpened)
            XCTAssertEqual(p.reduce(.editorClosed(ending)), [.restoreFocus(reason: "annotator closed")])
            XCTAssertEqual(p.reduce(.cardLanded(card, others: true)), [])
            XCTAssertEqual(p.mode, .thumbnails)
        }
    }

    func testTheStackTakesTheKeysBackWhenTheCardLandsFromTheEditor() {
        var p = after(.shortcut(.shortcut), .listed(found: true))
        XCTAssertEqual(p.reduce(.editorOpened), [.releaseKeys])
        XCTAssertFalse(p.isKeyed)
        XCTAssertEqual(p.reduce(.editorClosed(.back)), [.restoreFocus(reason: "annotator closed")])
        XCTAssertEqual(p.reduce(.cardLanded(card, others: true)), [.takeKeys(.card(card))])
    }

    func testACardLandingWhileTheNextFileIsOpenLeavesTheKeysWithTheEditor() {
        var p = after(.shortcut(.shortcut), .listed(found: true), .editorOpened)
        XCTAssertEqual(p.reduce(.cardLanded(card, others: true)), [])
    }

    func testTheFocusGoesBackOnceTheColumnHasSlidOut() {
        var p = after(.cardsShown)
        XCTAssertEqual(p.reduce(.dismiss(.timeout)), closes + [.slideOut(.timeout)])
        XCTAssertEqual(p.reduce(.slidOut), [.restoreFocus(reason: "stack dismissed")])
        _ = p.reduce(.dismiss(.timeout))
        _ = p.reduce(.cardsShown)
        XCTAssertEqual(p.reduce(.slidOut), [], "a column that came back before the slide-out ended keeps the focus")
    }

    func testAnEditorClosedWithoutAHandLeavesTheFocusAlone() {
        var p = after(.cardsShown, .editorOpened)
        XCTAssertEqual(p.reduce(.editorClosed(nil)), [])
    }

    func testRandomSequencesKeepTheKeysWithTheStack() {
        for seed in 0..<500 {
            var rng = SeededGenerator(seed: UInt64(seed))
            var p = P()
            var accepts = false
            var listing = false, slidingOut = false
            var closing = false
            var trace: [String] = []
            for _ in 0..<60 {
                var choices: [P.Event] = [.cardLanded(card, others: Bool.random(using: &rng))]
                if p.isStack { choices.append(.dismiss(.clickOutside)) }
                if p.isKeyed { choices.append(.dismiss(.esc)) }
                if listing {
                    choices = [.listed(found: Bool.random(using: &rng))] + (closing ? [.editorClosed(.shortcut)] : [])
                } else if closing {
                    choices = [.editorClosed(.shortcut)]
                } else {
                    choices.append(.shortcut(.shortcut))
                    if p.mode == .hidden { choices.append(.cardsShown) }
                    if p.mode == .thumbnails && !p.editorOpen { choices.append(.selected) }
                    if p.mode != .hidden { choices += [.dismiss(.timeout), .dismiss(.removed), .dismiss(.url)] }
                    choices.append(p.editorOpen ? .editorClosed([nil, .back, .clickedAway, .finished, .sent].randomElement(using: &rng)!) : .editorOpened)
                    if slidingOut { choices.append(.slidOut) }
                }
                let event = choices.randomElement(using: &rng)!
                let effects = p.reduce(event)
                trace.append("\(event) -> \(p.mode) \(effects)")
                let context = "seed \(seed)\n" + trace.joined(separator: "\n")
                if case .shortcut = event { listing = effects.contains(.listRecent) }
                if effects.contains(.closeEditor) { closing = true }
                if case .editorClosed = event { closing = false }
                if case .listed = event { listing = false }
                if case .slidOut = event { slidingOut = false }
                if effects.contains(where: { if case .slideOut = $0 { return true }; return false }) { slidingOut = true }
                for effect in effects {
                    switch effect {
                    case .holdKeys, .takeKeys: accepts = true
                    case .releaseKeys: accepts = false
                    default: break
                    }
                }
                if effects.contains(where: { if case .takeKeys = $0 { return true }; return false }) {
                    XCTAssertFalse(p.editorOpen, "the stack takes the keys only once the editor has closed\n\(context)")
                }
                if accepts && !listing && !closing {
                    XCTAssertTrue(p.isKeyed, "the panel takes keys only as the keyed stack\n\(context)")
                }
                let unasked: Bool
                switch event {
                case .cardsShown, .editorClosed(nil), .slidOut, .dismiss: unasked = true
                default: unasked = false
                }
                if unasked {
                    XCTAssertFalse(effects.contains { if case .takeKeys = $0 { return true }; if case .holdKeys = $0 { return true }; return false },
                                   "only a hand gives the corner the keys\n\(context)")
                }
                let restores = effects.contains { if case .restoreFocus = $0 { return true }; return false }
                if restores {
                    let byHandOrSlidOut: Bool
                    switch event {
                    case .slidOut: byHandOrSlidOut = true
                    case .editorClosed(let ending): byHandOrSlidOut = ending != nil
                    default: byHandOrSlidOut = false
                    }
                    XCTAssertTrue(byHandOrSlidOut, "the focus goes back only after a hand closed the editor or the column left\n\(context)")
                }
                if p.mode == .hidden && !listing { XCTAssertFalse(accepts, "nothing shown holds no keys\n\(context)") }
            }
        }
    }
}
