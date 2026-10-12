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
        try write(#"{"version": 2, "ui": {"cardMaxWidth": 300, "cardMaxHeight": \#(UITweaks().cardMaxHeight), "dimOpacity": \#(UITweaks().dimOpacity.nextUp)}}"#)
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

    // MARK: merge

    @MainActor
    func testAnEditToTheFileAndAChangeInTheAppBothSurvive() throws {
        let base = SettingsData()
        var app = base
        app.screenshotsFolder = "~/Pictures"   // as following macOS's save location does
        app.ui.cardMaxWidth = 300
        app.recentCount = 12
        var file = base
        file.ui.motion = 0                      // an edit made to the file before the app wrote
        file.recentCount = 7
        let merged = try XCTUnwrap(Settings.merged(base: base, app: app, file: file))
        XCTAssertEqual(merged.data.screenshotsFolder, "~/Pictures")
        XCTAssertEqual(merged.data.ui.cardMaxWidth, 300)
        XCTAssertEqual(merged.data.ui.motion, 0)
        XCTAssertEqual(merged.data.recentCount, 7, "where both changed a key, the file's value stands")
        XCTAssertEqual(merged.conflicts, ["recentCount"])
    }

    func testEveryTweakHasABound() {
        let encoded = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(UITweaks())) as! [String: Any]
        let doubles = Set(encoded.filter { $0.value is Double || $0.value is Int }.keys).subtracting(["backdropBands"])
        XCTAssertEqual(Set(UITweaks.bounds.map(\.name)), Set(doubles))
    }

    // MARK: sync

    /// Catches a write that stops recording its own bytes, so every write echoes back as a file
    /// edit: a spurious `onChange`, and Apple's keys pushed again. Also catches a `wrote` line for a
    /// write that changed no `ui` value.
    func testAWriteComesAfterTheDelayAndItsOwnEchoAppliesNothing() {
        var rig = SyncRig()
        XCTAssertEqual(rig.appEdits { $0.recentCount = 12 }, [.scheduleWrite(after: SettingsSync.writeDelay)])
        XCTAssertEqual(rig.writeFires().logLines, [])
        XCTAssertEqual(rig.writes.count, 1)
        XCTAssertEqual(rig.decoded(rig.disk).recentCount, 12)
        XCTAssertEqual(rig.send(.fileChanged), [.scheduleReload(after: SettingsSync.reloadDelay)])
        XCTAssertEqual(rig.reloadFires(), [])
    }

    /// Catches a write that does not take in the file first (C E W R): it replaces the file's edit,
    /// and its echo is then skipped as the app's own bytes.
    func testAnAppChangeAndAFileEditOnOtherKeysBothSurviveInEveryOrder() {
        for order in Self.syncOrders {
            var rig = SyncRig()
            rig.play(order, app: { $0.recentCount = 12 }, file: { $0.ui.motion = 0.5 })
            rig.reloadFires()
            rig.quit()
            for d in [rig.app, rig.decoded(rig.disk)] {
                XCTAssertEqual(d.recentCount, 12, order)
                XCTAssertEqual(d.ui.motion, 0.5, order)
            }
            XCTAssertFalse(rig.log.contains { $0.hasPrefix("kept the file's") }, order)
        }
    }

    /// Catches the conflict rule flipping to the app's value, a conflict that is no longer logged,
    /// and a conflict logged where the two changes were not made at the same time.
    func testWhereBothChangedAKeyTheFileWinsAndSaysSo() {
        // Where the app had written before the file was edited, the reload finds nothing changed in
        // the app since, so it takes the file's value without a merge. R E C W: the reload ran
        // before the edit, so the write's take-in finds both changed. E R C W: the reload took in
        // the file's 7 before the app changed, so the app's 12 is the later edit and is written.
        let appWins: Set<String> = ["ERCW"]
        let fileWinsQuietly: Set<String> = ["CRWE", "CWER", "CWRE", "RCWE"]
        let fileWinsSaying: Set<String> = ["CERW", "CEWR", "CREW", "ECRW", "ECWR", "RCEW", "RECW"]
        XCTAssertEqual(appWins.union(fileWinsQuietly).union(fileWinsSaying), Set(Self.syncOrders))
        for order in Self.syncOrders {
            var rig = SyncRig()
            rig.play(order, app: { $0.recentCount = 12 }, file: { $0.recentCount = 7 })
            rig.reloadFires()
            rig.quit()
            let expected = appWins.contains(order) ? 12 : 7
            XCTAssertEqual(rig.app.recentCount, expected, order)
            XCTAssertEqual(rig.decoded(rig.disk).recentCount, expected, order)
            let said = rig.log.filter { $0 == "kept the file's recentCount over this app's change" }.count
            XCTAssertEqual(said, fileWinsSaying.contains(order) ? 1 : 0, order)
        }
    }

    /// Catches a merge base set to the merged data rather than the file's: the second reload would
    /// then find nothing changed in the app, skip the merge, and lose the app's 12. Also catches a
    /// `wrote` line that lists the file's `ui` edits, which testers merge back as their own.
    func testAfterAReloadTheMergeBaseIsTheFilesData() {
        var rig = SyncRig()
        rig.appEdits { $0.recentCount = 12; $0.ui.cardMaxWidth = 300 }
        rig.fileEdits { $0.ui.motion = 0.5 }
        rig.reloadFires()
        rig.fileEdits { $0.windowShadow = false }
        rig.reloadFires()
        XCTAssertEqual(rig.writeFires().logLines, ["wrote ui.cardMaxWidth=300"])
        let written = rig.decoded(rig.writes.last)
        XCTAssertEqual(written.recentCount, 12)
        XCTAssertEqual(written.ui.cardMaxWidth, 300)
        XCTAssertEqual(written.ui.motion, 0.5)
        XCTAssertFalse(written.windowShadow)
    }

    /// Catches a write that takes the take-in's merged data, or the app's data from before the take-in,
    /// rather than the app's data after it: an `onChange` handler's `update` during the take-in would
    /// then be missing from the file until one more write.
    func testAnUpdateMadeDuringAWritesTakeInIsInThatWrite() {
        var rig = SyncRig()
        rig.appEdits { $0.recentCount = 12 }
        rig.fileEdits { $0.ui.motion = 0.5 }
        rig.onApply = { $0.screenshotsFolder = "~/Nested" }
        let effects = rig.writeFires()
        XCTAssertEqual(rig.writes.count, 1)
        let written = rig.decoded(rig.writes.last)
        XCTAssertEqual(written.recentCount, 12)
        XCTAssertEqual(written.ui.motion, 0.5)
        XCTAssertEqual(written.screenshotsFolder, "~/Nested")
        XCTAssertTrue(rig.writeTimer, "the nested change schedules its own write")
        let scheduled = effects.firstIndex(of: .scheduleWrite(after: SettingsSync.writeDelay))
        let write = effects.firstIndex { if case .write = $0 { true } else { false } }
        XCTAssertNotNil(scheduled)
        XCTAssertLessThan(scheduled ?? .max, write ?? .max, "the nested update is reduced before the write")
    }

    /// Catches a write to a file the launch decided not to touch, read-only blocking reloads, and a
    /// newer file later replacing the reason the launch gave.
    func testNothingIsWrittenWhileReadOnlyButFileEditsStillArrive() {
        var rig = SyncRig(readOnly: true, reason: "~/.config cannot be written")
        let disk = rig.disk
        rig.appEdits { $0.screenshotsFolder = "~/Pictures" }
        for effects in [rig.writeFires(), rig.quit()] {
            XCTAssertFalse(effects.hasWrite)
            XCTAssertEqual(effects.logLines,
                           ["warning not written: ~/.config cannot be written"])
        }
        XCTAssertEqual(rig.disk, disk)
        rig.fileEdits { $0.recentCount = 7 }
        rig.reloadFires()
        XCTAssertEqual(rig.app.recentCount, 7)
        XCTAssertEqual(rig.app.screenshotsFolder, "~/Pictures")

        rig.put(#"{"version": \#(Settings.currentVersion + 1), "format": "jpg"}"#)
        rig.reloadFires()
        XCTAssertEqual(rig.app.format, "jpg")
        XCTAssertFalse(rig.log.contains { $0.contains("is newer than") })
        rig.appEdits { $0.recentCount = 12 }
        XCTAssertEqual(rig.writeFires().logLines, ["warning not written: ~/.config cannot be written"])
    }

    /// Catches a newer build's keys dropped by a write already pending, and a read-only check made
    /// before the take-in rather than inside the write.
    func testAFileFromANewerVersionMakesTheAppReadOnlyMidRun() {
        let version = Settings.currentVersion + 1
        let newer = #"{"version": \#(version), "format": "jpg"}"#
        let warning = "warning file version \(version) is newer than this build's \(Settings.currentVersion); not writing to it"
        var rig = SyncRig()
        rig.appEdits { $0.recentCount = 12 }
        rig.put(newer)
        rig.reloadFires()
        XCTAssertEqual(rig.log.filter { $0 == warning }.count, 1)
        XCTAssertEqual(rig.app.format, "jpg")
        XCTAssertEqual(rig.app.recentCount, 12, "the app's change is kept in memory")
        XCTAssertTrue(rig.sync.readOnly)
        for effects in [rig.writeFires(), rig.quit()] {
            XCTAssertFalse(effects.hasWrite)
            XCTAssertTrue(effects.contains(.log("warning not written: the file is from a newer version")))
        }
        XCTAssertEqual(rig.disk, Data(newer.utf8))

        // The newer file arrives with the app's write already due and no reload before it.
        var pending = SyncRig()
        pending.appEdits { $0.recentCount = 12 }
        pending.put(newer)
        let effects = pending.writeFires()
        XCTAssertTrue(effects.contains(.log(warning)))
        XCTAssertTrue(effects.contains { if case .apply(let d, _) = $0 { d.format == "jpg" } else { false } })
        XCTAssertFalse(effects.hasWrite)
        XCTAssertEqual(effects.last, .log("warning not written: the file is from a newer version"))
        XCTAssertEqual(pending.disk, Data(newer.utf8))
    }

    /// Catches a quit that loses an edit made in the last 0.15 s, and a quit that rewrites a file
    /// the app never changed. Also catches a quit that skips its write because the timer's write
    /// already ran, and a second quit that writes again.
    func testAFlushTakesInAPendingFileEditBeforeItWrites() {
        var rig = SyncRig()
        rig.appEdits { $0.ui.cardMaxWidth = 300 }
        rig.fileEdits { $0.recentCount = 7 }
        let effects = rig.quit()
        XCTAssertEqual(effects.first, .cancelWrite)
        XCTAssertTrue(effects.contains { if case .apply(let d, _) = $0 { d.recentCount == 7 } else { false } })
        let written = rig.decoded(rig.writes.last)
        XCTAssertEqual(written.ui.cardMaxWidth, 300)
        XCTAssertEqual(written.recentCount, 7)
        XCTAssertEqual(rig.reloadFires(), [])

        var untouched = SyncRig()
        untouched.fileEdits { $0.recentCount = 7 }
        XCTAssertEqual(untouched.quit(), [])

        var timed = SyncRig()
        timed.appEdits { $0.recentCount = 12 }
        timed.writeFires()
        XCTAssertTrue(timed.quit().hasWrite)
        XCTAssertEqual(timed.quit(), [])
    }

    /// Catches the migration repeating on every reload, and a pasted file erasing the record that
    /// restore-apple-defaults needs. Also catches a stamp that writes the merged data, which would
    /// carry the app's pending change into the merge base, so its write would no longer log it.
    func testAPreVersionFileIsStampedOnceAndKeepsTheAppsAppleOriginal() {
        var rig = SyncRig()
        rig.appEdits { $0.ui.cardMaxWidth = 300 }
        rig.put(#"{"recentCount": 7}"#)
        let effects = rig.reloadFires()
        XCTAssertEqual(effects.count, 3, "\(effects)")
        XCTAssertEqual(effects.first, .log("migrated from version 0 to \(Settings.currentVersion)"))
        guard effects.count == 3, case .apply(let applied, "file") = effects[1], case .write(let raw) = effects[2] else {
            return XCTFail("expected the log, the apply and the stamp: \(effects)")
        }
        XCTAssertEqual(applied.recentCount, 7)
        XCTAssertEqual(applied.ui.cardMaxWidth, 300)
        XCTAssertEqual(applied.appleOriginal, SyncRig.original)
        let stamped = rig.decoded(raw)
        XCTAssertEqual(stamped.version, Settings.currentVersion)
        XCTAssertEqual(stamped.ui.cardMaxWidth, UITweaks().cardMaxWidth)
        XCTAssertEqual(stamped.appleOriginal, SyncRig.original)
        XCTAssertEqual(rig.reloadFires(), [])
        XCTAssertEqual(rig.writeFires().logLines, ["wrote ui.cardMaxWidth=300"])
        XCTAssertEqual(rig.decoded(rig.disk).ui.cardMaxWidth, 300)
    }

    /// Catches values outside their bounds reaching the app, and a take-in that does not record the
    /// bytes it took, which logs the clamp again at every later reload and every write. Also catches
    /// the app's `appleOriginal` replacing one the file carries.
    func testAClampedValueIsLoggedAndTheAppTakesTheClampedValue() {
        var rig = SyncRig()
        rig.put(#"{"version": \#(Settings.currentVersion), "recentCount": 5000}"#)
        let effects = rig.reloadFires()
        XCTAssertTrue(rig.log.contains("warning clamped recentCount 5000 -> 1000"))
        XCTAssertEqual(rig.app.recentCount, 1000)
        XCTAssertEqual(rig.app.appleOriginal, SyncRig.original)
        XCTAssertFalse(effects.hasWrite)
        XCTAssertEqual(rig.reloadFires(), [])
        rig.appEdits { $0.recentCount = 12 }
        XCTAssertEqual(rig.writeFires().logLines, [])

        let moved = AppleOriginal(location: "~/Pictures", showThumbnail: false, disableShadow: true, type: "jpg")
        rig.fileEdits { $0.appleOriginal = moved }
        rig.reloadFires()
        XCTAssertEqual(rig.app.appleOriginal, moved)
    }

    /// Catches a broken hand edit resetting the app's settings, and a failed read taken for an
    /// empty file.
    func testAFileThatDoesNotParseKeepsTheSettingsAndTheNextWriteReplacesIt() {
        var rig = SyncRig()
        let before = rig.app
        rig.put(#"{"recentCount": 7"#)
        let effects = rig.reloadFires()
        XCTAssertEqual(effects.count, 1, "\(effects)")
        guard case .log(let line) = effects.first else { return XCTFail("expected one log line: \(effects)") }
        XCTAssertTrue(line.hasPrefix("error settings-invalid file changed but does not parse; keeping current settings:"), line)
        XCTAssertEqual(rig.app, before)
        XCTAssertEqual(rig.send(.reloadDue(file: nil, app: rig.app)), [])
        rig.appEdits { $0.recentCount = 12 }
        rig.writeFires()
        XCTAssertEqual(rig.decoded(rig.disk), rig.app)
        XCTAssertEqual(rig.app.recentCount, 12)
    }

    /// Plays random app edits, file edits, timers, quits, pre-version, invalid, deleted and newer
    /// files, and checks that nothing is written while read-only, that nothing is clamped, that a
    /// take-in says a conflict for exactly the keys both sides changed since the file and the app
    /// last agreed, and that every edit ends up in the app and the file unless a later edit to that
    /// key, or a conflict the file won, replaced it. Catches any reordering of the take-in, the
    /// write, the merge base or the echo skip that loses an edit from either side or hands it to
    /// the other, and any write after read-only.
    func testRandomSequencesKeepTheInvariants() {
        var conflicts = 0, stamps = 0, readOnlyRuns = 0, invalidTakeIns = 0, flushesOverReload = 0
        seeds: for seed in 0..<100 {
            var rng = SeededGenerator(seed: UInt64(seed))
            var rig = SyncRig()
            var expected = SyncKey.values(in: rig.app)
            // What the file and the app last agreed on: the bytes last taken in or written.
            var base = expected
            var appN = 31, fileN = 32
            var trace: [(step: String, effects: [SettingsSync.Effect], readOnly: Bool)] = []
            func fail(_ message: String) -> Bool {
                let lines = trace.map { "\($0.step) -> \($0.effects.map(SyncKey.brief))\($0.readOnly ? " [read-only]" : "")" }
                XCTFail("\(message) (seed \(seed))\n" + lines.joined(separator: "\n"))
                return true
            }
            // Runs one step and checks its effects against the app and the file as they were before
            // it, which is what a take-in reads. nil when a check failed.
            func step(_ name: String, _ run: (inout SyncRig) -> [SettingsSync.Effect]) -> [SettingsSync.Effect]? {
                let app = SyncKey.values(in: rig.app)
                let disk = rig.disk
                let effects = run(&rig)
                trace.append((name, effects, rig.sync.readOnly))
                if rig.sync.readOnly, effects.hasWrite, fail("nothing is written while read-only") { return nil }
                var said: Set<SyncKey> = []
                for effect in effects {
                    switch effect {
                    case .log(let line):
                        if line.contains("warning clamped"), fail("nothing is clamped: \(line)") { return nil }
                        if line.hasPrefix("migrated from") { stamps += 1 }
                        if line.hasPrefix("error settings-invalid") { invalidTakeIns += 1 }
                        guard line.hasPrefix("kept the file's ") else { continue }
                        let name = line.dropFirst("kept the file's ".count).prefix { $0 != " " }
                        guard let key = SyncKey(rawValue: String(name)) else {
                            _ = fail("a conflict on a key nobody edited: \(name)")
                            return nil
                        }
                        said.insert(key)
                        conflicts += 1
                    case .apply(_, "file"):
                        guard let file = rig.parsed(disk).map(SyncKey.values) else {
                            _ = fail("a take-in with no file")
                            return nil
                        }
                        let both = Set(SyncKey.allCases.filter {
                            app[$0] != base[$0] && file[$0] != base[$0] && app[$0] != file[$0]
                        })
                        if said != both, fail("conflicts said \(said), both sides changed \(both)") { return nil }
                        for key in both { expected[key] = file[key] }
                        said = []
                        base = file
                    case .write(let raw):
                        base = SyncKey.values(in: rig.decoded(raw))
                    default:
                        break
                    }
                }
                if !said.isEmpty, fail("a conflict with no take-in") { return nil }
                return effects
            }
            for _ in 0..<40 {
                let effects: [SettingsSync.Effect]?
                if Int.random(in: 0..<60, using: &rng) == 0 {
                    effects = step("newer file") { rig in rig.putJSON { json in json["version"] = Settings.currentVersion + 1 } }
                } else {
                    var pick: Int
                    repeat { pick = Int.random(in: 0..<16, using: &rng) } while
                        (pick >= 9 && pick < 11 && !rig.reloadTimer) || (pick >= 11 && pick < 13 && !rig.writeTimer)
                    switch pick {
                    case 0..<5:
                        let key = [SyncKey.recentCount, .cardMaxWidth, .screenshotsFolder].randomElement(using: &rng)!
                        let n = appN
                        appN += 2
                        expected[key] = key.value(of: n)
                        effects = step("app \(key.rawValue)=\(n)") { rig in rig.appEdits { key.set(n, in: &$0) } }
                    case 5..<9:
                        let key = [SyncKey.recentCount, .cardMaxWidth, .motion].randomElement(using: &rng)!
                        let n = fileN
                        fileN += 2
                        expected[key] = key.value(of: n)
                        effects = step("file \(key.rawValue)=\(n)") { rig in rig.fileEdits { key.set(n, in: &$0) } }
                    case 9..<11:
                        effects = step("reload") { rig in rig.reloadFires() }
                    case 11..<13:
                        effects = step("write") { rig in rig.writeFires() }
                    case 13:
                        let reloadPending = rig.reloadTimer
                        effects = step("quit") { rig in rig.quit() }
                        if reloadPending, effects?.hasWrite == true { flushesOverReload += 1 }
                    case 14:
                        effects = step("pre-version file") { rig in rig.putJSON { json in json["version"] = nil } }
                    default:
                        let broken = Bool.random(using: &rng)
                        effects = step(broken ? "invalid file" : "deleted file") { rig in
                            let reload = rig.reloadFires()
                            rig.disk = broken ? Data("{".utf8) : nil
                            return reload + rig.send(.fileChanged)
                        }
                    }
                }
                if effects == nil { break seeds }
            }
            if rig.reloadTimer, step("drain: reload", { rig in rig.reloadFires() }) == nil { break seeds }
            if rig.sync.readOnly {
                readOnlyRuns += 1
                for key in SyncKey.allCases where key.value(in: rig.app) != expected[key] {
                    if fail("app \(key.rawValue) is \(key.value(in: rig.app)), expected \(expected[key] ?? "")") { break seeds }
                }
                continue
            }
            rig.appEdits { _ in }
            if !rig.writeTimer, fail("an app change schedules a write") { break seeds }
            if step("drain: write", { rig in rig.writeFires() }) == nil { break seeds }
            if !rig.reloadTimer, fail("the watcher sees the app's write") { break seeds }
            let echo = rig.reloadFires()
            if echo != [], fail("the last write's echo applies nothing: \(echo.map(SyncKey.brief))") { break seeds }
            let written = rig.decoded(rig.disk)
            for key in SyncKey.allCases {
                if key.value(in: rig.app) != expected[key],
                   fail("app \(key.rawValue) is \(key.value(in: rig.app)), expected \(expected[key] ?? "")") { break seeds }
                if key.value(in: written) != expected[key],
                   fail("file \(key.rawValue) is \(key.value(in: written)), expected \(expected[key] ?? "")") { break seeds }
            }
        }
        XCTAssertGreaterThan(conflicts, 20, "conflicts are part of the mix")
        XCTAssertGreaterThan(stamps, 20, "pre-version files are part of the mix")
        XCTAssertGreaterThan(readOnlyRuns, 20, "runs that go read-only are part of the mix")
        XCTAssertGreaterThan(invalidTakeIns, 20, "invalid files are part of the mix")
        XCTAssertGreaterThan(flushesOverReload, 20, "flushes with a reload pending are part of the mix")
    }

    /// The orders of an app change (C), a file edit (E), a reload (R) and a write (W) in which the
    /// write comes after the change.
    private static let syncOrders: [String] = {
        func permutations(_ s: [Character]) -> [[Character]] {
            s.count <= 1 ? [s] : s.indices.flatMap { i in
                permutations(Array(s[..<i] + s[(i + 1)...])).map { [s[i]] + $0 }
            }
        }
        return permutations(Array("CERW")).map { String($0) }.filter { $0.firstIndex(of: "C")! < $0.firstIndex(of: "W")! }
    }()
}

/// The keys the random sequences edit. The app edits the first three and the file all but the
/// folder, each with a fresh number: odd from the app, even from the file, all inside their bounds
/// and none a default of 0.1.1, which a migration would drop.
private enum SyncKey: String, CaseIterable {
    case recentCount, cardMaxWidth = "ui.cardMaxWidth", screenshotsFolder, motion = "ui.motion"

    func set(_ n: Int, in d: inout SettingsData) {
        switch self {
        case .recentCount: d.recentCount = n
        case .cardMaxWidth: d.ui.cardMaxWidth = Double(300 + n)
        case .screenshotsFolder: d.screenshotsFolder = "~/s\(n)"
        case .motion: d.ui.motion = Double(n) / 1000
        }
    }

    func value(of n: Int) -> String {
        var d = SettingsData()
        set(n, in: &d)
        return value(in: d)
    }

    func value(in d: SettingsData) -> String {
        switch self {
        case .recentCount: "\(d.recentCount)"
        case .cardMaxWidth: "\(d.ui.cardMaxWidth)"
        case .screenshotsFolder: d.screenshotsFolder
        case .motion: "\(d.ui.motion)"
        }
    }

    static func values(in d: SettingsData) -> [SyncKey: String] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.value(in: d)) })
    }

    static func describe(_ d: SettingsData) -> String {
        allCases.map { "\($0.rawValue)=\($0.value(in: d))" }.joined(separator: " ")
    }

    /// An effect short enough for a trace.
    static func brief(_ effect: SettingsSync.Effect) -> String {
        switch effect {
        case .apply(let d, let source): return "apply(\(source): \(describe(d)))"
        case .write(let raw):
            guard case .loaded(let loaded) = Settings.parse(raw) else { return "write(invalid)" }
            return "write(\(describe(loaded.data)))"
        default: return "\(effect)"
        }
    }
}

