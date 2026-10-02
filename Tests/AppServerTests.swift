import XCTest

final class AppServerTests: XCTestCase {
    /// A `thread/list` answer as a running app-server really writes it, cut to the fields the
    /// parser reads (captured 2026-09-21 through `codex app-server proxy --sock`).
    private let answer = #"""
    {"id":2,"result":{"data":[{"id":"01a0c28f-7c24-7a93-82e4-a7906de82cf4","name":"Open drawing","cwd":"/tmp/loop-test","recencyAt":1789970783,"preview":"Vignette request 08e8b73a: open the drawing","status":{"type":"notLoaded"}},{"id":"01a0c14e-e536-7580-866c-c50622cecd9b","name":"Explore agent screenshot loop","cwd":"/Users/p/Code/vignette","status":{"type":"idle"}}],"nextCursor":null}}
    """#

    func testTheThreadsInAnAnswerCarryTheirNameAndProject() {
        let threads = AppServer.threads(in: ["{\"method\":\"remoteControl/status/changed\"}", answer])
        XCTAssertEqual(threads.map(\.id), ["01a0c28f-7c24-7a93-82e4-a7906de82cf4",
                                          "01a0c14e-e536-7580-866c-c50622cecd9b"])
        XCTAssertEqual(threads[0].name, "Open drawing")
        XCTAssertEqual(threads[0].cwd, "/tmp/loop-test")
        XCTAssertEqual(threads[0].recencyAt, Date(timeIntervalSince1970: 1789970783))
        XCTAssertEqual(threads[0].preview, "Vignette request 08e8b73a: open the drawing")
    }

    /// An ephemeral thread and a sub-agent's thread are in the store but are nobody's conversation.
    func testEphemeralAndSubAgentThreadsAreLeftOut() {
        let listing = #"{"id":2,"result":{"data":[{"id":"a","cwd":"/x","ephemeral":true},{"id":"b","cwd":"/x","parentThreadId":"a"},{"id":"c","cwd":"/x","ephemeral":false,"parentThreadId":null}]}}"#
        XCTAssertEqual(AppServer.threads(in: [listing]).map(\.id), ["c"])
    }

    /// The store pages can overlap, and a thread can have no name.
    func testARepeatedThreadIsKeptOnceAndAnUnnamedOneSurvives() {
        let repeated = #"{"id":2,"result":{"data":[{"id":"a","name":null,"cwd":"/x","status":{"type":"idle"}},{"id":"a","name":null,"cwd":"/x","status":{"type":"idle"}}]}}"#
        let threads = AppServer.threads(in: [repeated])
        XCTAssertEqual(threads.map(\.id), ["a"])
        XCTAssertNil(threads[0].name)
    }

    /// Anything that is not the listing's own answer is ignored rather than failing the read: the
    /// server writes notifications down the same pipe.
    func testNoisePassesThroughWithoutProducingThreads() {
        XCTAssertEqual(AppServer.threads(in: ["", "not json", #"{"id":1,"result":{"userAgent":"x"}}"#]), [])
    }

    func testTheDiscoveryRequestsAreTheHandshakeThenTheListing() {
        let requests = AppServer.discoveryRequests(limit: 7)
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests[0].contains("\"method\":\"initialize\""))
        XCTAssertFalse(requests[1].contains("\"id\""), "initialized is a notification and is not waited for")
        XCTAssertTrue(requests[2].contains("\"limit\":7"))
        XCTAssertTrue(requests[2].contains("\"sortKey\":\"recency_at\""), "the threads asked for are the ones used last")
        XCTAssertTrue(requests[2].contains("\"useStateDbOnly\":true"), "a scan of every rollout took 3 s for a search")

        let shown = AppServer.discoveryRequests(limit: 7, shown: "01a0f064-1706-76e2-8312-bebefa67f004")
        XCTAssertEqual(shown.count, 4)
        let read = try? JSONSerialization.jsonObject(with: Data(shown[3].utf8)) as? [String: Any]
        XCTAssertEqual(read?["id"] as? Int, AppServer.readID)
        XCTAssertEqual(read?["method"] as? String, "thread/read")
        XCTAssertEqual((read?["params"] as? [String: Any])?["threadId"] as? String, "01a0f064-1706-76e2-8312-bebefa67f004")
    }

    /// The read's thread is apart from the listing's, and a refused read is no thread.
    func testTheReadIsApartFromTheListing() {
        let listing = #"{"id":2,"result":{"data":[{"id":"a","cwd":"/x","recencyAt":300}]}}"#
        let read = #"{"id":3,"result":{"thread":{"id":"old","name":"Investigate","cwd":"/y","recencyAt":1,"status":{"type":"notLoaded"}}}}"#
        XCTAssertEqual(AppServer.threads(in: [read, listing]).map(\.id), ["a"])
        XCTAssertEqual(AppServer.read(in: [read, listing])?.id, "old")
        XCTAssertEqual(AppServer.read(in: [read])?.cwd, "/y")
        XCTAssertNil(AppServer.read(in: [listing, #"{"id":3,"error":{"code":-32600,"message":"thread not loaded: x"}}"#]))
        XCTAssertNil(AppServer.read(in: [#"{"id":3,"result":{"thread":{"id":"s","cwd":"/y","parentThreadId":"old"}}}"#]),
                     "a sub-agent's thread is nobody's conversation")
    }

    /// An error answers a request too. A Codex that refused the read would otherwise hold every
    /// editor opened from the Codex app until the timeout.
    func testAConversationEndsOnAnErrorAnswer() {
        let responder = """
        import sys, time
        sys.stdin.readline()
        print('{"id":1,"result":{}}', flush=True)
        sys.stdin.readline(); sys.stdin.readline(); sys.stdin.readline()
        print('{"id":2,"result":{"data":[]}}', flush=True)
        print('{"id":3,"error":{"code":-32602,"message":"unknown field"}}', flush=True)
        time.sleep(30)
        """
        let started = Date()
        let lines = AppServer.converse("/usr/bin/python3", ["-c", responder],
                                       AppServer.discoveryRequests(shown: "x"), timeout: 20)
        XCTAssertLessThan(Date().timeIntervalSince(started), 15)
        XCTAssertEqual(lines.count, 3)
    }

    /// The conversation stops as soon as every request carrying an id has been answered, and does
    /// not wait for the process to exit: a real app-server keeps running until it is told not to.
    func testAConversationReturnsWhenItsAnswersHaveArrivedAndNotBefore() throws {
        let responder = """
        import sys, time
        sys.stdin.readline()
        print('{"id":1,"result":{}}', flush=True)
        sys.stdin.readline()
        sys.stdin.readline()
        print('{"method":"notification/noise"}', flush=True)
        print('{"id":2,"result":{"data":[]}}', flush=True)
        time.sleep(30)
        """
        let started = Date()
        let lines = AppServer.converse("/usr/bin/python3", ["-c", responder],
                                       AppServer.discoveryRequests(), timeout: 20)
        XCTAssertLessThan(Date().timeIntervalSince(started), 15, "it must not wait out the sleeping process")
        XCTAssertEqual(lines.count, 3, "every line is kept, notifications included")
        XCTAssertTrue(lines.last!.contains("\"id\":2"))
    }

    /// A binary that is not there is not an error to report; there is simply nothing to discover.
    func testAConversationWithNoProcessIsEmpty() {
        XCTAssertEqual(AppServer.converse("/nonexistent/codex", [], AppServer.discoveryRequests()), [])
    }
}
