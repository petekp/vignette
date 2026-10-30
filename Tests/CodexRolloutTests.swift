import XCTest

final class CodexRolloutTests: XCTestCase {
    private let note = "From Vignette: a note for you. requests/AAAA-1111/image.png"

    private func entry(_ type: String, _ payload: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["timestamp": "2026-10-30T06:36:46.388Z", "type": type, "payload": payload])
    }

    private func started(_ turn: String) -> Data {
        entry("event_msg", ["type": "task_started", "turn_id": turn, "root_turn_id": turn, "started_at": 1793342206])
    }

    private func completed(_ turn: String, as kind: String = "task_complete") -> Data {
        entry("event_msg", ["type": kind, "turn_id": turn, "root_turn_id": turn])
    }

    private func user(_ text: String) -> Data {
        entry("response_item", ["type": "message", "role": "user", "content": [["type": "input_text", "text": text]]])
    }

    private func assistant(_ text: String) -> Data {
        entry("response_item", ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]])
    }

    private func readings(_ turns: inout RolloutTurns, _ steps: [[Data]]) -> [SessionTurn?] {
        steps.map { lines in
            lines.forEach { turns.read($0) }
            return turns.reading()
        }
    }

    func testTheLinesCodex0165WritesForAQueuedLineReadAsWaitingThenBusyThenIdle() {
        var turns = RolloutTurns()
        turns.sent("ROLLOUT-TURN-ONE")
        let lines = [
            #"{"timestamp":"2026-10-30T06:36:46.388Z","ordinal":1,"type":"event_msg","payload":{"type":"task_started","turn_attribution":{"turn_id":"01a18b86-71b2-7501-9f4f-fd85a0022ad7","turn_trigger":null,"parent_turn_id":null,"initiating_agent_path":null,"root_turn_id":"01a18b86-71b2-7501-9f4f-fd85a0022ad7"},"turn_id":"01a18b86-71b2-7501-9f4f-fd85a0022ad7","root_turn_id":"01a18b86-71b2-7501-9f4f-fd85a0022ad7","started_at":1793342206,"model_context_window":258400,"collaboration_mode_kind":"default"}}"#,
            #"{"timestamp":"2026-10-30T06:36:46.397Z","ordinal":6,"type":"response_item","payload":{"type":"message","id":"msg_01a18b86-71bd-7962-9b5d-d7065e3dbcf4","role":"user","content":[{"type":"input_text","text":"ROLLOUT-TURN-ONE"}],"internal_chat_message_metadata_passthrough":{"turn_id":"01a18b86-71b2-7501-9f4f-fd85a0022ad7","create_time":1793342206.397182,"content_item_kinds":["user.text"],"content_item_metadata":[{"provenance":{"type":"user"}}]}},"metadata":{"retained_source":{"id":{"message_id":"msg_01a18b86-71bd-7962-9b5d-d7065e3dbcf4","turn_id":"01a18b86-71b2-7501-9f4f-fd85a0022ad7","role":"user"},"revision":"retained_01a18b86-71bd-7962-9b5d-d729fb96eac6","complete":true},"client_authored":false,"user_input_order":0,"mcp_attribution":{"status":"none"}}}"#,
            #"{"timestamp":"2026-10-30T06:36:46.405Z","ordinal":13,"type":"event_msg","payload":{"type":"task_complete","root_turn_id":"01a18b86-71b2-7501-9f4f-fd85a0022ad7","turn_id":"01a18b86-71b2-7501-9f4f-fd85a0022ad7","last_agent_message":"{\"say\":\"Ready.\",\"marks\":[]}","started_at":1793342206,"completed_at":1793342206,"duration_ms":17,"time_to_first_token_ms":14}}"#,
        ].map { Data($0.utf8) }
        XCTAssertEqual(readings(&turns, [[], [lines[0]], [lines[1]], [lines[2]]]), [.waiting, .waiting, .busy, .idle])
    }

    func testAnotherTurnRunningBeforeTheLineIsTakenStillReadsAsWaiting() {
        var turns = RolloutTurns()
        turns.sent(note)
        XCTAssertEqual(readings(&turns, [[started("a"), user("the person's own words")], [assistant("…")], [completed("a")],
                                         [started("b"), user(note)], [completed("b")]]),
                       [.waiting, .waiting, .waiting, .busy, .idle])
    }

    func testATurnThatStartsAndEndsBetweenTwoReadingsReadsBusyOnce() {
        var turns = RolloutTurns()
        turns.sent(note)
        XCTAssertEqual(readings(&turns, [[], [started("b"), user(note), assistant("done"), completed("b")], [], []]),
                       [.waiting, .busy, .idle, .idle])
    }

    func testTwoLinesQueuedTogetherWaitUntilEachHasHadItsOwnTurn() {
        var turns = RolloutTurns()
        turns.sent(note)
        turns.sent("From Vignette: a second note. requests/BBBB-2222/image.png")
        XCTAssertEqual(readings(&turns, [[started("a"), user(note)], [completed("a")],
                                         [started("b"), user("From Vignette: a second note. requests/BBBB-2222/image.png")], [completed("b")]]),
                       [.waiting, .waiting, .busy, .idle])
    }

    func testAnInterruptedTurnEndsAndAnotherTurnsEndDoesNotEndIt() {
        var turns = RolloutTurns()
        turns.sent(note)
        XCTAssertEqual(readings(&turns, [[completed("before")], [started("b"), user(note)], [completed("other")],
                                         [completed("b", as: "turn_aborted")]]),
                       [.waiting, .busy, .busy, .idle])
    }

    func testTheUserMessageEventOfBuildsBefore0165IsReadToo() {
        var turns = RolloutTurns()
        turns.sent(note)
        XCTAssertEqual(readings(&turns, [[started("b"), entry("event_msg", ["type": "user_message", "message": note])], [completed("b")]]),
                       [.busy, .idle])
    }

    func testALineThatWentNowhereIsTakenBack() {
        var turns = RolloutTurns()
        turns.sent(note)
        turns.unsent(note)
        XCTAssertEqual(turns.reading(), .idle)
    }

    func testARolloutInAShapeThisReaderDoesNotKnowReadsAsNoTurn() {
        var unknownEnvelope = RolloutTurns()
        unknownEnvelope.sent(note)
        unknownEnvelope.read(Data(#"{"kind":"task_started","turn":"b"}"#.utf8))
        unknownEnvelope.read(started("b"))
        XCTAssertNil(unknownEnvelope.reading())
        XCTAssertEqual(unknownEnvelope.unreadable, "a line with no type and payload")

        var renamedEvents = RolloutTurns()
        renamedEvents.sent(note)
        renamedEvents.read(entry("event_msg", ["type": "turn_began", "turn_id": "b"]))
        renamedEvents.read(user(note))
        XCTAssertNil(renamedEvents.reading(), "a sent line outside any turn means the turn events changed")

        var partLine = RolloutTurns()
        partLine.sent(note)
        partLine.read(Data(#"_turn_id":"b"}}"#.utf8))
        XCTAssertEqual(partLine.reading(), .waiting, "the end of a line read from the middle of the file is skipped")
    }

    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_793_342_206)
    }

    private func rolloutFile(_ lines: [Data]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rollouts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("rollout-2026-10-30T00-04-02-thread.jsonl")
        try Data(lines.map { $0 + Data("\n".utf8) }.joined()).write(to: file)
        return file
    }

    private func append(_ bytes: Data, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: bytes)
        try handle.close()
    }

    func testTheRolloutIsReadFromItsEndWhenTheLineWentAndALineIsReadOnceItsEndIsWritten() throws {
        let file = try rolloutFile([started("old"), user(note), completed("old")])
        let tracker = CodexTurns()
        tracker.sending(note, to: "thread", rollout: .at(file.path))
        XCTAssertEqual(tracker.turn(of: "thread") { _ in .unknown }, .waiting, "the same words earlier in the thread are not this line")
        let taken = started("b") + Data("\n".utf8) + user(note)
        try append(taken.prefix(taken.count - 10), to: file)
        XCTAssertEqual(tracker.turn(of: "thread") { _ in .unknown }, .waiting)
        try append(taken.suffix(10) + Data("\n".utf8), to: file)
        XCTAssertEqual(tracker.turn(of: "thread") { _ in .unknown }, .busy)
        try append(completed("b") + Data("\n".utf8), to: file)
        XCTAssertEqual(tracker.turn(of: "thread") { _ in .unknown }, .idle)
        XCTAssertNil(tracker.turn(of: "another thread") { _ in .unknown })
    }

    func testARolloutThatStopsGrowingIsAskedForAgainAndANewFileIsReadFromItsStart() throws {
        let file = try rolloutFile([])
        let clock = Clock()
        let tracker = CodexTurns(now: { clock.now })
        tracker.sending(note, to: "thread", rollout: .at(file.path))
        try append(started("b") + Data("\n".utf8) + user(note) + Data("\n".utf8), to: file)
        var asked = 0
        XCTAssertEqual(tracker.turn(of: "thread") { _ in asked += 1; return .unknown }, .busy)
        clock.now += CodexTurns.staleAfter - 1
        XCTAssertEqual(tracker.turn(of: "thread") { _ in asked += 1; return .unknown }, .busy)
        XCTAssertEqual(asked, 0, "a turn that is thinking writes nothing for a while")

        let next = file.deletingLastPathComponent().appendingPathComponent("rollout-2026-10-30T01-00-00-thread.jsonl")
        try Data((completed("b") + Data("\n".utf8))).write(to: next)
        clock.now += 2
        XCTAssertEqual(tracker.turn(of: "thread") { _ in asked += 1; return .at(next.path) }, .idle)
        XCTAssertEqual(asked, 1)
    }

    func testAWatchedThreadThatMovesToAnotherFileIsReadFromThatFilesStart() throws {
        let file = try rolloutFile([])
        let tracker = CodexTurns()
        tracker.sending(note, to: "thread", rollout: .at(file.path))
        XCTAssertEqual(tracker.turn(of: "thread") { _ in .unknown }, .waiting)
        let moved = file.deletingLastPathComponent().appendingPathComponent("rollout-2026-10-30T01-00-00-thread.jsonl")
        try Data([started("a"), user(note), completed("a")].map { $0 + Data("\n".utf8) }.joined()).write(to: moved)
        let second = "From Vignette: a second note. requests/BBBB-2222/image.png"
        tracker.sending(second, to: "thread", rollout: .at(moved.path))
        try append(Data([started("b"), user(second)].map { $0 + Data("\n".utf8) }.joined()), to: moved)
        XCTAssertEqual(tracker.turn(of: "thread") { _ in .unknown }, .busy, "the first line's turn in the new file is read too")
        try append(completed("b") + Data("\n".utf8), to: moved)
        XCTAssertEqual(tracker.turn(of: "thread") { _ in .unknown }, .idle)
    }

    func testALineSentBeforeTheThreadHasARolloutWaitsAndAReadThatNamesNoFileReadsAsNoTurn() throws {
        let clock = Clock()
        let tracker = CodexTurns(now: { clock.now })
        tracker.sending(note, to: "thread", rollout: .unknown)
        XCTAssertEqual(tracker.turn(of: "thread") { _ in XCTFail("asked again at once"); return .unknown }, .waiting)
        let file = try rolloutFile([started("b"), user(note)])
        clock.now += CodexTurns.staleAfter
        XCTAssertEqual(tracker.turn(of: "thread") { _ in .at(file.path) }, .busy, "a file that appears later is read from its start")

        let unnamed = CodexTurns()
        unnamed.sending(note, to: "thread", rollout: .unnamed)
        XCTAssertNil(unnamed.turn(of: "thread") { _ in .unknown })
    }
}
