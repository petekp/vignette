import XCTest

/// Every root here is a temporary directory. The installer takes its roots as parameters so a test
/// never reaches ~/.claude or ~/.codex, which on a real Mac hold the user's own skills.
final class SkillInstallerTests: XCTestCase {
    private var dir: URL!
    private var source: URL!
    private var root: URL!
    private var installed: URL { SkillInstaller.destination(in: root) }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-skill-\(UUID().uuidString)")
        source = dir.appendingPathComponent("bundle/vignette")
        root = dir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write("---\nname: vignette\n---\n\nShow the user an image.\n")
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private func write(_ text: String) throws {
        try text.write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    private func text(at url: URL) throws -> String {
        try String(contentsOf: url.appendingPathComponent("SKILL.md"), encoding: .utf8)
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func testInstallWritesTheSkill() throws {
        let results = SkillInstaller.install(source: source, into: [root])
        XCTAssertEqual(results.map(\.outcome), [.installed])
        XCTAssertEqual(results.first?.path.path, installed.path)
        XCTAssertEqual(try text(at: installed), try text(at: source))
        XCTAssertEqual(SkillInstaller.state(of: root), .installed)
    }

    func testASecondInstallOfTheSameFilesChangesNothing() {
        _ = SkillInstaller.install(source: source, into: [root])
        XCTAssertEqual(SkillInstaller.install(source: source, into: [root]).map(\.outcome), [.unchanged])
    }

    func testFilesThatDifferFromTheBundleAreRewritten() throws {
        _ = SkillInstaller.install(source: source, into: [root])
        try write("---\nname: vignette\n---\n\nShow the user an image, and read back their marks.\n")
        XCTAssertEqual(SkillInstaller.install(source: source, into: [root]).map(\.outcome), [.updated])
        XCTAssertEqual(try text(at: installed), try text(at: source))
    }

    func testInstallReplacesAFolderThatIsNotASkill() throws {
        try makeDirectory(installed)
        try "notes".write(to: installed.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SkillInstaller.install(source: source, into: [root]).map(\.outcome), [.updated])
        XCTAssertEqual(try text(at: installed), try text(at: source))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.appendingPathComponent("notes.txt").path))
    }

    func testTheSkillIsWrittenThroughALinkedSkillsDirectory() throws {
        // What one agent's directory looks like on a real Mac: `skills` is a link into a
        // repository of the user's, and that is where the agent reads the skill from.
        let real = dir.appendingPathComponent("someone-elses-repo/skills")
        try makeDirectory(real)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("skills"), withDestinationURL: real)

