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
        report.sections = ["tag": "t1", "drawings": ["/a b.png"], "nested": ["x": 1, "note": "line\nbreak"]]
        let line = report.rendered()
        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.hasPrefix(#"{"drawings":["/a b.png"],"nested":{"note":"line\nbreak","x":1},"tag":"t1"}"#), line)
        let back = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        XCTAssertEqual(back?["tag"] as? String, "t1")
    }

    func testNilOptionalsRenderAsNull() {
        var report = StateReport()
        let missing: String? = nil
        report.sections = ["focused": missing as Any]
        XCTAssertEqual(report.rendered(), #"{"focused":null}"#)
    }

    func testTheEditorSectionNeverHoldsATextsWords() throws {
        var core = EditorCore()
        let marks = [Mark(geometry: .text(Mark.Text(origin: CGPoint(x: 40, y: 40), text: "Zanzibar", wrap: nil, size: 24))),
                     Mark(geometry: .rectangle(CGRect(x: 100, y: 200, width: 300, height: 100)), agent: true)]
        _ = core.reduce(.open(Drawing(key: "/tmp/shot.png", pixels: PixelSize(width: 1000, height: 600), pointScale: 1, marks: marks),
                              style: .standard, metrics: .standard, arrowhead: .standard, pickColor: { _ in nil }))
        _ = core.reduce(.zoomChanged(1))
        // A double-click types into the text.
        core.click(50, 50, count: 2)
        _ = core.reduce(.typingChanged("Zanzibar Quixote"))
        XCTAssertNotNil(core.typing)

        var report = StateReport()
        report.sections = ["editor": core.inspection]
        let line = report.rendered()
        XCTAssertFalse(line.contains("Zanzibar"), line)
        XCTAssertFalse(line.contains("Quixote"), line)
        let editor = try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["editor"] as? [String: Any])
        XCTAssertEqual(editor["tool"] as? String, "select")
        XCTAssertEqual(editor["typing"] as? Bool, true)
        XCTAssertEqual(editor["selection"] as? [Int], [0])
        XCTAssertEqual(editor["undo"] as? Int, 0)
        XCTAssertEqual(editor["redo"] as? Int, 0)
        let listed = try XCTUnwrap(editor["marks"] as? [[String: Any]])
        XCTAssertEqual(listed.map { $0["type"] as? String }, ["text", "rectangle"])
        XCTAssertEqual(listed.map { $0["agent"] as? Bool }, [false, true])
        XCTAssertEqual(listed.last?["frame"] as? [Int], [100, 200, 300, 100])
    }

    func testUnserializableStateStillYieldsALine() {
        var report = StateReport()
        report.sections = ["bad": Date()]
        XCTAssertEqual(report.rendered(), #"{"error":"state not serializable"}"#)
    }
}
