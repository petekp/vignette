import XCTest

extension AgentConnectionTests {
    func testTheOkLineNamesTheFileTheMonitorWillTake() throws {
        let root = temporaryFolder()
        let folder = try inbox(root, pid: 102, session: session)
        let destination = AgentDestination(id: session, name: "x", address: .claudeSession(session))
        guard case .accepted(let detail, _) = claude(inboxes: root).submit("look here", to: destination) else {
            return XCTFail("a session with a live inbox is submittable")
        }
        let lines = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".line") }
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(detail.hasSuffix("line=\(lines[0])"))
    }

    func testTheMonitorsTakingOfALineIsSeenOnlyWhileItsSessionStillRuns() {
        typealias Handover = ClaudeCodeConnection.Handover
        XCTAssertEqual(Handover.of(lineIsThere: true, inboxIsThere: true, processIsRunning: true, waited: 5), .waiting)
        XCTAssertEqual(Handover.of(lineIsThere: false, inboxIsThere: true, processIsRunning: true, waited: 5), .handed)
        XCTAssertEqual(Handover.of(lineIsThere: false, inboxIsThere: false, processIsRunning: false, waited: 5), .inboxGone,
                       "the monitor removes the whole inbox as it stops, which is no hand-over")
        XCTAssertEqual(Handover.of(lineIsThere: false, inboxIsThere: true, processIsRunning: false, waited: 5), .inboxGone,
                       "an inbox being removed loses its line before its folder")
        XCTAssertEqual(Handover.of(lineIsThere: true, inboxIsThere: true, processIsRunning: true, waited: ClaudeCodeConnection.handoverLimit), .limit)
    }
}
