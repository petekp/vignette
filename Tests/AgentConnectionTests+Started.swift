import XCTest

extension AgentConnectionTests {
    func testASessionVignetteStartedIsReadFromTheLiveInboxHoldingIt() throws {
        let root = temporaryFolder()
        let row = try XCTUnwrap(StartableSessions.rows(folder: "/Users/p/Code/vignette", last: nil, lastUsed: Date(),
                                                      found: SessionPlaces.Found(place: .none)).last)
        let record = ScreenshotRequests.Record(id: "r", created: Date(), destinationID: session, destinationName: row.name,
                                               address: .claudeSession(session), addressGuard: .preflight, source: "a.png",
                                               sourceKey: "/tmp/a.png", status: .submitted, detail: "", start: row.start)
        let started = row.sent(as: record)
        XCTAssertEqual(started.id, session)
        XCTAssertNil(started.start, "the next send goes to the session that started, not to a new one")
        let connection = claude(inboxes: root)
        XCTAssertNil(connection.turn(of: started))
        try Data("busy\n".utf8).write(to: try inbox(root, pid: 101, session: session).appendingPathComponent("turn"))
        XCTAssertEqual(connection.turn(of: started), .busy)
    }
}
