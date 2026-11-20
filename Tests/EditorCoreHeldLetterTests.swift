import XCTest

final class EditorCoreHeldLetterTests: XCTestCase {
    private func core() -> EditorCore {
        var core = EditorCore()
        _ = core.reduce(.open(Drawing(key: "/tmp/shot.png", pixels: PixelSize(width: 1000, height: 600), pointScale: 1, marks: []),
                              style: .standard, metrics: .standard, markStyle: .standard))
        _ = core.reduce(.zoomChanged(1))
        return core
    }

    private func textOf(_ mark: Mark?) -> Mark.Text? {
        if case .text(let text)? = mark?.geometry { return text }
        return nil
    }

    func testAToolKeyRightAfterABoxPicksItsToolUnlessACharacterFollows() throws {
        var core = core()
        core.drag(from: (100, 100), to: (300, 200))
        XCTAssertTrue(core.key(.character("a")).contains(.holdKey))
        XCTAssertEqual(core.tool, .arrow)
        XCTAssertEqual(core.drawing.marks.count, 1)
        XCTAssertTrue(core.key(.character("d")).contains(.passKeysToText))
        XCTAssertEqual(core.tool, .rectangle)
        XCTAssertNotNil(textOf(core.drawing.marks.last))

        var other = self.core()
        other.drag(from: (100, 100), to: (300, 200))
        other.key(.character("a"))
        other.drag(from: (500, 300), to: (700, 400))
        XCTAssertEqual(other.tool, .arrow)
        guard case .arrow? = other.drawing.marks.last?.geometry else { return XCTFail("no arrow") }

        var option = self.core()
        option.drag(from: (100, 100), to: (300, 200))
        option.key(.character("a"))
        XCTAssertFalse(option.key(.character("e"), .option).contains(.passKeysToText),
                       "an Option key after the tool key starts no note, as in the message field")
        XCTAssertFalse(option.holdsKey)
        XCTAssertEqual(option.tool, .arrow)
        XCTAssertEqual(option.drawing.marks.count, 1)
    }
}
