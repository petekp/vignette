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
        func place(_ path: String, origin: String? = nil, environment: [String: String] = [:]) -> Place {
            SessionPlaces.resolve(folder: home.appendingPathComponent(path).path, originURL: origin, home: home.path, environment: environment).place
        }
        XCTAssertEqual(place(".codex/worktrees/6684/evercars/apps/ui"),
                       .repository(name: "evercars", root: nil, worktree: SessionPlaces.codexWorktree, subfolder: "apps/ui"))
        XCTAssertEqual(place(".codex/worktrees/6684/evercars"),
                       .repository(name: "evercars", root: nil, worktree: SessionPlaces.codexWorktree, subfolder: nil))
        XCTAssertEqual(place(".codex/worktrees/6684", origin: "git@github.com:Ever-Cars/evercars-backend.git"),
                       .repository(name: "evercars-backend", root: nil, remote: "github.com/Ever-Cars/evercars-backend", worktree: nil, subfolder: nil))
        XCTAssertEqual(place(".codex/worktrees/6684/evercars", origin: "https://github.com/Ever-Cars/evercars.git"),
                       .repository(name: "evercars", root: nil, remote: "github.com/Ever-Cars/evercars", worktree: SessionPlaces.codexWorktree, subfolder: nil))
        let moved = ["CODEX_HOME": try makeFolder("home/agents/codex", in: base).path]
        XCTAssertEqual(place("agents/codex/worktrees/6684/evercars/apps", environment: moved),
                       .repository(name: "evercars", root: nil, worktree: SessionPlaces.codexWorktree, subfolder: "apps"))
        XCTAssertEqual(place(".codex/worktrees/6684/evercars", environment: moved),
                       .repository(name: "evercars", root: nil, worktree: SessionPlaces.codexWorktree, subfolder: nil))
        XCTAssertEqual(place(".claude/worktrees/agent-1"), .folder(fromHome: "~/.claude/worktrees/agent-1"))
        XCTAssertEqual(place(".worktrees/menu"), .folder(fromHome: "~/.worktrees/menu"))
        XCTAssertEqual(place("Code/worktrees/vignette/menu"), .repository(name: "vignette", root: nil, worktree: "menu", subfolder: nil))
        XCTAssertEqual(place("Code/vignette/.worktrees/menu/Sources"), .repository(name: "vignette", root: nil, worktree: "menu", subfolder: "Sources"))
        XCTAssertEqual(place("Code/vignette/.claude/worktrees/menu"), .repository(name: "vignette", root: nil, worktree: "menu", subfolder: nil))
        XCTAssertEqual(place("Code/gone", origin: "git@github.com:Ever-Cars/evercars-backend.git"),
                       .repository(name: "evercars-backend", root: nil, remote: "github.com/Ever-Cars/evercars-backend", worktree: nil, subfolder: nil))
        XCTAssertEqual(place("Code/gone"), .folder(fromHome: "~/Code/gone"))
    }

    func testEveryWayOfWritingOneRemoteGivesOneAddress() {
        for url in ["https://github.com/Ever-Cars/evercars-backend.git", "git@github.com:Ever-Cars/evercars-backend.git",
                    "ssh://git@GitHub.com:22/Ever-Cars/evercars-backend/", "https://token@github.com/Ever-Cars/evercars-backend",
                    " git://github.com/Ever-Cars/evercars-backend.git\n"] {
            XCTAssertEqual(SessionPlaces.remoteAddress(url), "github.com/Ever-Cars/evercars-backend", url)
        }
        XCTAssertEqual(SessionPlaces.remoteAddress("file:///srv/git/notes.git"), "/srv/git/notes")
        XCTAssertEqual(SessionPlaces.remoteAddress("file://localhost/srv/git/notes.GIT"), "/srv/git/notes")
        XCTAssertEqual(SessionPlaces.remoteAddress("ssh://git@[2001:db8::1]:22/o/foo"), "[2001:db8::1]/o/foo")
        XCTAssertNotEqual(SessionPlaces.remoteAddress("https://[2001:db8::1]/o/foo"), SessionPlaces.remoteAddress("https://[2001:db8::2]/o/foo"))
        XCTAssertEqual(SessionPlaces.remoteAddress("/srv/git/notes.git"), "/srv/git/notes")
        XCTAssertNil(SessionPlaces.remoteAddress("../notes.git"), "a relative path names a different repository from each checkout")
        XCTAssertNil(SessionPlaces.remoteAddress(""))
    }

    func testTheOriginIsReadFromTheRepositorysConfigForEveryCheckoutOfIt() throws {
        let base = temporaryFolder()
        let home = try makeFolder("home", in: base)
        let main = try makeFolder("home/Code/evercars", in: base)
        try write("ref: refs/heads/main\n", to: main.appendingPathComponent(".git/HEAD"))
        try write("""
        [core]
        \turl = https://example.com/not-a-remote
        [remote "upstream"]
        \turl = https://github.com/someone/evercars.git
        [Remote "origin"]
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        \tURL = "git@github.com:Ever-Cars/evercars.git" ; the company's
        """, to: main.appendingPathComponent(".git/config"))
        let worktree = try makeFolder("home/Code/worktrees/evercars/live-ink", in: base)
        let gitdir = main.appendingPathComponent(".git/worktrees/live-ink")
        try write("gitdir: \(gitdir.path)\n", to: worktree.appendingPathComponent(".git"))
        try write("../..\n", to: gitdir.appendingPathComponent("commondir"))
        let root = canonical(main)
        func place(_ folder: URL) -> Place { SessionPlaces.resolve(folder: folder.path, home: home.path).place }
        let remote = "github.com/Ever-Cars/evercars"
        XCTAssertEqual(place(main), .repository(name: "evercars", root: root, remote: remote, worktree: nil, subfolder: nil))
        XCTAssertEqual(place(worktree), .repository(name: "evercars", root: root, remote: remote, worktree: "live-ink", subfolder: nil))
        XCTAssertEqual(place(worktree.deletingLastPathComponent().appendingPathComponent("gone")),
                       .repository(name: "evercars", root: root, remote: remote, worktree: "gone", subfolder: nil))
        XCTAssertEqual(SessionPlaces.resolve(folder: main.path, originURL: "https://github.com/someone/else.git", home: home.path).place,
                       .repository(name: "evercars", root: root, remote: remote, worktree: nil, subfolder: nil),
                       "the checkout's own config wins over a thread's stored remote")

        let unnamed = try makeFolder("home/Code/unnamed", in: base)
        try write("[remote \"Origin\"]\n\turl = https://github.com/Ever-Cars/unnamed.git\n", to: unnamed.appendingPathComponent(".git/config"))
        XCTAssertEqual(place(unnamed), .repository(name: "unnamed", root: canonical(unnamed), worktree: nil, subfolder: nil),
                       "a remote's name keeps its case")
        for config in ["[remote.origin]\n\turl = https://github.com/o/unnamed\n", "[remote\t\"origin\"]\r\n\turl = https://github.com/o/unnamed\r\n",
                       "[remote \"origin\"] url = https://github.com/o/unnamed\n"] {
            try write(config, to: unnamed.appendingPathComponent(".git/config"))
            XCTAssertEqual(place(unnamed), .repository(name: "unnamed", root: canonical(unnamed), remote: "github.com/o/unnamed", worktree: nil, subfolder: nil), config)
        }
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
