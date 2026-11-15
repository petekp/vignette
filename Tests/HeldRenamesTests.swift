import XCTest

final class HeldRenamesTests: XCTestCase {
    private func delivered(_ held: inout ScreenshotWatcher.HeldRenames, through scan: Int, present: Set<String>,
                           current: Set<String>) -> (renames: [String], removed: [String]) {
        let delivery = held.deliver(through: scan, left: ScreenshotWatcher.left(present, for: current))
        return (delivery.renames.map { "\($0.from)>\($0.to)" }, delivery.removed)
    }

    func testAHeldRenameWaitsForTheDeliveryOfItsOwnScan() {
        var held = ScreenshotWatcher.HeldRenames()
        held.hold([(from: "a.png", to: "b.png")], scan: 2, undelivered: [])
        let early = delivered(&held, through: 1, present: ["a.png"], current: ["a.png"])
        XCTAssertEqual(early.renames, [])
        XCTAssertEqual(early.removed, [])
        let own = delivered(&held, through: 2, present: ["a.png"], current: ["b.png"])
        XCTAssertEqual(own.renames, ["a.png>b.png"])
        XCTAssertEqual(own.removed, [])
        XCTAssertEqual(delivered(&held, through: 3, present: ["b.png"], current: ["b.png"]).renames, [])
    }

    func testADeliveryTakesTheRenamesAnEarlierDeliveryLeft() {
        var held = ScreenshotWatcher.HeldRenames()
        held.hold([(from: "a.png", to: "b.png")], scan: 1, undelivered: [])
        held.hold([(from: "c.png", to: "d.png")], scan: 2, undelivered: [])
        let both = delivered(&held, through: 2, present: ["a.png", "c.png", "gone.png"], current: ["b.png", "d.png"])
        XCTAssertEqual(both.renames, ["a.png>b.png", "c.png>d.png"])
        XCTAssertEqual(both.removed, ["gone.png"])
    }

    func testARenameOfANameWhoseArrivalIsUndeliveredIsARemoval() {
        var held = ScreenshotWatcher.HeldRenames()
        let kept = held.hold([(from: "a.png", to: "b.png"), (from: "c.png", to: "d.png")], scan: 1, undelivered: ["a.png"])
        XCTAssertEqual(kept.map(\.from), ["c.png"])
        let delivery = delivered(&held, through: 1, present: ["a.png", "c.png"], current: ["b.png", "d.png"])
        XCTAssertEqual(delivery.renames, ["c.png>d.png"])
        XCTAssertEqual(delivery.removed, ["a.png"])
    }
}
