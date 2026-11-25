import XCTest

final class SessionPlacesTests: XCTestCase {
    private func temporaryFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("places-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeFolder(_ path: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func canonical(_ url: URL) -> String {
        (try? url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? url.path
    }

    func testARepositoryWorktreeSubfolderAndBranchAreReadFromGitFiles() throws {
        let base = temporaryFolder()
        let home = try makeFolder("home", in: base)
        let main = try makeFolder("home/Code/evercars", in: base)
        try write("ref: refs/heads/main\n", to: main.appendingPathComponent(".git/HEAD"))
        try write("ref: refs/remotes/origin/main\n", to: main.appendingPathComponent(".git/refs/remotes/origin/HEAD"))
        _ = try makeFolder("home/Code/evercars/apps/pdk-ui/.hidden", in: base)

        let inMain = SessionPlaces.resolve(folder: main.appendingPathComponent("apps/pdk-ui").path, home: home.path)
        XCTAssertEqual(inMain.place, .repository(name: "evercars", root: canonical(main), worktree: nil, subfolder: "apps/pdk-ui"))
        XCTAssertNil(inMain.branch, "the default branch is not shown")

        let inHidden = SessionPlaces.resolve(folder: main.appendingPathComponent("apps/pdk-ui/.hidden").path, home: home.path)
        XCTAssertEqual(inHidden.place, .repository(name: "evercars", root: canonical(main), worktree: nil, subfolder: "apps/pdk-ui"))

        let worktree = try makeFolder("home/Code/worktrees/evercars/live-ink", in: base)
        let gitdir = main.appendingPathComponent(".git/worktrees/live-ink")
        try write("gitdir: \(gitdir.path)\n", to: worktree.appendingPathComponent(".git"))
        try write("../..\n", to: gitdir.appendingPathComponent("commondir"))
        try write("ref: refs/heads/live-ink\n", to: gitdir.appendingPathComponent("HEAD"))
        let inWorktree = SessionPlaces.resolve(folder: worktree.path, home: home.path)
        XCTAssertEqual(inWorktree.place, .repository(name: "evercars", root: canonical(main), worktree: "live-ink", subfolder: nil))
        XCTAssertEqual(inWorktree.branch, "live-ink")

        let goneInside = SessionPlaces.resolve(folder: main.appendingPathComponent(".claude/worktrees/agent-1").path, home: home.path)
        XCTAssertEqual(goneInside.place, .repository(name: "evercars", root: canonical(main), worktree: "agent-1", subfolder: nil))

        let codex = try makeFolder("home/.codex/worktrees/6684/evercars", in: base)
        let codexGitdir = main.appendingPathComponent(".git/worktrees/evercars1")
        try write("gitdir: \(codexGitdir.path)\n", to: codex.appendingPathComponent(".git"))
        try write("../..\n", to: codexGitdir.appendingPathComponent("commondir"))
        try write("0123456789abcdef\n", to: codexGitdir.appendingPathComponent("HEAD"))
        let inCodex = SessionPlaces.resolve(folder: codex.path, home: home.path, environment: [:])
        XCTAssertEqual(inCodex.place, .repository(name: "evercars", root: canonical(main), worktree: SessionPlaces.codexWorktree, subfolder: nil))
        XCTAssertNil(inCodex.branch)
    }

    func testTheDefaultBranchFallsBackToMainThenMaster() throws {
        let base = temporaryFolder()
        let home = try makeFolder("home", in: base)
        let repo = try makeFolder("home/old", in: base)
        try write("ref: refs/heads/feature\n", to: repo.appendingPathComponent(".git/HEAD"))
        try write("0123\n", to: repo.appendingPathComponent(".git/refs/heads/master"))
        XCTAssertEqual(SessionPlaces.resolve(folder: repo.path, home: home.path).branch, "feature")
        try write("ref: refs/heads/master\n", to: repo.appendingPathComponent(".git/HEAD"))
        XCTAssertNil(SessionPlaces.resolve(folder: repo.path, home: home.path).branch)
    }

    func testAFolderWithNoRepositoryIsAPathFromHome() throws {
        let base = temporaryFolder()
        let home = try makeFolder("home", in: base)
        try write("ref: refs/heads/main\n", to: home.appendingPathComponent(".git/HEAD"))
        let code = try makeFolder("home/Code", in: base)
        XCTAssertEqual(SessionPlaces.resolve(folder: code.path, home: home.path).place, .folder(fromHome: "~/Code"))
        XCTAssertEqual(SessionPlaces.resolve(folder: home.path, home: home.path).place, .folder(fromHome: "~"))
        XCTAssertEqual(SessionPlaces.resolve(folder: nil, home: home.path).place, .none)
    }

    func testAFolderThatIsGoneIsReadFromItsShapeThenItsRemote() throws {
        let base = temporaryFolder()
        let home = try makeFolder("home", in: base)
        func place(_ path: String, origin: String? = nil) -> Place {
            SessionPlaces.resolve(folder: home.appendingPathComponent(path).path, originURL: origin, home: home.path).place
        }
        XCTAssertEqual(place(".codex/worktrees/6684/evercars/apps/ui"),
                       .repository(name: "evercars", root: nil, worktree: SessionPlaces.codexWorktree, subfolder: "apps/ui"))
        XCTAssertEqual(place("Code/worktrees/vignette/menu"), .repository(name: "vignette", root: nil, worktree: "menu", subfolder: nil))
        XCTAssertEqual(place("Code/vignette/.worktrees/menu/Sources"), .repository(name: "vignette", root: nil, worktree: "menu", subfolder: "Sources"))
        XCTAssertEqual(place("Code/vignette/.claude/worktrees/menu"), .repository(name: "vignette", root: nil, worktree: "menu", subfolder: nil))
        XCTAssertEqual(place("Code/gone", origin: "git@github.com:Ever-Cars/evercars-backend.git"),
                       .repository(name: "evercars-backend", root: nil, worktree: nil, subfolder: nil))
        XCTAssertEqual(place("Code/gone"), .folder(fromHome: "~/Code/gone"))
        XCTAssertEqual(SessionPlaces.remoteName("https://github.com/Ever-Cars/evercars-backend.git"), "evercars-backend")
    }

    func testTheFolderHoldingARepositorysWorktreesAndEveryFolderInItAreFiledUnderTheRepository() throws {
        let base = temporaryFolder()
        let home = try makeFolder("home", in: base)
        let main = try makeFolder("home/Code/ever/evercars-backend", in: base)
        try write("ref: refs/heads/main\n", to: main.appendingPathComponent(".git/HEAD"))
        let worktrees = try makeFolder("home/Code/ever/worktrees/evercars-backend", in: base)
        let notes = try makeFolder("home/Code/ever/worktrees/evercars-backend/notes/drafts", in: base)
        let worktree = try makeFolder("home/Code/ever/worktrees/evercars-backend/live-ink", in: base)
        let gitdir = main.appendingPathComponent(".git/worktrees/live-ink")
        try write("gitdir: \(gitdir.path)\n", to: worktree.appendingPathComponent(".git"))
        try write("../..\n", to: gitdir.appendingPathComponent("commondir"))
        func place(_ folder: URL) -> Place { SessionPlaces.resolve(folder: folder.path, home: home.path).place }
        let root = canonical(main)

        XCTAssertEqual(place(main), .repository(name: "evercars-backend", root: root, worktree: nil, subfolder: nil))
        XCTAssertEqual(place(worktrees), .repository(name: "evercars-backend", root: root, worktree: nil, subfolder: "worktrees"))
        XCTAssertEqual(place(notes), .repository(name: "evercars-backend", root: root, worktree: nil, subfolder: "worktrees/notes/drafts"))
        XCTAssertEqual(place(notes.appendingPathComponent("gone")),
                       .repository(name: "evercars-backend", root: root, worktree: nil, subfolder: "worktrees/notes/drafts/gone"))
        XCTAssertEqual(place(worktree), .repository(name: "evercars-backend", root: root, worktree: "live-ink", subfolder: nil))
        XCTAssertEqual(place(worktree.appendingPathComponent("apps/gone")),
                       .repository(name: "evercars-backend", root: root, worktree: "live-ink", subfolder: "apps/gone"))
        XCTAssertEqual(place(worktrees.appendingPathComponent("removed/apps")),
                       .repository(name: "evercars-backend", root: root, worktree: "removed", subfolder: "apps"))
    }

    func testAWorktreesFolderWithNoCheckoutBesideItIsAPlainFolder() throws {
        let base = temporaryFolder()
        let home = try makeFolder("home", in: base)
        try write("ref: refs/heads/main\n", to: home.appendingPathComponent(".git/HEAD"))
        let noCheckout = try makeFolder("home/Code/ever/worktrees/evercars-backend/notes", in: base)
        _ = try makeFolder("home/Downloads/photos", in: base)
        let notAWorktree = try makeFolder("home/Downloads/worktrees/photos/2024", in: base)
        let besideHome = try makeFolder("worktrees/home/notes", in: base)
        func place(_ folder: URL) -> Place { SessionPlaces.resolve(folder: folder.path, home: home.path).place }

        XCTAssertEqual(place(noCheckout), .folder(fromHome: "~/Code/ever/worktrees/evercars-backend/notes"))
        XCTAssertEqual(place(notAWorktree), .folder(fromHome: "~/Downloads/worktrees/photos/2024"))
        XCTAssertEqual(place(besideHome), .folder(fromHome: canonical(besideHome)))
        XCTAssertEqual(place(noCheckout.deletingLastPathComponent().appendingPathComponent("menu")),
                       .repository(name: "evercars-backend", root: nil, worktree: "menu", subfolder: nil))
    }
}