/// Plays `Settings` in memory: the file is `disk` and the timers are two flags. Events pass through
/// an `EventHold` as in `Settings.send`, so an answer, or an edit made inside an `.apply`, is
/// reduced after every effect of the event that led to it.
private struct SyncRig {
    static let original = AppleOriginal(location: "~/Desktop", showThumbnail: true, disableShadow: false, type: "png")

    private let hold = EventHold<SettingsSync.Event>()
    var sync: SettingsSync
    var app: SettingsData
    var disk: Data?
    /// The last bytes on disk that parsed, which a hand edit starts from when the file is broken or gone.
    var lastValid: Data
    var writes: [Data] = []
    var log: [String] = []
    var writeTimer = false
    var reloadTimer = false
    /// An app edit made inside the next `.apply`, as an `onChange` handler that calls `update` makes it.
    var onApply: ((inout SettingsData) -> Void)?

    init(readOnly: Bool = false, reason: String = "") {
        var base = SettingsData()
        base.appleOriginal = Self.original
        let raw = try! Settings.encoder().encode(base)
        app = base
        disk = raw
        lastValid = raw
        sync = SettingsSync(bytes: raw, data: base, readOnly: readOnly, readOnlyReason: reason)
    }

    @discardableResult
    mutating func send(_ event: SettingsSync.Event) -> [SettingsSync.Effect] {
        var all: [SettingsSync.Effect] = []
        let hold = self.hold
        hold.send(event) { event in
            let effects = sync.reduce(event)
            all += effects
            for effect in effects { run(effect) }
        }
        return all
    }

