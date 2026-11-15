import Combine
import SwiftUI
import XCTest

@MainActor
final class SetupModelTests: XCTestCase {
    private var withClaude: SetupWindowController.Callbacks {
        var callbacks = SetupWindowController.Callbacks()
        callbacks.agents = {
            [AgentPluginStatus(root: URL(fileURLWithPath: "/setup-tests/.claude"), client: .claude, installed: false, hasTool: true)]
        }
        return callbacks
    }

    func testNotNowInAllOfSetupGoesOnToTheAgents() {
        let model = SetupModel(callbacks: withClaude, scope: .whole, start: .liveInk)
        var closed = false
        model.done = { closed = true }
        model.useLiveInk(false, animation: .default)
        let moved = expectation(description: "the page moved")
        DispatchQueue.main.async { moved.fulfill() }
        wait(for: [moved], timeout: 1)
        XCTAssertFalse(closed)
        XCTAssertEqual(model.page, .agents)
    }

    func testSetupThatShowedLiveInkRecordsItsOfferOnThisMacToo() {
        let suite = "SetupModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SetupModel(callbacks: withClaude, scope: .whole, start: .liveInk)
        var data = SettingsData()
        model.record(in: &data, on: defaults)
        XCTAssertTrue(data.liveInkOffered)
        XCTAssertTrue(defaults.bool(forKey: ThisMac.liveInkOfferKey))
    }

    func testSetupClosedBeforeLiveInkLeavesItsOfferForTheNextLaunch() {
        let suite = "SetupModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SetupModel(callbacks: withClaude, scope: .whole, start: .welcome)
        var data = SettingsData()
        model.record(in: &data, on: defaults)
        XCTAssertFalse(data.liveInkOffered)
        XCTAssertFalse(defaults.bool(forKey: ThisMac.liveInkOfferKey))
    }

    func testNotNowClosesLiveInkAlone() {
        let model = SetupModel(callbacks: withClaude, scope: .liveInk, start: .liveInk)
        var closed = false
        model.done = { closed = true }
        model.useLiveInk(false, animation: .default)
        XCTAssertTrue(closed)
    }

    func testAToolFoundAfterSetupOpensTurnsItsSwitchOn() {
        let root = URL(fileURLWithPath: "/setup-tests/.claude")
        var hasTool = false
        let changed = PassthroughSubject<Void, Never>()
        var callbacks = SetupWindowController.Callbacks()
        callbacks.agents = { [AgentPluginStatus(root: root, client: .claude, installed: false, hasTool: hasTool)] }
        callbacks.changes = changed.eraseToAnyPublisher()
        let model = SetupModel(callbacks: callbacks)
        XCTAssertFalse(model.chosen.contains(root))
        hasTool = true
        changed.send()
        XCTAssertTrue(model.chosen.contains(root))
    }

    func testStartingOnLiveInkPermissionsHoldsThemAfterUseLiveInk() {
        let model = SetupModel(callbacks: .init(), scope: .whole, start: .liveInkSetup)
        XCTAssertEqual(model.page, .liveInkSetup)
        XCTAssertEqual(model.pages, [.welcome, .shortcut, .liveInk, .liveInkSetup])
    }

    func testSetupSavesOpenAtLoginOnlyWhenItsOwnSwitchMoved() {
        var callbacks = SetupWindowController.Callbacks()
        callbacks.launchAtLogin = { true }
        let model = SetupModel(callbacks: callbacks)
        XCTAssertNil(model.launchAtLoginChoice)
        model.launchAtLogin = false
        XCTAssertEqual(model.launchAtLoginChoice, false)
        model.launchAtLogin = true
        XCTAssertNil(model.launchAtLoginChoice)
    }
}
