import XCTest

@MainActor
final class JSONLinesProcessTests: XCTestCase {
    private var folder: URL!
    private var lines: [[String: Any]] = []
    private var status: Int32?

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-json-lines-\(UUID().uuidString)")
        lines = []
        status = nil
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func start(_ script: String) throws -> JSONLinesProcess {
        try JSONLinesProcess(binary: "/bin/sh", arguments: ["-c", script], environment: ["PATH": "/bin:/usr/bin"], folder: folder,
                             onLine: { [unowned self] in lines.append($0) }, onEnd: { [unowned self] in status = $0 })
    }

    private func spin(until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    func testEachJSONObjectLineArrivesOnceAndTheEndHasTheStatus() throws {
        let process = try start(#"printf '{"a":1}\n{"b":'; sleep 0.1; printf '2}\n[3]\n'; exit 4"#)
        spin { status != nil && lines.count >= 2 }
        XCTAssertEqual(status, 4)
        XCTAssertEqual(lines as NSArray, [["a": 1], ["b": 2]] as NSArray)
        XCTAssertGreaterThan(process.pid, 0)
    }

    func testTheLastErrorLineIsTheLastLineOfStandardError() throws {
        let process = try start("echo one >&2; echo two >&2")
        spin { status != nil && process.lastErrorLine == "two" }
        XCTAssertEqual(process.lastErrorLine, "two")
    }

    func testStopEndsTheProcessAndReportsNothingMore() throws {
        let process = try start("while :; do sleep 0.1; done")
        let pid = process.pid
        process.stop()
        spin { kill(pid, 0) != 0 }
        XCTAssertNotEqual(kill(pid, 0), 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(status)
    }
}
