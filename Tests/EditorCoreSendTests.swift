import XCTest

final class EditorCoreSendTests: XCTestCase {
    private let session = AgentDestination(id: "s1", name: "s1", address: .claudeSession("s1"))

    private func core() -> EditorCore {
        var core = EditorCore()
        open(&core)
        return core
    }

    private func open(_ core: inout EditorCore) {
        _ = core.reduce(.open(Drawing(key: "/tmp/shot.png", pixels: PixelSize(width: 1000, height: 600), pointScale: 1, marks: []),
                              style: .standard, metrics: .standard, markStyle: .standard))
    }

    /// The host says what Return and Cmd+Return finish with. Cmd+Return ends typing first, as Done does.
    func testReturnAndCmdReturnFinishWithWhatTheHostSays() {
        var core = core()
        core.finishes = .init(returnKey: .done, commandReturn: .send)
        XCTAssertTrue(core.key(.returnKey).contains(.done(core.drawing)))
        XCTAssertTrue(core.key(.returnKey, .command).contains(.send(core.drawing, to: nil)))
        _ = core.reduce(.setTool(.text))
        core.click(200, 200)
        _ = core.reduce(.typingChanged("note"))
        let sent = core.key(.returnKey, .command)
        XCTAssertEqual(sent.first, .endTyping)
        XCTAssertTrue(sent.contains(.send(core.drawing, to: nil)), "the text is in the drawing that is sent")
        XCTAssertEqual(core.drawing.marks.count, 1)

        core.finishes = .init(returnKey: .send, commandReturn: .send)
        XCTAssertTrue(core.key(.returnKey).contains(.send(core.drawing, to: nil)))
    }

    func testSendInTheToolbarCarriesTheDestinationItChose() {
        var core = core()
        XCTAssertTrue(core.reduce(.send(session)).contains(.send(core.drawing, to: session)))
    }

    func testASendPressedAfterTheEditorClosedIsDroppedAndTheNextImagesKeySendsWhereItsOwnBarDoes() {
        var core = core()
        core.finishes = .init(returnKey: .done, commandReturn: .send)
        _ = core.reduce(.park)
        XCTAssertEqual(core.reduce(.send(session)), [])
        open(&core)
        XCTAssertTrue(core.key(.returnKey, .command).contains(.send(core.drawing, to: nil)))
    }
}
