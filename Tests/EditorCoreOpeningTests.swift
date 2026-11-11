import XCTest

final class EditorCoreOpeningTests: XCTestCase {
    private func drawing(_ key: ScreenshotKey) -> Drawing {
        Drawing(key: key.path, pixels: PixelSize(width: 1000, height: 600), pointScale: 1, marks: [])
    }

    private func open(_ core: inout EditorCore, _ key: ScreenshotKey) {
        _ = core.reduce(.open(drawing(key), style: .standard, metrics: .standard, markStyle: .standard))
    }

    func testTheNextImageFinishesWithWhatTheBarStillOffers() {
        var core = EditorCore()
        open(&core, "/tmp/a.png")
        core.finishes = .init(returnKey: .send, commandReturn: .send)
        _ = core.reduce(.park)
        open(&core, "/tmp/b.png")
        XCTAssertEqual(core.finishes, .init(returnKey: .send, commandReturn: .send))
        XCTAssertTrue(core.key(.returnKey, .command).contains(.send(core.drawing, to: nil)))
    }
}
