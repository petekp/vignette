import AppKit
import XCTest

final class AgentTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    func testARecordedAgentReadsBackAndFollowsTheFile() throws {
        let file = dir.appendingPathComponent("Screenshot.png")
        try Data("png".utf8).write(to: file)
        XCTAssertNil(Agent.of(file), "a capture has no agent")
        Agent.record(agent: "claude", origin: nil, on: file)
        XCTAssertEqual(Agent.of(file), "claude")
        let renamed = dir.appendingPathComponent("Screenshot 2.png")
        try FileManager.default.moveItem(at: file, to: renamed)
        XCTAssertEqual(Agent.of(renamed), "claude", "the name travels with the file, not with its path")
        XCTAssertNil(Agent.of(dir.appendingPathComponent("gone.png")))
    }

    func testAPushThatNamesItsSessionIsAReplyTarget() throws {
        let session = "E011FFF1-C791-4934-9E61-9307D840A5EB"
        let thread = "01a16116-a9f0-71c2-9ec3-fe702ddcb168"
        XCTAssertEqual(Commands.parse(URL(string: "vignette://add?file=/tmp/x.png&agent=claude&session=\(session)")!).session, session)
        XCTAssertEqual(Agent.cleanSession(session), session.lowercased(), "herdr reports ids in lowercase")
        XCTAssertEqual(Agent.cleanSession(thread), thread, "a Codex thread id is a UUID too")
        XCTAssertNil(Agent.cleanSession(""), "an unset variable sends an empty value")
        XCTAssertNil(Agent.cleanSession("../../etc"))
        XCTAssertEqual(Agent.pushOrigin(agent: "claude", session: session), .claudeSession(session.lowercased()))
        XCTAssertEqual(Agent.pushOrigin(agent: "Codex", session: thread), .codexThread(uuid: thread))
        XCTAssertNil(Agent.pushOrigin(agent: "gemini", session: session), "no other client is addressed by a session id")
        XCTAssertNil(Agent.pushOrigin(agent: nil, session: session))

        let file = dir.appendingPathComponent("Checkout.png")
        try Data("png".utf8).write(to: file)
        Agent.record(agent: "claude", origin: nil, on: file)
        XCTAssertNil(Agent.origin(of: file), "a push that did not say which session is not a reply")
        for origin in [AgentAddress.claudeSession(session.lowercased()), .codexThread(uuid: thread)] {
            Agent.record(agent: origin.client.rawValue, origin: origin, on: file)
            XCTAssertEqual(Agent.origin(of: file)?.address, origin)
            XCTAssertEqual(Agent.of(file), origin.client.rawValue)
        }
    }
    func testATitlesInkIsTheColourThatStandsOutMoreFromItsWorstPart() {
        let crossover = (1.05 * 0.05).squareRoot() - 0.05
        XCTAssertEqual(TitleInk.choose(behind: [crossover - 0.001]), .white)
        XCTAssertEqual(TitleInk.choose(behind: [crossover + 0.001]), .black)
        XCTAssertEqual(TitleInk.choose(behind: [0.05, 0.12]), .white)
        XCTAssertEqual(TitleInk.choose(behind: [0.02, 0.6]), .white)
        XCTAssertEqual(TitleInk.choose(behind: [0.12, 0.6]), .black)
        XCTAssertNil(TitleInk.choose(behind: []))
        XCTAssertEqual(TitleInk.luminance(encoded: 1, dim: 0.3), InkContrast.linear(0.7))
    }

    func testATitleShowsOnceItHasLandedAndKnowsItsInkOrOnceTheWaitForItEnds() {
        var inkFirst = TitleReveal()
        XCTAssertNil(inkFirst.reduce(.opened))
        XCTAssertNil(inkFirst.reduce(.inkKnown(at: 1)))
        XCTAssertEqual(inkFirst.reduce(.landed(at: 2)), .show(waited: 0))
        XCTAssertNil(inkFirst.reduce(.inkKnown(at: 3)))

        var landedFirst = TitleReveal()
        _ = landedFirst.reduce(.opened)
        XCTAssertEqual(landedFirst.reduce(.landed(at: 2)), .waitForInk)
        XCTAssertEqual(landedFirst.reduce(.inkKnown(at: 2.25)), .show(waited: 0.25))
        XCTAssertNil(landedFirst.reduce(.waitEnded(at: 2.5)))

        var waitedOut = TitleReveal()
        _ = waitedOut.reduce(.opened)
        _ = waitedOut.reduce(.landed(at: 2))
        XCTAssertEqual(waitedOut.reduce(.waitEnded(at: 2.5)), .showInAppearanceInk(waited: 0.5))
        XCTAssertNil(waitedOut.reduce(.inkKnown(at: 3)))

        var reopened = TitleReveal()
        _ = reopened.reduce(.opened)
        _ = reopened.reduce(.inkKnown(at: 1))
        _ = reopened.reduce(.landed(at: 2))
        XCTAssertNil(reopened.reduce(.opened))
        XCTAssertEqual(reopened.reduce(.landed(at: 4)), .waitForInk)

        var closedDuringTheWait = TitleReveal()
        _ = closedDuringTheWait.reduce(.opened)
        _ = closedDuringTheWait.reduce(.landed(at: 2))
        XCTAssertNil(closedDuringTheWait.reduce(.closed))
        XCTAssertNil(closedDuringTheWait.reduce(.waitEnded(at: 2.5)))
        XCTAssertNil(closedDuringTheWait.reduce(.inkKnown(at: 2.6)))

        var untitled = TitleReveal()
        XCTAssertNil(untitled.reduce(.closed))
        XCTAssertNil(untitled.reduce(.inkKnown(at: 1)))
        XCTAssertNil(untitled.reduce(.landed(at: 2)))
    }

    func testARecordedTitleReadsBackAndFollowsTheFile() throws {
        let file = dir.appendingPathComponent("Checkout.png")
        try Data("png".utf8).write(to: file)
        XCTAssertNil(Agent.title(of: file))
        let description = String(String(repeating: "Écran 日本語 🧑🏽‍💻 ", count: 30).prefix(AgentTitle.maxDescription))
        let title = try XCTUnwrap(AgentTitle.validated(title: "Checkout", description: description).value)
        XCTAssertGreaterThan(description.utf8.count, 4 * Agent.maxLength)
        Agent.record(title: title, on: file)
        let renamed = dir.appendingPathComponent("Checkout 2.png")
        try FileManager.default.moveItem(at: file, to: renamed)
        XCTAssertEqual(Agent.title(of: renamed), title)

        let titleOnly = try XCTUnwrap(AgentTitle.validated(title: "Cart", description: nil).value)
        Agent.record(title: titleOnly, on: renamed)
        XCTAssertEqual(Agent.title(of: renamed), titleOnly)
    }

    func testASendersNameIsOneShortLineAndAPushWithoutOneDropsTheLast() throws {
        XCTAssertEqual(Commands.parse(URL(string: "vignette://add?file=/tmp/x.png&agent=claude&from=sender+name")!).from, "sender name")
        XCTAssertEqual(Agent.cleanSender("  sender\nname ").name, "sender name")
        XCTAssertNil(Agent.cleanSender(" ").name)
        let long = Agent.cleanSender(String(repeating: "word ", count: 20))
        XCTAssertTrue(long.cut)
        XCTAssertLessThanOrEqual(try XCTUnwrap(long.name).count, Agent.maxSenderLength)

        let file = dir.appendingPathComponent("Sent.png")
        try Data("png".utf8).write(to: file)
        Agent.record(agent: "claude", origin: nil, on: file)
        Agent.record(sender: "vignette", on: file)
        XCTAssertEqual(Agent.sender(of: file), "vignette")
        Agent.record(agent: "claude", origin: nil, on: file)
        XCTAssertNil(Agent.sender(of: file), "a later push names its own sender or none")
    }

    func testBadgeLabelNamesTheSessionElseTheAgent() {
        XCTAssertEqual(Agent.label(for: "claude", sender: "vignette"), "From vignette")
        XCTAssertEqual(Agent.label(for: "claude", sender: nil), "From Claude")
        XCTAssertEqual(Agent.label(for: "", sender: nil), "From an agent")
        XCTAssertNotNil(NSImage(systemSymbolName: Agent.fallbackSymbol, accessibilityDescription: nil), "the badge glyph must exist")
    }
}
