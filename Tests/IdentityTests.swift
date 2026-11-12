import XCTest

final class IdentityTests: XCTestCase {
    private var dir: URL!
    private var person: URL { dir.appendingPathComponent("person") }
    private var temporary: URL { dir.appendingPathComponent("temporary/com.example.vignette") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("IdentityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: person.appendingPathComponent("Library/Application Support/com.example.vignette/x"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("test"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link"), withDestinationURL: person)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func dataHome(home: URL, settings: URL?) -> String {
        Launch.dataHome(bundleID: "com.example.vignette", home: home,
                        environment: settings.map { ["VIGNETTE_SETTINGS": $0.path] } ?? [:],
                        personHome: person, temporary: dir.appendingPathComponent("temporary")).path
    }

    func testSignatureDistinguishesBundleIds() {
        XCTAssertNotEqual(Identity.hotKeySignature(for: "com.petepetrash.vignette"), Identity.hotKeySignature(for: "com.example.vignette"))
    }

    func testReadsTheFirstUrlScheme() {
        let info: [String: Any] = ["CFBundleURLTypes": [["CFBundleURLName": "x", "CFBundleURLSchemes": ["snap", "other"]]]]
        XCTAssertEqual(Identity.urlScheme(in: info), "snap")
        XCTAssertNil(Identity.urlScheme(in: [:]))
    }

    func testARealLaunchKeepsItsDataInItsHomeFolder() {
        XCTAssertEqual(dataHome(home: person, settings: nil), person.path)
        XCTAssertEqual(dataHome(home: dir.appendingPathComponent("moved"), settings: nil), dir.appendingPathComponent("moved").path)
    }

    func testATestLaunchOnThePersonsHomeKeepsItsDataBesideItsSettingsFile() {
        let settings = dir.appendingPathComponent("test/settings.json")
        XCTAssertEqual(dataHome(home: person, settings: settings), dir.appendingPathComponent("test").path)
        XCTAssertEqual(dataHome(home: dir.appendingPathComponent("link"), settings: settings), dir.appendingPathComponent("test").path)
        XCTAssertEqual(dataHome(home: URL(fileURLWithPath: person.path.uppercased()), settings: settings), dir.appendingPathComponent("test").path)
    }

    func testATestLaunchOnAScratchHomeKeepsItsDataInThatHome() {
        let scratch = dir.appendingPathComponent("scratch-home")
        XCTAssertEqual(dataHome(home: scratch, settings: dir.appendingPathComponent("test/settings.json")), scratch.path)
    }

    func testATestLaunchOnAScratchHomeThatLinksIntoThePersonsLibraryKeepsItsDataInTheTemporaryFolder() throws {
        let scratch = dir.appendingPathComponent("scratch-home")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: scratch.appendingPathComponent("Library"),
                                                   withDestinationURL: person.appendingPathComponent("Library"))
        XCTAssertEqual(dataHome(home: scratch, settings: dir.appendingPathComponent("test/settings.json")), temporary.path)
    }

    func testATestLaunchOnThePersonsHomeWithARelativeOrRootSettingsFileKeepsItsDataInTheTemporaryFolder() {
        for settings in ["settings.json", "/settings.json"] {
            let folder = Launch.dataHome(bundleID: "com.example.vignette", home: person, environment: ["VIGNETTE_SETTINGS": settings],
                                         personHome: person, temporary: dir.appendingPathComponent("temporary"))
            XCTAssertEqual(folder.path, temporary.path, settings)
        }
    }

    func testATestLaunchNeverGetsThePersonsOwnFoldersWhereverItsSettingsFileIs() {
        let own = "Library/Application Support/com.example.vignette"
        let settingsFiles = [
            person.appendingPathComponent("settings.json"),
            person.appendingPathComponent("\(own)/x/settings.json"),
            person.appendingPathComponent("Library/Caches/com.example.vignette/settings.json"),
            dir.appendingPathComponent("link/settings.json"),
            dir.appendingPathComponent("link/\(own)/not-made-yet/settings.json"),
        ]
        for settings in settingsFiles {
            XCTAssertEqual(dataHome(home: person, settings: settings), temporary.path, settings.path)
        }
    }
}
