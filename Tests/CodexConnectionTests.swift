import XCTest

final class CodexConnectionTests: XCTestCase {
    private func temporaryFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A thread is named as the Codex app names it: the app's rule, read from its bundle and checked
    /// against its own titles for 144 threads on 2026-09-25. A first message is plain text with its lines joined, and an IDE's is its request.
    func testAThreadIsNamedAsTheCodexAppNamesIt() {
        func name(_ name: String?, _ preview: String) -> String {
            CodexConnection.name(of: AppServer.Thread(id: "01a0ab02-0000", name: name, cwd: "/x", preview: preview))
        }
        XCTAssertEqual(name("Implement Plan: <task>Add a toolbar</task>", ""), "Implement Plan: Add a toolbar",
                       "a tag is taken out of a name")
        XCTAssertEqual(name(nil, "Review [notes.md](docs/notes.md).\n\n---\n\n### Then\n\n- fix **the** `outline`"),
                       "Review notes.md. Then fix the outline")
        XCTAssertEqual(name(nil, "# Context from my IDE setup:\n\n## Active file: a.swift\n\n## My request for Codex:\nMake it faster"),
                       "Make it faster")
        XCTAssertEqual(name(nil, "<environment_context>\n  <cwd>/Users/p/x</cwd>\n</environment_context>"),
                       "<environment_context> /Users/p/x </environment_context>",
                       "a tag's name has no underscore, so this one is text")
        let long = String(repeating: "word ", count: 30)
        XCTAssertEqual(name(nil, long), String(String(repeating: "word ", count: 16).dropLast()) + "…",
                       "cut to 79 characters and an ellipsis, without the space before it")
        XCTAssertEqual(name("", " \n "), "Codex 01a0ab02")
    }

