import AppKit
import XCTest

@MainActor
final class LiveAskPictureTests: XCTestCase {
    private typealias Plan = LivePacket.Plan
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let terminal = LivePacket.Listed(id: 20, pid: 200, layer: 0, frame: CGRect(x: 0, y: 30, width: 900, height: 700))
    private let browser = LivePacket.Listed(id: 30, pid: 300, layer: 0, frame: CGRect(x: 600, y: 200, width: 900, height: 700))

    private func asked(_ box: CGRect, on window: LivePacket.Listed?) -> LivePacket.Asked {
        LivePacket.Asked(id: UUID(), box: box, window: window?.id)
    }

    func testInkOnOneWindowIsThatWindowAloneAndInkOnNoneIsTheScreen() {
        let first = asked(CGRect(x: 50, y: 100, width: 80, height: 40), on: terminal)
        let second = asked(CGRect(x: 700, y: 400, width: 80, height: 40), on: terminal)
        XCTAssertEqual(LivePacket.plan(for: [first, second], windows: [browser, terminal], screens: [screen]), .window(terminal.id),
                       "covered or not, ink on one window is that window's picture")
        XCTAssertEqual(LivePacket.plan(for: [asked(CGRect(x: 50, y: 900, width: 80, height: 40), on: nil)], windows: [terminal], screens: [screen]),
                       .window(nil))
    }

    func testInkOnTwoWindowsIsTheScreenTheirFramesCover() {
        let onTerminal = asked(CGRect(x: 50, y: 100, width: 80, height: 40), on: terminal)
        let onBrowser = asked(CGRect(x: 1000, y: 500, width: 80, height: 40), on: browser)
        XCTAssertEqual(LivePacket.plan(for: [onTerminal, onBrowser], windows: [browser, terminal], screens: [screen]),
                       .area(CGRect(x: 0, y: 30, width: 1500, height: 870), windows: [browser.id, terminal.id], alone: []),
                       "the frames' union, the windows front to back, and nothing alone when all the ink shows")
    }

    func testInkUnderAnotherAppsWindowInFrontGoesWithItsWindowAlone() {
        let shown = asked(CGRect(x: 50, y: 100, width: 80, height: 40), on: terminal)
        let covered = asked(CGRect(x: 700, y: 400, width: 80, height: 40), on: terminal)
        let onBrowser = asked(CGRect(x: 1000, y: 500, width: 80, height: 40), on: browser)
        guard case .area(_, _, let alone) = LivePacket.plan(for: [shown, onBrowser, covered], windows: [browser, terminal], screens: [screen]) else {
            return XCTFail("ink on two windows is an area")
        }
        XCTAssertEqual(alone, [Plan.Alone(window: terminal.id, ink: [shown.id, covered.id], covered: [covered.id], outside: [])])
    }

    func testNoSheetPanelWindowOffTheInkOrWindowBehindCoversInk() {
        let box = CGRect(x: 700, y: 400, width: 80, height: 40)
        let onTerminal = asked(box, on: terminal), onBrowser = asked(CGRect(x: 1000, y: 800, width: 80, height: 40), on: browser)
        let sheet = LivePacket.Listed(id: 21, pid: terminal.pid, layer: 0, frame: box.insetBy(dx: -20, dy: -20))
        let panel = LivePacket.Listed(id: 40, pid: 400, layer: 3, frame: box.insetBy(dx: -20, dy: -20))
        let elsewhere = LivePacket.Listed(id: 50, pid: 500, layer: 0, frame: CGRect(x: 0, y: 800, width: 300, height: 100))
        let behind = LivePacket.Listed(id: 60, pid: 600, layer: 0, frame: box.insetBy(dx: -20, dy: -20))
        let browserBelow = LivePacket.Listed(id: browser.id, pid: browser.pid, layer: 0, frame: CGRect(x: 600, y: 750, width: 900, height: 200))
        let plan = LivePacket.plan(for: [onTerminal, onBrowser], windows: [sheet, panel, elsewhere, browserBelow, terminal, behind], screens: [screen])
        guard case .area(_, _, let alone) = plan else { return XCTFail("ink on two windows is an area") }
        XCTAssertEqual(alone, [], "its own app's sheet, a floating panel, a window off the ink and one behind cover nothing")
    }

