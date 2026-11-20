import XCTest

final class SettingsSyncTests: XCTestCase {
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

    func testAFailedWriteIsLoggedAndALaterReloadKeepsTheAppsChange() {
        var rig = SyncRig()
        rig.appEdits { $0.ui.cardMaxWidth = 300 }
        rig.writesFail = 1
        XCTAssertEqual(rig.writeFires().logLines, ["error write-failed settings.json: the disk is full"])
        XCTAssertEqual(rig.writes, [])
        rig.send(.fileChanged)
        XCTAssertEqual(rig.reloadFires(), [])
        XCTAssertEqual(rig.app.ui.cardMaxWidth, 300)
        XCTAssertEqual(rig.quit().logLines, ["wrote ui.cardMaxWidth=300"])
        XCTAssertEqual(rig.decoded(rig.disk).ui.cardMaxWidth, 300)
    }

    func testAFolderThatCannotBeWrittenKeepsTheWriteFailedUntilAWriteGoesThrough() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-sync-\(UUID().uuidString)")
        let file = folder.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        var rig = SyncRig()
        rig.file = file
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)

        rig.appEdits { $0.recentCount = 12 }
        XCTAssertFalse(rig.sync.lastWriteFailed)
        XCTAssertEqual(rig.writeFires().logLines.map { $0.hasPrefix("error write-failed settings.json:") }, [true])
        XCTAssertTrue(rig.sync.lastWriteFailed)
        rig.appEdits { $0.recentCount = 13 }
        rig.writeFires()
        XCTAssertTrue(rig.sync.lastWriteFailed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        XCTAssertTrue(rig.quit().hasWrite)
        XCTAssertFalse(rig.sync.lastWriteFailed)
        XCTAssertEqual(rig.decoded(try Data(contentsOf: file)).recentCount, 13)
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

    /// The orders of an app change (C), a file edit (E), a reload (R) and a write (W) in which the
    /// write comes after the change.
    static let syncOrders: [String] = {
        func permutations(_ s: [Character]) -> [[Character]] {
            s.count <= 1 ? [s] : s.indices.flatMap { i in
                permutations(Array(s[..<i] + s[(i + 1)...])).map { [s[i]] + $0 }
            }
        }
        return permutations(Array("CERW")).map { String($0) }.filter { $0.firstIndex(of: "C")! < $0.firstIndex(of: "W")! }
    }()
}
