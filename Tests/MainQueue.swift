import XCTest

extension XCTestCase {
    func runTheMainQueue() {
        let ran = expectation(description: "the main queue ran every block queued before this one")
        DispatchQueue.main.async { ran.fulfill() }
        wait(for: [ran], timeout: 10)
    }
}
