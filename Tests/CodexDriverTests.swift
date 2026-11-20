import XCTest

@MainActor
final class CodexDriverTests: XCTestCase {
    private let driver = CodexDriver(binary: { nil }, home: FileManager.default.temporaryDirectory)

    private func words(for answer: Result<[String: Any], AppServerSession.ServerError>) -> String? {
        CodexDriver.accountProblem(answer).map { driver.reason(forError: $0) ?? driver.couldNotStart }
    }

    func testAnAccountLetsTheStartGoOn() {
        XCTAssertNil(CodexDriver.accountProblem(.success(["account": ["type": "chatgpt"]])))
    }

    func testNoAccountReadsAsSignedOut() {
        XCTAssertEqual(words(for: .success(["account": NSNull()])), CodexDriver.signedOut)
        XCTAssertEqual(words(for: .failure(.init(message: "Unauthorized"))), CodexDriver.signedOut)
    }

    func testAnAccountReadErrorAboutSomethingElseSaysCodexCouldNotStart() {
        XCTAssertEqual(words(for: .failure(.init(message: "connection reset by peer"))), driver.couldNotStart)
    }
}
