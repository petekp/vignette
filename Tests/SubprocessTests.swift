import XCTest

final class SubprocessTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-subprocess-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func sh(_ script: String, timeout: TimeInterval = 5, environment: [String: String] = [:],
                    includingErrors: Bool = true) throws -> (status: Int32, output: String, timedOut: Bool) {
        try XCTUnwrap(Subprocess.run("/bin/sh", ["-c", script], timeout: timeout, environment: environment, folder: folder,
                                     includingErrors: includingErrors))
    }

    func testAFinishedCommandAnswersItsStatusAndBothStreams() throws {
        let run = try sh("echo out; echo err >&2; exit 3")
        XCTAssertEqual(run.status, 3)
        XCTAssertEqual(run.output, "out\nerr\n")
        XCTAssertFalse(run.timedOut)
    }

    func testWithoutErrorsTheOutputIsStandardOutputAlone() throws {
        XCTAssertEqual(try sh("echo out; echo err >&2", includingErrors: false).output, "out\n")
    }

    func testItRunsInTheFolderWithTheAddedEnvironment() throws {
        XCTAssertEqual(try sh("echo $VIGNETTE_TEST_VALUE > here.txt", environment: ["VIGNETTE_TEST_VALUE": "seven"]).status, 0)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("here.txt"), encoding: .utf8), "seven\n")
    }

    func testACommandThatCannotStartAnswersNil() {
        XCTAssertNil(Subprocess.run(folder.appendingPathComponent("missing").path, [], timeout: 5))
    }

    func testACommandPastItsDeadlineIsStoppedAndSaysSo() throws {
        let start = Date()
        let run = try sh("exec sleep 30", timeout: 0.3)
        XCTAssertTrue(run.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testACommandThatIgnoresTheStopIsKilled() {
        let answered = expectation(description: "answered")
        DispatchQueue.global().async {
            let run = Subprocess.run("/bin/sh", ["-c", "trap '' TERM; while :; do sleep 0.1; done"], timeout: 0.3)
            XCTAssertEqual(run?.timedOut, true)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 0.3 + Subprocess.killGrace + Subprocess.drainLimit + 1)
    }

    func testOutputHeldOpenByABackgroundProcessDoesNotHoldTheAnswer() throws {
        let start = Date()
        let run = try sh("sleep 30 & echo $!; echo done")
        if let pid = run.output.split(separator: "\n").first.flatMap({ Int32($0) }) { kill(pid, SIGKILL) }
        XCTAssertEqual(run.status, 0)
        XCTAssertFalse(run.timedOut)
        XCTAssertTrue(run.output.hasSuffix("done\n"), run.output)
        XCTAssertLessThan(Date().timeIntervalSince(start), Subprocess.drainLimit + 2)
    }

    func testABackgroundProcessCanStillWriteAfterTheAnswer() throws {
        let marker = folder.appendingPathComponent("wrote")
        try autoreleasepool {
            XCTAssertEqual(try sh("(sleep 1; echo late && touch wrote) & echo started").output, "started\n")
        }
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }
}
