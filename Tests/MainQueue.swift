import XCTest

extension XCTestCase {
    func runTheMainQueue() {
        let ran = expectation(description: "the main queue ran every block queued before this one")
        DispatchQueue.main.async { ran.fulfill() }
        wait(for: [ran], timeout: 10)
    }

    func runTimersDue(within delay: TimeInterval) {
        let ran = expectation(description: "a timer armed after every timer due within \(delay) s ran after them")
        RunLoop.main.add(Timer(timeInterval: delay, repeats: false) { _ in ran.fulfill() }, forMode: .common)
        wait(for: [ran], timeout: delay + 10)
    }
}
