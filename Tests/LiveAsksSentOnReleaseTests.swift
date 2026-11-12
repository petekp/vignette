import CoreGraphics
import XCTest

final class LiveAsksSentOnReleaseTests: XCTestCase {
    typealias A = LiveAsks

    private func ink(_ x: CGFloat = 0) -> Mark { Mark(geometry: .ellipse(CGRect(x: x, y: 0, width: 40, height: 30))) }

    private func begin(_ a: inout A, on shown: [Mark], toSession: Bool = false, sentOnRelease: Bool) -> A.Ask.ID {
        guard case .began(let id, _, _, _) = a.begin(among: shown, following: nil, words: "what is this", toSession: toSession,
                                                    sentOnRelease: sentOnRelease)
        else { XCTFail("the ask was refused"); return 0 }
        return id
    }

    func testStoppingAnAskSentOnReleaseTakesItsNewInkAwayAndOpensNoNote() {
        var a = A()
        let asked = ink(), fresh = ink(50)
        _ = a.reduce(.drew(asked.id))
        _ = begin(&a, on: [asked], sentOnRelease: false)
        _ = a.reduce(.drew(fresh.id))
        let id = begin(&a, on: [asked, fresh], sentOnRelease: true)
        XCTAssertEqual(a.ask(id)?.sentOnRelease, true)
        XCTAssertEqual(a.reduce(.cancelled(id, shown: [asked.id, fresh.id])), [.ended(id), .removeAnswer(id, []), .remove([fresh.id])])
        XCTAssertEqual(a.noteInk, [])
        XCTAssertNil(a.ask(id))
        XCTAssertEqual(a.newInk(among: [asked]), [], "ink an earlier ask was about stays asked")
    }

    func testStoppingItWhileTheResponderAnswersInterruptsFirst() {
        var a = A()
        let mark = ink()
        _ = a.reduce(.drew(mark.id))
        let id = begin(&a, on: [mark], sentOnRelease: true)
        XCTAssertEqual(a.reduce(.arrived(.packetCame, for: id)), [.send(id)])
        XCTAssertEqual(a.reduce(.cancelled(id, shown: [mark.id])), [.ended(id), .interrupt, .removeAnswer(id, []), .remove([mark.id])])
    }

    func testANoteToASessionSentOnReleaseIsWithdrawnAndItsInkGoes() {
        var a = A()
        let mark = ink()
        _ = a.reduce(.drew(mark.id))
        let id = begin(&a, on: [mark], toSession: true, sentOnRelease: true)
        XCTAssertEqual(a.reduce(.cancelled(id, shown: [mark.id])), [.ended(id), .removeAnswer(id, []), .remove([mark.id])])
        XCTAssertEqual(a.reduce(.arrived(.sentToSession(ink: [mark.id]), for: id)), [.withdraw])
    }

    func testAFollowUpFromAButtonIsNeverSentOnRelease() {
        var a = A()
        let mark = ink(), reply = Mark(geometry: .text(Mark.Text(origin: .zero, text: "A button.", wrap: nil, size: 14)), agent: true)
        _ = a.reduce(.drew(mark.id))
        let first = begin(&a, on: [mark], sentOnRelease: false)
        _ = a.reduce(.arrived(.packetCame, for: first))
        _ = a.reduce(.arrived(.answerCame, for: first))
        _ = a.reduce(.answered(reply: reply, actions: [], findings: [], shown: [reply.id], for: first))
        guard case .began(let follow, _, _, _) = a.begin(among: [mark, reply], following: A.Following(reply: reply, pick: .reply, words: "and?"),
                                                         sentOnRelease: true)
        else { return XCTFail("the follow-up was refused") }
        XCTAssertEqual(a.ask(follow)?.sentOnRelease, false)
    }
}
