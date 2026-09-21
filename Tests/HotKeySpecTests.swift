import AppKit
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

    func testEveryKeyCodeSurvivesTextAndParse() {
        let combinations: [UInt32] = [0, UInt32(cmdKey), UInt32(shiftKey), UInt32(optionKey), UInt32(controlKey),
                                      UInt32(cmdKey | shiftKey), UInt32(cmdKey | optionKey | controlKey),
                                      UInt32(cmdKey | shiftKey | optionKey | controlKey)]
        for (name, code) in HotKeySpec.keyCodes {
            XCTAssertEqual(HotKeySpec.keyName(forKeyCode: code), name)
            for modifiers in combinations {
                guard let text = HotKeySpec.text(keyCode: code, modifiers: modifiers) else {
                    return XCTFail("no text for \(name)")
                }
                XCTAssertEqual(HotKeySpec.parse(text), .key(keyCode: code, modifiers: modifiers), text)
            }
        }
    }

    func testTextNamesUnknownKeyCodeAsNothing() {
        XCTAssertNil(HotKeySpec.text(keyCode: 999, modifiers: 0))
        XCTAssertNil(HotKeySpec.keyName(forKeyCode: 999))
    }

    func testEveryModifierSurvivesDoubleTapTextAndParse() {
        for (name, code) in HotKeySpec.modifierCodes {
            XCTAssertEqual(HotKeySpec.doubleTapText(forKeyCode: code), "double-\(name)")
            XCTAssertEqual(HotKeySpec.parse("double-\(name)"), .doubleTap(keyCode: code))
        }
        XCTAssertNil(HotKeySpec.doubleTapText(forKeyCode: 0))
    }

    func testGlyphsReadAsMacShortcuts() {
        XCTAssertEqual(HotKeySpec.parse("cmd+shift+6")?.glyphs, "⇧⌘6")
        XCTAssertEqual(HotKeySpec.parse("ctrl+opt+space")?.glyphs, "⌃⌥Space")
        XCTAssertEqual(HotKeySpec.parse("cmd+f5")?.glyphs, "⌘F5")
        XCTAssertEqual(HotKeySpec.parse("cmd+up")?.glyphs, "⌘↑")
        XCTAssertEqual(HotKeySpec.parse("cmd+return")?.glyphs, "⌘↩")
        XCTAssertEqual(HotKeySpec.parse("double-rshift")?.glyphs, "Right Shift ×2")
    }

    func testLabelNamesTheKey() {
        XCTAssertEqual(HotKeySpec.parse("cmd+shift+6")?.label, "⇧⌘6")
        XCTAssertEqual(HotKeySpec.parse("double-rshift")?.label, "double-tap Right Shift")
        XCTAssertEqual(HotKeySpec.parse("double-lcmd")?.label, "double-tap Left Command")
    }

    func testMenuKeyEquivalent() {
        let combination = HotKeySpec.parse("cmd+shift+6")?.menuKeyEquivalent
        XCTAssertEqual(combination?.key, "6")
        XCTAssertEqual(combination?.modifiers, [.command, .shift])

        XCTAssertEqual(HotKeySpec.parse("cmd+f5")?.menuKeyEquivalent?.key,
                       String(UnicodeScalar(UInt32(NSF5FunctionKey))!))
        XCTAssertEqual(HotKeySpec.parse("cmd+up")?.menuKeyEquivalent?.key,
                       String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!))
        XCTAssertEqual(HotKeySpec.parse("ctrl+opt+space")?.menuKeyEquivalent?.key, " ")
        XCTAssertNil(HotKeySpec.parse("double-rshift")?.menuKeyEquivalent)
    }

    func testCarbonModifiersFromEventFlags() {
        XCTAssertEqual(HotKeySpec.carbonModifiers([.command, .shift]), UInt32(cmdKey | shiftKey))
        XCTAssertEqual(HotKeySpec.carbonModifiers([.option, .control]), UInt32(optionKey | controlKey))
        XCTAssertEqual(HotKeySpec.carbonModifiers([.capsLock, .function]), 0)
    }
}
