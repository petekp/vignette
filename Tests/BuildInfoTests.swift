import XCTest

final class BuildInfoTests: XCTestCase {
    func testReadsTheStampedKeys() {
        let info = BuildInfo(info: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "12", "VignetteBuild": "a1b2c3d-dirty"])
        XCTAssertEqual(info.description, "0.1.0 (12, a1b2c3d-dirty)")
        XCTAssertEqual(info.build, "a1b2c3d-dirty")
    }

    func testFallsBackWhenUnstamped() {
        XCTAssertEqual(BuildInfo(info: [:]).description, "dev (0, unknown)")
    }
}