    func testAWindowOfTheInksOwnAppCoversItOnlyAtTwoHundredPointsBothWays() {
        let box = CGRect(x: 100, y: 300, width: 80, height: 40)
        let onTerminal = asked(box, on: terminal), onBrowser = asked(CGRect(x: 1000, y: 500, width: 80, height: 40), on: browser)
        func covers(_ size: CGSize) -> Bool {
            let front = LivePacket.Listed(id: 22, pid: terminal.pid, layer: 0, frame: CGRect(origin: CGPoint(x: 50, y: 250), size: size))
            guard case .area(_, _, let alone) = LivePacket.plan(for: [onTerminal, onBrowser], windows: [front, browser, terminal],
                                                                screens: [screen]) else { return false }
            return alone.first?.covered == [onTerminal.id]
        }
        XCTAssertTrue(covers(CGSize(width: 200, height: 200)))
        XCTAssertFalse(covers(CGSize(width: 199, height: 400)))
        XCTAssertFalse(covers(CGSize(width: 400, height: 199)))
    }

    func testInkOffTheNewestInksDisplayGoesWithItsWindowAlone() {
        let right = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let far = LivePacket.Listed(id: 70, pid: 700, layer: 0, frame: CGRect(x: 1700, y: 100, width: 800, height: 600))
        let onFar = asked(CGRect(x: 1800, y: 200, width: 80, height: 40), on: far)
        let onTerminal = asked(CGRect(x: 50, y: 100, width: 80, height: 40), on: terminal)
        XCTAssertEqual(LivePacket.plan(for: [onFar, onTerminal], windows: [terminal, far], screens: [screen, right]),
                       .area(terminal.frame, windows: [terminal.id],
                             alone: [Plan.Alone(window: far.id, ink: [onFar.id], covered: [], outside: [onFar.id])]),
                       "the picture keeps to the newest ink's display")
    }

    func testInkOverAnOpenMenuIsTheScreenRoundTheMenuAndItsWindow() {
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let menu = LivePacket.Listed(id: 90, pid: 900, layer: menuLevel, frame: CGRect(x: 102, y: 25, width: 246, height: 587))
        let onMenu = asked(CGRect(x: 150, y: 100, width: 80, height: 40), on: terminal)
        XCTAssertEqual(LivePacket.plan(for: [onMenu], windows: [menu, terminal], screens: [screen]),
                       .area(CGRect(x: 0, y: 25, width: 900, height: 705), windows: [terminal.id], alone: []),
                       "the window alone would leave the menu out")
        let elsewhere = LivePacket.Listed(id: 91, pid: 910, layer: menuLevel, frame: CGRect(x: 1200, y: 25, width: 200, height: 300))
        let overlay = LivePacket.Listed(id: 92, pid: 920, layer: Int(CGWindowLevelForKey(.screenSaverWindow)), frame: screen)
        XCTAssertEqual(LivePacket.plan(for: [onMenu], windows: [overlay, elsewhere, terminal], screens: [screen]), .window(terminal.id),
                       "a menu off the ink and a window over the whole screen are not what the ink is on")
    }

    func testInkOnNoWindowBesideAWindowsInkTakesInARoomRoundIt() {
        let onDesktop = asked(CGRect(x: 1300, y: 850, width: 80, height: 40), on: nil)
        let onTerminal = asked(CGRect(x: 50, y: 100, width: 80, height: 40), on: terminal)
        let margin = LivePacket.screenInkMargin
        XCTAssertEqual(LivePacket.plan(for: [onDesktop, onTerminal], windows: [terminal], screens: [screen]),
                       .area(CGRect(x: 0, y: 30, width: 1380 + margin, height: 860 + margin), windows: [terminal.id], alone: []))
    }