    private mutating func run(_ effect: SettingsSync.Effect) {
        switch effect {
        case .log(let line): log.append(line)
        case .apply(let d, _):
            app = d
            if let edit = onApply {
                onApply = nil
                appEdits(edit)
            }
        case .write(let raw):
            disk = raw
            lastValid = raw
            writes.append(raw)
            reloadTimer = true   // the watcher sees the app's own write
        case .writeAppData: send(.appData(app))
        case .readFileAndFlush: send(.flush(file: disk, app: app))
        case .scheduleWrite: writeTimer = true
        case .cancelWrite: writeTimer = false
        case .scheduleReload: reloadTimer = true
        }
    }

    @discardableResult
    mutating func appEdits(_ change: (inout SettingsData) -> Void) -> [SettingsSync.Effect] {
        change(&app)
        return send(.appChanged)
    }

    /// A hand edit, made over the file as it is, or over its last good bytes when it is broken or gone.
    @discardableResult
    mutating func fileEdits(_ change: (inout SettingsData) -> Void) -> [SettingsSync.Effect] {
        var d = parsed(disk) ?? parsed(lastValid)!
        change(&d)
        let raw = try! Settings.encoder().encode(d)
        disk = raw
        lastValid = raw
        return send(.fileChanged)
    }

    /// A hand edit to the file's JSON itself, for a key `SettingsData` would not write as given.
    @discardableResult
    mutating func putJSON(_ change: (inout [String: Any]) -> Void) -> [SettingsSync.Effect] {
        var json = try! JSONSerialization.jsonObject(with: parsed(disk) != nil ? disk! : lastValid) as! [String: Any]
        change(&json)
        let raw = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        disk = raw
        lastValid = raw
        return send(.fileChanged)
    }

