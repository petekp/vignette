import AppKit
import XCTest

final class StateReportTests: XCTestCase {
    func testTopLeftFlipsAgainstThePrimaryDisplay() {
        // A 100x50 window whose bottom-left is 200 points up on a 982-point primary display.
        XCTAssertEqual(StateReport.topLeft(NSRect(x: 10, y: 200, width: 100, height: 50), primaryHeight: 982), [10, 732, 100, 50])
        // A display above the primary has AppKit y beyond the primary's height and negative CG y.
        XCTAssertEqual(StateReport.topLeft(NSRect(x: 255, y: 982, width: 2560, height: 1440), primaryHeight: 982), [255, -1440, 2560, 1440])
        XCTAssertEqual(StateReport.topLeft(.zero, primaryHeight: 982), [0, 982, 0, 0])
    }

    func testRendersOneSortedLineThatParsesBack() throws {
        var report = StateReport()
        report.sections = ["tag": "t1", "drafts": ["/a b.png"], "page": "unavailable", "nested": ["x": 1, "note": "line\nbreak"]]
        let line = report.rendered()
        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.hasPrefix(#"{"drafts":["/a b.png"],"nested":{"note":"line\nbreak","x":1},"page":"unavailable","tag":"t1"}"#), line)
        let back = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        XCTAssertEqual(back?["tag"] as? String, "t1")
    }

    func testNilOptionalsRenderAsNull() {
        var report = StateReport()
        let missing: String? = nil
        report.sections = ["focused": missing as Any]
        XCTAssertEqual(report.rendered(), #"{"focused":null}"#)
    }

    @MainActor
    func testPageQueryAnswersOnceWithoutAPage() {
        let controller = AnnotationController()   // never preloaded: no web view
        var answers: [Any?] = []
        controller.queryPage(timeout: 0.05) { answers.append($0) }
        XCTAssertEqual(answers.count, 1)
        XCTAssertNil(answers[0] as Any?)
        let waited = expectation(description: "past the timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { waited.fulfill() }
        wait(for: [waited], timeout: 1)
        XCTAssertEqual(answers.count, 1, "the timeout must not answer a second time")
        XCTAssertEqual(controller.stateJSON["pageState"] as? String, "unavailable")
    }

    func testUnserializableStateStillYieldsALine() {
        var report = StateReport()
        report.sections = ["bad": Date()]
        XCTAssertEqual(report.rendered(), #"{"error":"state not serializable"}"#)
    }
}