    func testAPromptOfMacOSsOwnOverTheInkIsNotWhatTheInkIsOn() {
        let finder = info(id: 20, owner: "Finder", layer: 0, frame: terminal.frame)
        for layer in [Int(CGWindowLevelForKey(.modalPanelWindow)), Int(CGWindowLevelForKey(.popUpMenuWindow)), 0] {
            let prompt = info(id: 99, owner: "UserNotificationCenter", layer: layer, frame: CGRect(x: 300, y: 200, width: 260, height: 320))
            let listed = LivePacket.listed([prompt, finder], own: 1)
            XCTAssertEqual(listed.map(\.id), [20], "at layer \(layer)")
            let onFinder = asked(CGRect(x: 350, y: 300, width: 80, height: 40), on: terminal)
            XCTAssertEqual(LivePacket.plan(for: [onFinder], windows: listed, screens: [screen]), .window(terminal.id), "at layer \(layer)")
            let point = CGPoint(x: 390, y: 320)
            XCTAssertEqual(LiveWindows.window(under: point, in: [prompt, finder], own: 1, ordinary: true)?.id, 20, "at layer \(layer)")
            XCTAssertEqual(LiveWindows.window(under: point, in: [prompt, finder], own: 1, ordinary: false)?.id, 20, "at layer \(layer)")
        }
    }

    func testEveryPromptOwnerIsPassedOverAndAnAppsPanelIsNot() {
        let finder = info(id: 20, owner: "Finder", layer: 0, frame: terminal.frame)
        let point = CGPoint(x: 390, y: 320)
        for owner in SystemPrompts.owners {
            let prompt = info(id: 99, owner: owner, layer: 0, frame: CGRect(x: 300, y: 200, width: 260, height: 320))
            XCTAssertEqual(LiveWindows.window(under: point, in: [prompt, finder], own: 1, ordinary: true)?.id, 20, owner)
        }
        let panel = info(id: 98, owner: "Xcode", layer: Int(CGWindowLevelForKey(.modalPanelWindow)), frame: CGRect(x: 300, y: 200, width: 260, height: 320))
        XCTAssertEqual(LiveWindows.window(under: point, in: [panel, finder], own: 1, ordinary: false)?.id, 98)
        XCTAssertNil(LiveWindows.window(under: point, in: [panel, finder], own: 1, ordinary: true))
    }

    func testVignettesTitledWindowTakesTheMarkAndItsOtherWindowsAreSeenThrough() {
        let finder = info(id: 20, owner: "Finder", layer: 0, frame: terminal.frame)
        let frame = CGRect(x: 300, y: 200, width: 600, height: 400)
        let overlay = info(id: 31, owner: "Vignette", layer: 1, frame: frame, pid: 300)
        let point = CGPoint(x: 390, y: 320)
        for layer in [0, Int(CGWindowLevelForKey(.floatingWindow))] {
            let settings = info(id: 30, owner: "Vignette", layer: layer, frame: frame, pid: 300)
            let windows = [overlay, settings, finder]
            XCTAssertEqual(LiveWindows.window(under: point, in: windows, own: 300, ownTitled: [30], ordinary: true)?.id, 30, "at layer \(layer)")
            XCTAssertEqual(LiveWindows.window(under: point, in: windows, own: 300, ownTitled: [30], ordinary: false)?.id, 30, "at layer \(layer)")
            XCTAssertEqual(LiveWindows.window(under: point, in: windows, own: 300, ordinary: true)?.id, 20, "at layer \(layer)")
        }
    }

    func testVignettesAlertTakesNoMark() {
        let finder = info(id: 20, owner: "Finder", layer: 0, frame: terminal.frame)
        let alert = info(id: 30, owner: "Vignette", layer: Int(CGWindowLevelForKey(.modalPanelWindow)),
                         frame: CGRect(x: 300, y: 200, width: 260, height: 160), pid: 300)
        XCTAssertNil(LiveWindows.window(under: CGPoint(x: 390, y: 320), in: [alert, finder], own: 300, ownTitled: [30], ordinary: true))
    }

    private func info(id: CGWindowID, owner: String, layer: Int, frame: CGRect, pid: pid_t? = nil) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid ?? pid_t(id) * 10, kCGWindowOwnerName as String: owner,
         kCGWindowLayer as String: layer, kCGWindowAlpha as String: 1.0, kCGWindowBounds as String: frame.dictionaryRepresentation]
    }
}
