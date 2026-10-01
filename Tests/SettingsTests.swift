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
    func testAgentSkillStartsUnaskedAndOnlyRecordsThatTheOfferWasMade() throws {
        XCTAssertEqual(SettingsData().agentSkillChoice, .unasked)
        var odd = SettingsData()
        odd.agentSkill = "maybe"
        var validated = odd.validated()
        XCTAssertEqual(validated.data.agentSkillChoice, .unasked)
        XCTAssertEqual(validated.corrections, ["agentSkill \"maybe\" -> \"unasked\""])

        // `on` used to install at every launch. Disk says what is installed now, so a file that
        // still holds it is read as an offer already made.
        var older = SettingsData()
        older.agentSkill = "on"
        validated = older.validated()
        XCTAssertEqual(validated.data.agentSkillChoice, .off)
        XCTAssertEqual(validated.corrections, ["agentSkill \"on\" -> \"off\""])
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

    /// A folder Vignette can't write: the launch says so and runs read-only, rather than logging a
    /// file it never made and starting over as a first launch every time.
    @MainActor
    func testAFileThatCannotBeCreatedIsReadOnlyWithANotice() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        let boot = Settings.bootstrap(at: file)
        XCTAssertTrue(boot.readOnly)
        XCTAssertEqual(boot.notice?.title, "Settings can't be saved")
        XCTAssertFalse(boot.log.contains { $0.hasPrefix("created") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
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
    func testFileHoldsOnlyTheUIValuesThatDiffer() throws {
        try write(#"{"version": 2, "ui": {"cardMaxWidth": 300, "cardMaxHeight": \#(UITweaks().cardMaxHeight)}}"#)
        let boot = Settings.bootstrap(at: file)
        XCTAssertEqual(boot.data.ui.cardMaxWidth, 300)
        XCTAssertEqual(try json()["ui"] as? [String: Double], ["cardMaxWidth": 300])
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
    func testMigrateFromVersion1DropsTheOldDefaultsAndKeepsChoices() throws {
        try write(#"{"version": 1, "ui": {"newTextSize": 24, "textWeight": 700, "slideInDuration": 0.75, "cardMaxWidth": 208, "slideInCurve": "spring", "motion": 0.5}}"#)
        guard case .loaded(let loaded) = Settings.load(file) else { return XCTFail("a version 1 file loads") }
        XCTAssertEqual(loaded.data.ui.newTextSize, UITweaks().newTextSize, "0.1.1's default is not a choice")
        XCTAssertEqual(loaded.data.ui.slideInDuration, UITweaks().slideInDuration)
        XCTAssertEqual(loaded.data.ui.cardMaxWidth, UITweaks().cardMaxWidth, "a default changed after 0.1.1 still moves")
        XCTAssertEqual(loaded.data.ui.textWeight, 700, "a value 0.1.1 did not default to is a choice")
        XCTAssertEqual(loaded.data.ui.motion, 0.5)
        let two = Settings.migrate(["version": 2, "ui": ["newTextSize": 24]]).json["ui"] as? [String: Any]
        XCTAssertEqual(two?["newTextSize"] as? Int, 24, "a version 2 file's values are all choices")
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
        d.sendInstructions = "Answer\nwith a drawing\t "
        d.ui.agentColor = "indigo"
        d.ui.textFont = "No Such Family"
        let (fixed, notes) = d.validated()
        XCTAssertEqual(fixed.recentCount, 1000)
        XCTAssertEqual(fixed.screenshotsFolder, "~/Desktop")
        XCTAssertEqual(fixed.ui.slideInCurve, "spring")
        XCTAssertEqual(fixed.ui.backdropBands, 1)
        XCTAssertEqual(fixed.ui.hoverScale, UITweaks().hoverScale)
        XCTAssertEqual(fixed.sendInstructions, "Answer with a drawing", "herdr submits the line with Return")
        XCTAssertEqual(fixed.ui.agentColor, "#364fc7")
        XCTAssertEqual(fixed.ui.textFont, "rounded")
        XCTAssertEqual(notes.count, 8, notes.joined(separator: "; "))
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
