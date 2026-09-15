import XCTest

final class IdentityTests: XCTestCase {
    func testSignatureIsStableAndDistinguishesBundleIds() {
        XCTAssertEqual(Identity.hotKeySignature(for: "com.petepetrash.shotnote"), Identity.hotKeySignature(for: "com.petepetrash.shotnote"))
        XCTAssertNotEqual(Identity.hotKeySignature(for: "com.petepetrash.shotnote"), Identity.hotKeySignature(for: "com.example.shotnote"))
    }

    func testReadsTheFirstUrlScheme() {
        let info: [String: Any] = ["CFBundleURLTypes": [["CFBundleURLName": "x", "CFBundleURLSchemes": ["snap", "other"]]]]
        XCTAssertEqual(Identity.urlScheme(in: info), "snap")
        XCTAssertNil(Identity.urlScheme(in: [:]))
    }
}