    /// The thread the Codex app shows joins the threads used last when it is older than them, and
    /// only when the store has it.
    func testTheShownThreadJoinsTheListingWhateverItsAge() {
        let listing = #"{"id":2,"result":{"data":[{"id":"a","name":"Recent","cwd":"/x","recencyAt":300}]}}"#
        let read = #"{"id":3,"result":{"thread":{"id":"old","name":"Investigate appointments","cwd":"/y","recencyAt":1}}}"#
        var connection = CodexConnection()
        connection.binary = { "/bin/codex" }
        connection.converse = { _, _, _ in [listing, read] }
        XCTAssertEqual(connection.destinations(including: "old").map(\.id), ["a", "old"])
        XCTAssertEqual(connection.destinations().map(\.id), ["a"], "without an id, no read is used")
        let refused = #"{"id":3,"error":{"code":-32600,"message":"thread not loaded: old"}}"#
        connection.converse = { _, _, _ in [listing, refused] }
        XCTAssertEqual(connection.destinations(including: "old").map(\.id), ["a"])
        connection.converse = { _, _, _ in [listing, #"{"id":3,"result":{"thread":{"id":"a","cwd":"/x"}}}"#] }
        XCTAssertEqual(connection.destinations(including: "a").map(\.id), ["a"], "a listed thread is listed once")
    }

    func testTheQueueCallIsOneArgvElementPerPart() {
        let thread = "01a0c176-bfab-7662-9ffb-a30cc3490835"
        XCTAssertEqual(CodexConnection.arguments(thread: thread, message: "look at \"a b.png\""),
                       ["queue", "--thread", thread, "--message", "look at \"a b.png\""])
    }

    func testAThreadTheServerDoesNotHaveIsTheDestinationHavingChanged() {
        // What codex queue 0.159.2 prints for a thread id no thread has (2026-10-01).
        let deleted = "Error: failed to queue session message: thread/queue/add failed: failed to read thread: invalid thread-store request: no rollout found for thread id 01a0fa10-0000-7000-8000-00000000dead (code -32603)"
        guard case .destinationChanged(_, let reason) = CodexConnection.failure(output: deleted, thread: "t") else {
            return XCTFail("a missing thread is not a retryable failure")
        }
        XCTAssertEqual(reason, "Codex can't find this thread. You can send it to another one.")
        guard case .destinationChanged = CodexConnection.failure(output: "failed to connect to ws://127.0.0.1:9", thread: "t") else {
            return XCTFail("an engine that cannot be reached is not a retryable failure")
        }
        guard case .notSubmitted = CodexConnection.failure(output: "Error: invalid message", thread: "t") else {
            return XCTFail("anything else definitely did not arrive")
        }
    }

    /// `codex queue` answers the same whether or not an engine has the thread, so a send to a thread
    /// nobody has open says it waits, and the lock an engine holds on a loaded thread is what tells.
    func testASendToAThreadNoEngineHasLoadedIsQueued() throws {
        let thread = "01a0c176-bfab-7662-9ffb-a30cc3490835"
        var connection = CodexConnection()
        connection.binary = { "/bin/codex" }
        connection.run = { _, _, _ in (0, "Queued message 7 for thread \(thread).", false) }
        let destination = AgentDestination(id: thread, name: "t", address: .codexThread(uuid: thread))
        connection.isLoaded = { _ in false }
        guard case .queued(_, let reason) = connection.submit("look", to: destination) else {
            return XCTFail("a thread no engine has loaded only stores the message")
        }
        XCTAssertEqual(reason, "Codex reads it when you open this thread.")
        connection.isLoaded = { _ in true }
        guard case .accepted = connection.submit("look", to: destination) else { return XCTFail("a loaded thread takes it") }

        let home = temporaryFolder()
        XCTAssertFalse(CodexConnection.isLoaded(thread, codexHome: home))
        let locks = home.appendingPathComponent("thread-writer-locks")
        try FileManager.default.createDirectory(at: locks, withIntermediateDirectories: true)
        try Data().write(to: locks.appendingPathComponent("\(thread).lock"))
        XCTAssertTrue(CodexConnection.isLoaded(thread, codexHome: home))
    }

    /// Every thread the listing reports becomes a destination, named, with its own project and
    /// the time it was last used, and addressed by its UUID alone.
    func testEveryListedThreadBecomesADestinationWithItsProject() {
        let answer = """
        {"id":2,"result":{"data":[\
        {"id":"01a0c14e-e536-7580-866c-c50622cecd9b","name":"Explore agent screenshot loop","cwd":"/Users/p/Code/vignette","status":{"type":"idle"}},\
        {"id":"01a0c28f-7c24-7a93-82e4-a7906de82cf4","name":"Open drawing","cwd":"/tmp/loop-test","recencyAt":1789970783,"status":{"type":"idle"}},\
        {"id":"01a0ab02-91c0-7000-8000-000000000000","name":null,"cwd":"/tmp/x","preview":"## Look at this\\nthe rest","status":{"type":"idle"}}]}}
        """
        var connection = CodexConnection()
        connection.binary = { "/bin/codex" }
        connection.converse = { _, _, _ in [answer] }

        let found = connection.destinations()
        XCTAssertEqual(found.map(\.name), ["Explore agent screenshot loop", "Open drawing", "Look at this the rest"],
                       "a thread with no name reads as its first message, its lines joined")
        XCTAssertEqual(found[1].detail, "loop-test", "the project is the session's own folder")
        XCTAssertEqual(found[1].address, .codexThread(uuid: "01a0c28f-7c24-7a93-82e4-a7906de82cf4"))
        XCTAssertEqual(found[1].lastUsed, Date(timeIntervalSince1970: 1789970783))
    }

    /// Discovery starts an app-server of its own. `thread/list` reads the store on disk, so that
    /// server sees the same sessions the desktop app's does.
    func testDiscoveryAsksAnAppServerItStarts() {
        var argv: [String] = []
        var connection = CodexConnection()
        connection.binary = { "/bin/codex" }
        connection.converse = { _, arguments, _ in argv = arguments; return [] }
        _ = connection.destinations()
        XCTAssertEqual(argv, ["app-server"])
    }

    /// No Codex on the machine is not an error: there is nothing to discover and nothing is spawned.
    func testWithNoCodexThereAreNoDestinationsAndNothingIsSpawned() {
        var asked = false
        var connection = CodexConnection()
        connection.binary = { nil }
        connection.converse = { _, _, _ in asked = true; return [] }

        XCTAssertTrue(connection.destinations().isEmpty)
        XCTAssertFalse(asked, "nothing is spawned when there is no binary to spawn")
    }
}
