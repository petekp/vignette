import AppKit
import XCTest

extension CommandsTests {
    func testAnAgentTitleIsOneLineCutAtAWordToItsLimit() {
        let parsed = Commands.parse(URL(string: "vignette://add?file=/tmp/x.png&title=Checkout%20page&description=After%20the%20fix")!)
        XCTAssertEqual(parsed.title, "Checkout page")
        XCTAssertEqual(parsed.description, "After the fix")

        let formEncoded = Commands.parse(URL(string: "vignette://add?file=/tmp/a+b.png&title=Inbox+layout&description=1%2B1+is+2")!)
        XCTAssertEqual(formEncoded.title, "Inbox layout")
        XCTAssertEqual(formEncoded.description, "1+1 is 2")
        XCTAssertEqual(formEncoded.files.first?.lastPathComponent, "a+b.png")

        let spaced = AgentTitle.validated(title: "  Checkout\npage \t", description: "one\r\ntwo\u{7}three")
        XCTAssertEqual(spaced.value?.title, "Checkout page")
        XCTAssertEqual(spaced.value?.description, "one two three")
        XCTAssertEqual(spaced.cut, [])

        let exact = String(repeating: "x", count: AgentTitle.maxTitle)
        XCTAssertEqual(AgentTitle.validated(title: exact, description: nil).value?.title, exact)

        let words = AgentTitle.maxTitle / 5
        let cut = AgentTitle.validated(title: String(repeating: "word ", count: 2 * words), description: nil)
        XCTAssertEqual(cut.cut, [.title])
        XCTAssertEqual(cut.value?.title, String(repeating: "word ", count: words).trimmingCharacters(in: .whitespaces) + "…")
        XCTAssertEqual(AgentTitle.validated(title: String(repeating: "word ", count: words - 1) + "abcdefghij", description: nil).value?.title,
                       String(repeating: "word ", count: words - 1).trimmingCharacters(in: .whitespaces) + "…")

        let unbroken = AgentTitle.validated(title: nil, description: String(repeating: "x", count: 300))
        XCTAssertEqual(unbroken.cut, [.description])
        XCTAssertEqual(unbroken.value?.description, String(repeating: "x", count: AgentTitle.maxDescription - 1) + "…")
        XCTAssertNil(unbroken.value?.title)

        XCTAssertNil(AgentTitle.validated(title: " \n ", description: "").value)
        XCTAssertNil(AgentTitle.validated(title: nil, description: nil).value)
    }
}
