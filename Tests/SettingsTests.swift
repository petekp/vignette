import XCTest

final class SettingsTests: XCTestCase {
    private var dir: URL!
    private var file: URL { dir.appendingPathComponent("settings.json") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private func write(_ text: String) throws {
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    private func json() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }

    // MARK: load

    @MainActor
    func testMissingFileIsMissingNotInvalid() {
        guard case .missing = Settings.load(file) else { return XCTFail("expected .missing") }
    }

    @MainActor
    func testPartialFileKeepsDefaultsForMissingKeys() throws {
        try write(#"{"recentCount": 7, "ui": {"cardMaxWidth": 300}}"#)
        guard case .loaded(let loaded) = Settings.load(file) else { return XCTFail("expected .loaded") }
        XCTAssertEqual(loaded.data.recentCount, 7)
        XCTAssertEqual(loaded.data.ui.cardMaxWidth, 300)
        XCTAssertEqual(loaded.data.ui.cardMaxHeight, UITweaks().cardMaxHeight)
        XCTAssertEqual(loaded.data.recentHotkey, SettingsData().recentHotkey)
    }

    @MainActor
    func testAgentSkillStartsUnaskedAndAnUnknownWordIsClamped() throws {
        XCTAssertEqual(SettingsData().agentSkillChoice, .unasked)
        try write(#"{"agentSkill": "on"}"#)
        guard case .loaded(let loaded) = Settings.load(file) else { return XCTFail("expected .loaded") }
        XCTAssertEqual(loaded.data.agentSkillChoice, .on)
        var odd = SettingsData()
        odd.agentSkill = "maybe"
        let validated = odd.validated()
        XCTAssertEqual(validated.data.agentSkillChoice, .unasked)
        XCTAssertEqual(validated.corrections, ["agentSkill \"maybe\" -> \"unasked\""])
    }

    @MainActor
    func testSyntaxErrorIsInvalid() throws {
        try write(#"{"recentCount": 7"#)
        guard case .invalid(let reason) = Settings.load(file) else { return XCTFail("expected .invalid") }
        XCTAssertFalse(reason.isEmpty)
    }

    @MainActor
    func testWrongTypeIsInvalid() throws {
        try write(#"{"recentCount": "many"}"#)
        guard case .invalid = Settings.load(file) else { return XCTFail("expected .invalid") }
    }

    // MARK: bootstrap

    @MainActor
    func testInvalidFileIsSetAsideNotOverwritten() throws {
        let bad = #"{"recentCount": 7"#
        try write(bad)
        let boot = Settings.bootstrap(at: file)
        let aside = dir.appendingPathComponent("settings.json.invalid")
        XCTAssertEqual(try String(contentsOf: aside, encoding: .utf8), bad)
        XCTAssertNotNil(boot.notice)
        XCTAssertTrue(boot.log.contains { $0.hasPrefix("error settings-invalid") })
        XCTAssertEqual((try json())["version"] as? Int, Settings.currentVersion, "a fresh file replaces the bad one")
    }

    @MainActor
    func testMissingFileIsCreatedWithAppleOriginal() throws {
        let boot = Settings.bootstrap(at: file)
        XCTAssertNotNil(boot.data.appleOriginal)
        XCTAssertTrue(boot.log.contains { $0.hasPrefix("created") })
        XCTAssertNotNil((try json())["appleOriginal"])
    }

    @MainActor
    func testNegativeCountIsClampedInMemoryAndLogged() throws {
        try write(#"{"recentCount": -1, "ui": {"backdropWidth": 0, "cardShadowOpacity": 3}}"#)
        let boot = Settings.bootstrap(at: file)
        XCTAssertEqual(boot.data.recentCount, 0)
        XCTAssertEqual(boot.data.ui.backdropWidth, 1)
        XCTAssertEqual(boot.data.ui.cardShadowOpacity, 1)
        let clamps = boot.log.filter { $0.hasPrefix("warning clamped") }
        XCTAssertEqual(clamps.count, 3, clamps.joined(separator: "; "))
        XCTAssertFalse(boot.readOnly)
    }

    @MainActor
    func testMissingKeysAreFilledInOnDisk() throws {
        try write(#"{"recentCount": 7}"#)
        _ = Settings.bootstrap(at: file)
        let j = try json()
        XCTAssertEqual(j["recentCount"] as? Int, 7)
        XCTAssertNotNil(j["ui"])
        XCTAssertEqual(j["version"] as? Int, Settings.currentVersion)
    }

    @MainActor
    func testFileWithoutVersionIsMigratedAndRewritten() throws {
        try write(#"{"recentCount": 7}"#)
        let boot = Settings.bootstrap(at: file)
        XCTAssertTrue(boot.log.contains("migrated from version 0 to \(Settings.currentVersion)"))
        XCTAssertEqual((try json())["version"] as? Int, Settings.currentVersion)
    }

    @MainActor
    func testNewerVersionIsReadOnly() throws {
        let newer = #"{"version": \#(Settings.currentVersion + 1), "recentCount": 7, "futureKey": true}"#
        try write(newer)
        let boot = Settings.bootstrap(at: file)
        XCTAssertTrue(boot.readOnly)
        XCTAssertEqual(boot.data.recentCount, 7)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), newer, "a newer file is never rewritten")
    }

    // MARK: migrate

    @MainActor
    func testMigrateStampsCurrentVersion() {
        let out = Settings.migrate(["recentCount": 3])
        XCTAssertEqual(out.from, 0)
        XCTAssertEqual(out.json["version"] as? Int, Settings.currentVersion)
        XCTAssertEqual(out.json["recentCount"] as? Int, 3)
    }

    @MainActor
    func testMigrateReadsAnyNumericVersion() throws {
        XCTAssertEqual(Settings.migrate(["version": 1.0]).from, 1)
        try write(#"{"version": "1"}"#)
        guard case .invalid = Settings.load(file) else { return XCTFail("a non-numeric version is invalid, not version 0") }
    }

    @MainActor
    func testMigrateLeavesNewerFilesAlone() {
        let out = Settings.migrate(["version": 99])
        XCTAssertEqual(out.from, 99)
        XCTAssertEqual(out.json["version"] as? Int, 99)
    }

    // MARK: validated

    func testValidatedLeavesGoodDataAlone() {
        let (data, notes) = SettingsData().validated()
        XCTAssertEqual(data, SettingsData())
        XCTAssertEqual(notes, [])
    }

    func testValidatedRepairsEachKind() {
        var d = SettingsData()
        d.recentCount = 5000
        d.screenshotsFolder = "  "
        d.ui.slideInCurve = "bounce"
        d.ui.backdropBands = 0
        d.ui.hoverScale = .nan
        let (fixed, notes) = d.validated()
        XCTAssertEqual(fixed.recentCount, 1000)
        XCTAssertEqual(fixed.screenshotsFolder, "~/Desktop")
        XCTAssertEqual(fixed.ui.slideInCurve, "spring")
        XCTAssertEqual(fixed.ui.backdropBands, 1)
        XCTAssertEqual(fixed.ui.hoverScale, UITweaks().hoverScale)
        XCTAssertEqual(notes.count, 5, notes.joined(separator: "; "))
    }

    @MainActor
    func testLaunchAtLoginIsOffUnlessTheFileSaysSo() throws {
        try write(#"{"recentCount": 7}"#)
        guard case .loaded(let off) = Settings.load(file) else { return XCTFail("expected .loaded") }
        XCTAssertFalse(off.data.launchAtLogin, "a file from before the setting existed must not register a login item")
        try write(#"{"launchAtLogin": true}"#)
        guard case .loaded(let on) = Settings.load(file) else { return XCTFail("expected .loaded") }
        XCTAssertTrue(on.data.launchAtLogin)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(on.data)) as? [String: Any]
        XCTAssertEqual(encoded?["launchAtLogin"] as? Bool, true, "the file key is the contract")
    }

    func testDefaultsAreWithinTheirBounds() {
        // A default outside its bound would be clamped on load, so a fresh install would not render the tuned UI.
        var d = SettingsData()
        d.ui = UITweaks()
        XCTAssertEqual(d.validated().data.ui, UITweaks())
    }

    func testEveryTweakHasABound() {
        let encoded = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(UITweaks())) as! [String: Any]
        let doubles = Set(encoded.filter { $0.value is Double || $0.value is Int }.keys).subtracting(["backdropBands"])
        XCTAssertEqual(Set(UITweaks.bounds.map(\.name)), Set(doubles))
    }
}
