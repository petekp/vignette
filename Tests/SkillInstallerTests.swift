import XCTest

/// Every root here is a temporary directory. The installer takes its roots as parameters so a test
/// never reaches ~/.claude or ~/.codex, which on a real Mac hold the user's own skills.
final class SkillInstallerTests: XCTestCase {
    private var dir: URL!
    private var source: URL!
    private var root: URL!
    private let stamp = SkillInstaller.Stamp(app: "Vignette", version: "0.1.0", build: "aaaa111")
    private var installed: URL { SkillInstaller.folder(in: root) }

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

    func testInstallWritesTheSkillAndItsMarker() throws {
        let results = SkillInstaller.install(source: source, into: [root], stamp: stamp)
        XCTAssertEqual(results.map(\.outcome), [.installed])
        XCTAssertEqual(results.first?.path.path, installed.path)
        XCTAssertEqual(try text(at: installed), try text(at: source))
        XCTAssertEqual(SkillInstaller.state(of: root).stamp, stamp, "the marker says which build wrote it")
    }

    func testSecondInstallOfTheSameBuildChangesNothing() {
        _ = SkillInstaller.install(source: source, into: [root], stamp: stamp)
        let again = SkillInstaller.install(source: source, into: [root], stamp: stamp)
        XCTAssertEqual(again.map(\.outcome), [.unchanged])
    }

    func testANewerBuildRewritesOurCopy() throws {
        _ = SkillInstaller.install(source: source, into: [root], stamp: stamp)
        try write("---\nname: vignette\n---\n\nShow the user an image, and read back their marks.\n")
        let newer = SkillInstaller.Stamp(app: "Vignette", version: "0.2.0", build: "bbbb222")
        XCTAssertEqual(SkillInstaller.install(source: source, into: [root], stamp: newer).map(\.outcome), [.updated])
        XCTAssertEqual(try text(at: installed), try text(at: source))
        XCTAssertEqual(SkillInstaller.state(of: root).stamp, newer)
    }

    func testAnEditedCopyIsRewrittenEvenAtTheSameBuild() throws {
        _ = SkillInstaller.install(source: source, into: [root], stamp: stamp)
        try "gone".write(to: installed.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SkillInstaller.install(source: source, into: [root], stamp: stamp).map(\.outcome), [.updated])
        XCTAssertEqual(try text(at: installed), try text(at: source))
    }

    func testADirectoryWithoutOurMarkerIsNeverWrittenOrRemoved() throws {
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try "someone else's skill".write(to: installed.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SkillInstaller.install(source: source, into: [root], stamp: stamp).map(\.outcome), [.notOurs])
        XCTAssertEqual(try text(at: installed), "someone else's skill")
        XCTAssertEqual(SkillInstaller.remove(from: [root]).map(\.outcome), [.notOurs])
        XCTAssertEqual(try text(at: installed), "someone else's skill")
    }

    func testALinkedSkillIsNotOursWhateverItPointsAt() throws {
        // The repo's own skill folder, linked into the agent's directory by hand: the link is
        // followed to a copy that does have a marker if you let it, so the path itself is checked.
        _ = SkillInstaller.install(source: source, into: [dir.appendingPathComponent("elsewhere")], stamp: stamp)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("skills"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: installed,
                                                   withDestinationURL: SkillInstaller.folder(in: dir.appendingPathComponent("elsewhere")))
        XCTAssertEqual(SkillInstaller.state(of: root).state, .foreign)
        XCTAssertEqual(SkillInstaller.install(source: source, into: [root], stamp: stamp).map(\.outcome), [.notOurs])
        XCTAssertEqual(SkillInstaller.remove(from: [root]).map(\.outcome), [.notOurs])
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
    }

    func testARootOrItsSkillsDirectoryThatIsALinkIsNeverWrittenThrough() throws {
        // What one agent's directory looks like on a real Mac: `skills` is a link into a
        // repository of the user's, so a copy written through it lands somewhere they did not name.
        let real = dir.appendingPathComponent("someone-elses-repo/skills")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("skills"), withDestinationURL: real)