        XCTAssertEqual(SkillInstaller.install(source: source, into: [root]).map(\.outcome), [.installed])
        XCTAssertEqual(try text(at: real.appendingPathComponent("vignette")), try text(at: source))
        XCTAssertEqual(SkillInstaller.state(of: root), .installed, "read back through the link")
        XCTAssertEqual(installed.path, real.appendingPathComponent("vignette").resolvingSymlinksInPath().path)
    }

    func testALinkedSkillFolderIsWrittenThroughAndSurvives() throws {
        // The user keeps the skill in a folder of their own and links the agent at it. The files
        // are theirs to update; the link is theirs to keep.
        let real = dir.appendingPathComponent("my-skills/vignette")
        try makeDirectory(real)
        try "older".write(to: real.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let link = root.appendingPathComponent("skills/vignette")
        try makeDirectory(link.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        XCTAssertEqual(SkillInstaller.install(source: source, into: [root]).map(\.outcome), [.updated])
        XCTAssertEqual(try text(at: real), try text(at: source), "the user's own folder holds the new copy")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), real.path,
                       "the link is still the link")
    }

    func testTwoRootsReachingOneFolderAreOneCopyAndTwoRows() throws {
        let real = dir.appendingPathComponent("my-skills/vignette")
        try makeDirectory(real)
        let second = dir.appendingPathComponent("second")
        for agent in [root!, second] {
            let link = agent.appendingPathComponent("skills/vignette")
            try makeDirectory(link.deletingLastPathComponent())
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        }

        let results = SkillInstaller.install(source: source, into: [root, second])
        XCTAssertEqual(results.map(\.outcome), [.updated, .updated], "one install, reported for both roots")
        XCTAssertEqual(Set(results.map(\.path.path)).count, 1)
        XCTAssertEqual(try text(at: real), try text(at: source))
        XCTAssertEqual(SkillInstaller.state(of: root), .installed)
        XCTAssertEqual(SkillInstaller.state(of: second), .installed)
    }

    func testRemoveTakesTheEntryAndReportsWhenThereIsNone() {
        XCTAssertEqual(SkillInstaller.remove(from: [root]).map(\.outcome), [.absent])
        _ = SkillInstaller.install(source: source, into: [root])
        XCTAssertEqual(SkillInstaller.remove(from: [root]).map(\.outcome), [.removed])
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertEqual(SkillInstaller.state(of: root), .none)
    }

    func testRemoveUnlinksALinkedSkillFolderAndLeavesTheTargetAlone() throws {
        let real = dir.appendingPathComponent("my-skills/vignette")
        try makeDirectory(real)
        try "mine".write(to: real.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let link = root.appendingPathComponent("skills/vignette")
        try makeDirectory(link.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        XCTAssertEqual(SkillInstaller.remove(from: [root]).map(\.outcome), [.removed])
        XCTAssertNil(try? FileManager.default.attributesOfItem(atPath: link.path), "the link is gone")
        XCTAssertEqual(try text(at: real), "mine", "what it pointed at is untouched")
    }

    func testEveryRootIsHandledOnItsOwn() throws {
        let second = dir.appendingPathComponent("second")
        try makeDirectory(SkillInstaller.destination(in: second))
        let results = SkillInstaller.install(source: source, into: [root, second])
        XCTAssertEqual(results.map(\.outcome), [.installed, .updated])
    }

    // MARK: What the Agents tab reads

    /// A home folder with the two agent directories in it, and the roots the tab would list.
    private func agentHome(claude: Bool = true, codex: Bool = true) throws -> URL {
        let home = dir.appendingPathComponent("home")
        for (make, name) in [(claude, ".claude"), (codex, ".codex")] where make {
            try makeDirectory(home.appendingPathComponent(name))
        }
        return home
    }

    func testAStatusIsTheAgentAndWhetherTheSkillIsThere() throws {
        let home = try agentHome()
        let claude = home.appendingPathComponent(".claude")
        _ = SkillInstaller.install(source: source, into: [claude])
        let rows = SkillInstaller.statuses(home: home)
        XCTAssertEqual(rows.map(\.name), ["Claude Code", "Codex"])
        XCTAssertEqual(rows.map(\.status), ["Installed", "Not installed"])
        XCTAssertEqual(rows.map(\.root), [claude, home.appendingPathComponent(".codex")],
                       "each row carries the agent its own button acts on")
    }

    func testAFolderWithoutASkillReadsAsNotInstalled() throws {
        let home = try agentHome(codex: false)
        let claude = home.appendingPathComponent(".claude")
        try makeDirectory(SkillInstaller.destination(in: claude))
        XCTAssertEqual(SkillInstaller.status(of: claude).status, "Not installed")
    }

    func testStatusesAreOneRowPerAgentAndNoneWithoutOne() throws {
        let home = try agentHome()
        XCTAssertEqual(SkillInstaller.statuses(home: home).map(\.name), ["Claude Code", "Codex"])
        XCTAssertEqual(SkillInstaller.statuses(home: dir.appendingPathComponent("empty-home")), [])
    }

    func testRootsAreTheAgentDirectoriesThatExist() throws {
        let home = dir.appendingPathComponent("home")
        try makeDirectory(home.appendingPathComponent(".codex"))
        XCTAssertEqual(SkillInstaller.roots(home: home), [home.appendingPathComponent(".codex")])
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".claude"), withDestinationURL: dir)
        XCTAssertEqual(SkillInstaller.roots(home: home).map(\.lastPathComponent), [".claude", ".codex"],
                       "a linked agent directory is one of them, and is written through")
    }
}
