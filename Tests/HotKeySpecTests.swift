import Carbon
import XCTest

final class HotKeySpecTests: XCTestCase {
    func testParsesModifiersAndKey() {
        XCTAssertEqual(HotKeySpec.parse("cmd+shift+6"), .key(keyCode: 22, modifiers: UInt32(cmdKey | shiftKey)))
        XCTAssertEqual(HotKeySpec.parse("ctrl+opt+s"), .key(keyCode: 1, modifiers: UInt32(controlKey | optionKey)))
        XCTAssertEqual(HotKeySpec.parse("cmd+f5"), .key(keyCode: 96, modifiers: UInt32(cmdKey)))
        XCTAssertEqual(HotKeySpec.parse("command+option+control+return"),
                       .key(keyCode: 36, modifiers: UInt32(cmdKey | optionKey | controlKey)))
    }

    func testIgnoresCaseAndWhitespace() {
        XCTAssertEqual(HotKeySpec.parse(" Cmd + Shift + 6 "), HotKeySpec.parse("cmd+shift+6"))
        XCTAssertEqual(HotKeySpec.parse("Double-RShift"), .doubleTap(keyCode: 60))
    }

    func testParsesDoubleTapOfEachModifier() {
        let expected: [String: UInt16] = ["lshift": 56, "rshift": 60, "lcmd": 55, "rcmd": 54,
                                          "lopt": 58, "ropt": 61, "lctrl": 59, "rctrl": 62]
        for (name, code) in expected {
            XCTAssertEqual(HotKeySpec.parse("double-\(name)"), .doubleTap(keyCode: code), name)
        }
    }

    func testRejectsWhatItCannotMap() {
        XCTAssertNil(HotKeySpec.parse(""))
        XCTAssertNil(HotKeySpec.parse("cmd"))
        XCTAssertNil(HotKeySpec.parse("cmd+"))
        XCTAssertNil(HotKeySpec.parse("cmd+shift+§"))
        XCTAssertNil(HotKeySpec.parse("double-space"))
        XCTAssertNil(HotKeySpec.parse("double-"))
    }
}