        XCTAssertEqual(SkillInstaller.linkedPath(in: root)?.path, root.appendingPathComponent("skills").path)
        XCTAssertEqual(SkillInstaller.install(source: source, into: [root], stamp: stamp).map(\.outcome), [.linkedRoot])
        XCTAssertEqual(SkillInstaller.remove(from: [root]).map(\.outcome), [.linkedRoot])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: real.path), [],
                       "nothing was written through the link")
        XCTAssertFalse(SkillInstaller.install(source: source, into: [root], stamp: stamp)[0].detail.isEmpty,
                       "the refusal says why")

        // The agent directory itself can be the link, and the copy lands just as far away.
        let linked = dir.appendingPathComponent("linked-root")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: dir.appendingPathComponent("someone-elses-repo"))
        XCTAssertEqual(SkillInstaller.linkedPath(in: linked)?.path, linked.path)
        XCTAssertEqual(SkillInstaller.install(source: source, into: [linked], stamp: stamp).map(\.outcome), [.linkedRoot])
        XCTAssertEqual(SkillInstaller.remove(from: [linked]).map(\.outcome), [.linkedRoot])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: real.path), [],
                       "nothing was written through the linked root either")
    }

    func testRemoveTakesOurCopyAndReportsWhenThereIsNone() {
        XCTAssertEqual(SkillInstaller.remove(from: [root]).map(\.outcome), [.absent])
        _ = SkillInstaller.install(source: source, into: [root], stamp: stamp)
        XCTAssertEqual(SkillInstaller.remove(from: [root]).map(\.outcome), [.removed])
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertEqual(SkillInstaller.state(of: root).state, .none)
    }

    func testEveryRootIsHandledOnItsOwn() throws {
        let second = dir.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: SkillInstaller.folder(in: second), withIntermediateDirectories: true)
        let results = SkillInstaller.install(source: source, into: [root, second], stamp: stamp)
        XCTAssertEqual(results.map(\.outcome), [.installed, .notOurs])
    }

    // MARK: What the Agents tab reads

    /// A home folder with the two agent directories in it, and the roots the tab would list.
    private func agentHome(claude: Bool = true, codex: Bool = true) throws -> URL {
        let home = dir.appendingPathComponent("home")
        for (make, name) in [(claude, ".claude"), (codex, ".codex")] where make {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        return home
    }

    func testStatusOfOurCopyNamesTheBuildAndThePath() throws {
        let home = try agentHome(codex: false)
        let claude = home.appendingPathComponent(".claude")
        _ = SkillInstaller.install(source: source, into: [claude], stamp: stamp)
        let status = SkillInstaller.status(of: claude, home: home)
        XCTAssertEqual(status.name, "Claude Code")
        XCTAssertEqual(status.status, "Installed, 0.1.0 (aaaa111)")
        XCTAssertEqual(status.detail, "~/.claude/skills/vignette")
        XCTAssertNil(status.reveal)
    }

    func testStatusOfAnEmptyRootNamesThePathTheSkillWouldTake() throws {
        let home = try agentHome(claude: false)
        let status = SkillInstaller.status(of: home.appendingPathComponent(".codex"), home: home)
        XCTAssertEqual(status.name, "Codex")
        XCTAssertEqual(status.status, "Not installed")
        XCTAssertEqual(status.detail, "~/.codex/skills/vignette")
        XCTAssertNil(status.reveal)
    }

    func testStatusOfSomeoneElsesSkillSaysItIsLeftAlone() throws {
        let home = try agentHome(codex: false)
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: SkillInstaller.folder(in: claude), withIntermediateDirectories: true)
        let status = SkillInstaller.status(of: claude, home: home)
        XCTAssertEqual(status.status, "Something else is at ~/.claude/skills/vignette. Vignette leaves it alone.")
        XCTAssertNil(status.detail)
        XCTAssertNil(status.reveal)
    }

    func testStatusOfALinkedRootSaysWhyAndRevealsTheLink() throws {
        let home = try agentHome(claude: false)
        let codex = home.appendingPathComponent(".codex")
        let link = codex.appendingPathComponent("skills")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir.appendingPathComponent("someone-elses-repo"))
        let status = SkillInstaller.status(of: codex, home: home)
        XCTAssertEqual(status.status, "Not installed: ~/.codex/skills is a link, and Vignette does not write through links.")
        XCTAssertNil(status.detail)
        XCTAssertEqual(status.reveal, link)
    }

    func testStatusesAreOneRowPerAgentAndNoneWithoutOne() throws {
        let home = try agentHome()
        XCTAssertEqual(SkillInstaller.statuses(home: home).map(\.name), ["Claude Code", "Codex"])
        XCTAssertEqual(SkillInstaller.statuses(home: dir.appendingPathComponent("empty-home")), [])
    }

    func testRootsAreTheAgentDirectoriesThatExist() throws {
        let home = dir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        XCTAssertEqual(SkillInstaller.roots(home: home), [home.appendingPathComponent(".codex")])
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".claude"), withDestinationURL: dir)
        XCTAssertEqual(SkillInstaller.roots(home: home).map(\.lastPathComponent), [".claude", ".codex"],
                       "a linked root is still listed, so the state report can name it as skipped")
    }
}
