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
        let model = SetupModel(callbacks: withClaude, scope: .whole, start: .liveInk, offersLiveInk: true)
        var closed = false
        model.done = { closed = true }
        model.useLiveInk(false, animation: .default)
        let moved = expectation(description: "the page moved")
        DispatchQueue.main.async { moved.fulfill() }
        wait(for: [moved], timeout: 1)
        XCTAssertFalse(closed)
        XCTAssertEqual(model.page, .agents)
    }

    func testNotNowClosesLiveInkAlone() {
        let model = SetupModel(callbacks: withClaude, scope: .liveInk, start: .liveInk, offersLiveInk: true)
        var closed = false
        model.done = { closed = true }
        model.useLiveInk(false, animation: .default)
        XCTAssertTrue(closed)
    }

    func testStartingOnLiveInkPermissionsHoldsThemAfterUseLiveInk() {
        let model = SetupModel(callbacks: .init(), scope: .whole, start: .liveInkSetup, offersLiveInk: true)
        XCTAssertEqual(model.page, .liveInkSetup)
        XCTAssertEqual(model.pages, [.welcome, .shortcut, .liveInk, .liveInkSetup])
    }
}
