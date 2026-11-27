import XCTest
@testable import Vignette

final class PinFaceTests: XCTestCase {
    private func pin(_ comments: [Pin.Comment], number: Int = 3) -> Pin {
        Pin(id: UUID(), number: number, place: .point(CGPoint(x: 10, y: 10)), comments: comments)
    }

    func testAnAgentsPinTakesItsBrandAndOneWithoutALogoWearsItsFirstLetter() {
        let style = MarkStyle.standard
        let claude = pin([Pin.Comment(text: "Waiting for host", agent: true, agentName: "Claude")])
        XCTAssertEqual(claude.maker, .agent("claude"))
        XCTAssertEqual(style.painting(claude.maker).agentColor, SRGB(hex: "#d97757"))
        XCTAssertEqual(PinFace(pin([Pin.Comment(text: "Hi", agent: true)]).maker), .logo(""))
        let other = pin([Pin.Comment(text: "Hm", agent: true, agentName: "gemini")])
        XCTAssertEqual(PinFace(other.maker), .letter("G"))
        XCTAssertEqual(style.painting(other.maker).agentColor, style.agentColor)
        let person = pin([Pin.Comment(text: "Too narrow")])
        XCTAssertEqual(PinFace(person.maker), .number)
        XCTAssertEqual(style.painting(person.maker), style)
    }

    func testAPersonsPinAnAgentAnsweredWearsThatAgentsDotAndItsCardCountsTheReplies() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let answered = pin([Pin.Comment(text: "Too narrow\nand too tall", at: now.addingTimeInterval(-60)),
                            Pin.Comment(text: "Widened", agent: true, agentName: "codex", at: now)])
        XCTAssertEqual(answered.answeringAgent, .agent("codex"))
        let words = PinHoverCard.Words(answered, now: now)
        XCTAssertEqual(words.name, "You")
        XCTAssertEqual(words.firstLine, "Too narrow")
        XCTAssertNotNil(words.time)
        XCTAssertNil(PinHoverCard.Words(pin([Pin.Comment(text: "Old")]), now: now).time)
        XCTAssertEqual(words.replies, "1 reply from Codex")
        let both = pin(answered.comments + [Pin.Comment(text: "Thanks", at: now)])
        XCTAssertEqual(PinHoverCard.Words(both, now: now).replies, "2 replies")
        XCTAssertNil(pin([Pin.Comment(text: "Mine", agent: true, agentName: "claude")]).answeringAgent)
    }
}
