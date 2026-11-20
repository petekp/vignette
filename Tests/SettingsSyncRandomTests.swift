import XCTest

final class SettingsSyncRandomTests: XCTestCase {
    /// Plays random app edits, file edits, timers, quits, pre-version, invalid, deleted and newer
    /// files, and checks that nothing is written while read-only, that nothing is clamped, that a
    /// take-in says a conflict for exactly the keys both sides changed since the file and the app
    /// last agreed, and that every edit ends up in the app and the file unless a later edit to that
    /// key, or a conflict the file won, replaced it. Catches any reordering of the take-in, the
    /// write, the merge base or the echo skip that loses an edit from either side or hands it to
    /// the other, and any write after read-only.
    func testRandomSequencesKeepTheInvariants() {
        var conflicts = 0, stamps = 0, readOnlyRuns = 0, invalidTakeIns = 0, flushesOverReload = 0, failedWrites = 0
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
                var writing: [SyncKey: String]?
                for effect in effects {
                    switch effect {
                    case .log(let line):
                        if line.contains("warning clamped"), fail("nothing is clamped: \(line)") { return nil }
                        if line.hasPrefix("error write-failed") {
                            writing = nil
                            failedWrites += 1
                        }
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
                        if let written = writing { base = written }
                        writing = nil
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
                        if let written = writing { base = written }
                        writing = SyncKey.values(in: rig.decoded(raw))
                    default:
                        break
                    }
                }
                if let written = writing { base = written }
                if !said.isEmpty, fail("a conflict with no take-in") { return nil }
                return effects
            }
            for _ in 0..<40 {
                let effects: [SettingsSync.Effect]?
                if Int.random(in: 0..<60, using: &rng) == 0 {
                    effects = step("newer file") { rig in rig.putJSON { json in json["version"] = Settings.currentVersion + 1 } }
                } else {
                    var pick: Int
                    repeat { pick = Int.random(in: 0..<17, using: &rng) } while
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
                    case 16:
                        effects = step("the next write fails") { rig in
                            rig.writesFail = 1
                            return []
                        }
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
            rig.writesFail = 0
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
        XCTAssertGreaterThan(failedWrites, 20, "failed writes are part of the mix")
    }
}
