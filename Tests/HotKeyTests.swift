import Carbon
import XCTest

final class HotKeyTests: XCTestCase {
    func testParsesModifiersAndKey() {
        XCTAssertEqual(HotKey.parse("cmd+shift+6"), .key(keyCode: 22, modifiers: UInt32(cmdKey | shiftKey)))
        XCTAssertEqual(HotKey.parse("ctrl+opt+s"), .key(keyCode: 1, modifiers: UInt32(controlKey | optionKey)))
        XCTAssertEqual(HotKey.parse("cmd+f5"), .key(keyCode: 96, modifiers: UInt32(cmdKey)))
        XCTAssertEqual(HotKey.parse("command+option+control+return"),
                       .key(keyCode: 36, modifiers: UInt32(cmdKey | optionKey | controlKey)))
    }

    func testIgnoresCaseAndWhitespace() {
        XCTAssertEqual(HotKey.parse(" Cmd + Shift + 6 "), HotKey.parse("cmd+shift+6"))
        XCTAssertEqual(HotKey.parse("Double-RShift"), .doubleTap(keyCode: 60))
    }

    func testParsesDoubleTapOfEachModifier() {
        let expected: [String: UInt16] = ["lshift": 56, "rshift": 60, "lcmd": 55, "rcmd": 54,
                                          "lopt": 58, "ropt": 61, "lctrl": 59, "rctrl": 62]
        for (name, code) in expected {
            XCTAssertEqual(HotKey.parse("double-\(name)"), .doubleTap(keyCode: code), name)
        }
    }

    func testRejectsWhatItCannotMap() {
        XCTAssertNil(HotKey.parse(""))
        XCTAssertNil(HotKey.parse("cmd"))
        XCTAssertNil(HotKey.parse("cmd+"))
        XCTAssertNil(HotKey.parse("cmd+shift+§"))
        XCTAssertNil(HotKey.parse("double-space"))
        XCTAssertNil(HotKey.parse("double-"))
    }
}
