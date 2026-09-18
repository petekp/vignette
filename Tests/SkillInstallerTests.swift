import XCTest

/// Every root here is a temporary directory. The installer takes its roots as parameters so a test
/// never reaches ~/.claude or ~/.codex, which on a real Mac hold the user's own skills.
final class SkillInstallerTests: XCTestCase {
    private var dir: URL!
    private var source: URL!
    private var root: URL!
    private let stamp = SkillInstaller.Stamp(app: "Shotnote", version: "0.1.0", build: "aaaa111")
    private var installed: URL { SkillInstaller.folder(in: root) }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotnote-skill-\(UUID().uuidString)")
        source = dir.appendingPathComponent("bundle/shotnote")
        root = dir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write("---\nname: shotnote\n---\n\nShow the user an image.\n")
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
        try write("---\nname: shotnote\n---\n\nShow the user an image, and read back their marks.\n")
        let newer = SkillInstaller.Stamp(app: "Shotnote", version: "0.2.0", build: "bbbb222")
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

    func testRootsAreTheAgentDirectoriesThatExist() throws {
        let home = dir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        XCTAssertEqual(SkillInstaller.roots(home: home), [home.appendingPathComponent(".codex")])
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        XCTAssertEqual(SkillInstaller.roots(home: home).map(\.lastPathComponent), [".claude", ".codex"])
    }
}
