import CoreGraphics
import XCTest

final class LiveAsksWithoutInkTests: XCTestCase {
    typealias A = LiveAsks

    private let pointer = CGPoint(x: 300, y: 200)

    private func reply(_ text: String) -> Mark {
        Mark(geometry: .text(Mark.Text(origin: .zero, text: text, wrap: nil, size: 14)), agent: true)
    }

    func testWithAPointerTheAskIsAboutTheWindowThereEvenWithInkAskedBefore() {
        var a = A()
        let asked = Mark(geometry: .ellipse(CGRect(x: 0, y: 0, width: 40, height: 30)))
        _ = a.reduce(.drew(asked.id))
        _ = a.begin(among: [asked], following: nil, words: "what is this")
        guard case .began(let id, let about, let point, _) = a.begin(among: [asked], following: nil, words: "and this window?", at: pointer)
        else { return XCTFail("the ask was refused") }
        XCTAssertEqual(about, [])
        XCTAssertEqual(point, pointer)
        XCTAssertEqual(a.ask(id)?.spot, pointer)
        XCTAssertEqual(a.ask(id)?.about, [])
    }

    func testWithNoInkAndNoPointerTheAskIsStillRefused() {
        var a = A()
        guard case .refused(.noInk, _) = a.begin(among: [], following: nil, words: "what is this") else {
            return XCTFail("an ask with no ink and no pointer began")
        }
    }

    func testEscStopsItAndOpensNoNote() {
        var a = A()
        guard case .began(let id, _, _, _) = a.begin(among: [], following: nil, words: "what is this", at: pointer)
        else { return XCTFail("the ask was refused") }
        XCTAssertEqual(a.reduce(.arrived(.packetCame, for: id)), [.send(id)])
        XCTAssertEqual(a.reduce(.cancelled(id, shown: [])), [.ended(id), .interrupt, .removeAnswer(id, [])])
        XCTAssertNil(a.ask(id))
    }

    func testAnAskFollowingItsAnswerIsAboutTheSameWindowEvenWithInkAskedBefore() {
        var a = A()
        let asked = Mark(geometry: .ellipse(CGRect(x: 0, y: 0, width: 40, height: 30)))
        let answer = reply("A window.")
        _ = a.reduce(.drew(asked.id))
        _ = a.begin(among: [asked], following: nil, words: "what is this")
        guard case .began(let first, _, _, _) = a.begin(among: [asked], following: nil, words: "and this window?", at: pointer)
        else { return XCTFail("the ask was refused") }
        _ = a.reduce(.arrived(.packetCame, for: first))
        _ = a.reduce(.arrived(.answerCame, for: first))
        _ = a.reduce(.answered(reply: answer, actions: [], findings: [], shown: [answer.id], for: first))
        guard case .began(let follow, let about, let point, _) = a.begin(
            among: [asked, answer], following: A.Following(reply: answer, pick: .reply, words: "and?"))
        else { return XCTFail("the follow-up was refused") }
        XCTAssertEqual(about, [])
        XCTAssertEqual(point, pointer)
        XCTAssertEqual(a.ask(follow)?.spot, pointer)
    }
}