    @discardableResult
    mutating func put(_ json: String) -> [SettingsSync.Effect] {
        disk = Data(json.utf8)
        if parsed(disk) != nil { lastValid = disk! }
        return send(.fileChanged)
    }

    @discardableResult
    mutating func writeFires() -> [SettingsSync.Effect] {
        writeTimer = false
        return send(.writeDue(file: disk, app: app))
    }

    @discardableResult
    mutating func reloadFires() -> [SettingsSync.Effect] {
        reloadTimer = false
        return send(.reloadDue(file: disk, app: app))
    }

    @discardableResult
    mutating func quit() -> [SettingsSync.Effect] {
        send(.quit)
    }

    /// The bytes as the app reads them; `SettingsData()` for bytes that do not parse.
    func decoded(_ raw: Data?) -> SettingsData {
        guard let d = parsed(raw) else {
            XCTFail("the bytes do not parse")
            return SettingsData()
        }
        return d
    }

    func parsed(_ raw: Data?) -> SettingsData? {
        guard let raw, case .loaded(let loaded) = Settings.parse(raw) else { return nil }
        return loaded.data
    }
}

private extension Array where Element == SettingsSync.Effect {
    var hasWrite: Bool { contains { if case .write = $0 { true } else { false } } }
    var logLines: [String] { compactMap { effect -> String? in if case .log(let line) = effect { return line }; return nil } }
}

extension SyncRig {
    /// Plays one of `SettingsTests.syncOrders`.
    mutating func play(_ order: String, app: (inout SettingsData) -> Void, file: (inout SettingsData) -> Void) {
        for step in order {
            switch step {
            case "C": appEdits(app)
            case "E": fileEdits(file)
            case "R": reloadFires()
            default: writeFires()
            }
        }
    }
}
