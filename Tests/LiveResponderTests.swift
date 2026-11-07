import XCTest

@MainActor
final class LiveResponderTests: XCTestCase {
    private final class Driver: ResponderDriver {
        let client = AgentClient.codex
        let name = "Codex"
        let binary: @Sendable () -> String? = { "/usr/bin/true" }
        let notFound = ResponderRefusal(reason: "No Codex.", detail: "none")
        let couldNotStart = "Codex couldn't start."
        let couldNotAnswer = "Codex couldn't answer."
        var report: ((ResponderEvent) -> Void)?
        var started: XCTestExpectation?
        var sent = 0

        func start(binary: String, askWaiting: @escaping () -> Bool, report: @escaping (ResponderEvent) -> Void) -> String? {
            self.report = report
            started?.fulfill()
            return nil
        }

        func send(_ parts: [LiveResponder.Part]) { sent += 1 }
        func interrupt() {}
        func stop() {}
        func reason(forError text: String) -> String? { nil }
        nonisolated static func availability() -> LiveResponder.Availability { .ready }
        nonisolated static func problem(_ availability: LiveResponder.Availability) -> String? { nil }
        static let alwaysOffered = true
    }

    private func askedAndUnderWay() async -> (LiveResponder, Driver, () -> [Result<LiveAnswer, LiveResponder.Failure>]) {
        let driver = Driver()
        let started = expectation(description: "the driver started")
        driver.started = started
        let responder = LiveResponder(driver: driver)
        var results: [Result<LiveAnswer, LiveResponder.Failure>] = []
        responder.ask(.init(content: { _ in [.text("what is this")] }, onSay: { _ in }, onAnswer: { results.append($0) }))
        await fulfillment(of: [started], timeout: 5)
        driver.report?(.ready("test"))
        return (responder, driver, { results })
    }

    func testAnAskUnderWayWhenTheSignInGoesFailsOnce() async {
        let (responder, driver, results) = await askedAndUnderWay()
        XCTAssertEqual(responder.state, .asking)
        XCTAssertEqual(driver.sent, 1)
        responder.stop(failingAsks: true)
        XCTAssertEqual(results().count, 1)
        guard case .failure? = results().first else { return XCTFail("the ask was answered, not failed") }
        XCTAssertEqual(responder.state, .stopped)
    }
}
