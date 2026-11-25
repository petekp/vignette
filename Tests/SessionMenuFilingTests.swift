import XCTest

final class SessionMenuFilingTests: XCTestCase {
    func testClonesOfOneRemoteShareOneGroupAndEveryCloneButTheMainOneIsAPlace() {
        let now = Date()
        let home = SessionPlaces.home
        let mine = home + "/Code/ever/evercars-backend"
        let kickflip = home + "/.claude/kickflip/repos/ever-cars/evercars-backend"
        func fix(_ id: String, _ place: Place, used: Double = 1) -> AgentDestination {
            AgentDestination(id: id, name: "Fix", address: .claudeSession(id), lastUsed: now.addingTimeInterval(-used * 60), place: place)
        }
        func clone(_ root: String, remote: String?, worktree: String? = nil, name: String = "evercars-backend") -> Place {
            .repository(name: name, root: root, remote: remote, worktree: worktree, subfolder: nil)
        }
        let a = fix("a", clone(mine, remote: "github.com/Ever-Cars/evercars-backend"), used: 2)
        let b = fix("b", clone(kickflip, remote: "github.com/ever-cars/evercars-backend"), used: 1)
        let menu = SessionMenu.menu([b, a], destination: nil, now: now)
        XCTAssertEqual(menu.top.map(\.header), ["evercars-backend"])
        XCTAssertEqual(menu.topRows.map(\.title), ["Fix (~/.claude/kickflip/repos/ever-cars/evercars-backend)", "Fix"],
                       "the clone in a tool's dot folder is not the main one, however recently it was used")
        XCTAssertEqual(menu.topRows[0].details, "~/.claude/kickflip/repos/ever-cars/evercars-backend")
        XCTAssertEqual(menu.topRows[1].details, "")
        XCTAssertEqual(SessionMenu.menu([b], destination: nil, now: now).topRows.map(\.details), [""], "a lone clone is the main one")
        let short = fix("s", clone(home + "/.k/evercars-backend", remote: "github.com/Ever-Cars/evercars-backend"), used: 3)
        XCTAssertEqual(SessionMenu.menu([a, short], destination: nil, now: now).topRows.map(\.details), ["", "~/.k/evercars-backend"],
                       "a clone in a dot folder is not the main one, however short its path")

        let goneCodex = fix("c", .repository(name: "evercars-backend", root: nil, remote: "github.com/Ever-Cars/evercars-backend",
                                             worktree: SessionPlaces.codexWorktree, subfolder: nil), used: 3)
        let goneWorktree = fix("d", .repository(name: "evercars-backend", root: nil, worktree: "menu", subfolder: nil), used: 6)
        XCTAssertEqual(SessionMenu.menu([a, b, goneCodex, goneWorktree], destination: nil, now: now).top.map { $0.rows.map(\.id) },
                       [["b", "a", "c", "d"]], "a session known by its remote or its name only joins the repository")

        let other = fix("e", clone(home + "/Code/forks/evercars-backend", remote: "github.com/petekp/evercars-backend"), used: 4)
        let local = fix("f", clone(home + "/scratch/evercars-backend", remote: nil), used: 5)
        let apart = SessionMenu.menu([a, b, other, local, goneCodex, goneWorktree], destination: nil, count: 10, now: now)
        XCTAssertEqual(apart.top.map(\.header), ["Ever-Cars/evercars-backend", "petekp/evercars-backend", "~/scratch/evercars-backend",
                                                 "evercars-backend"], "repositories with one name are told apart by owner, else path")
        XCTAssertEqual(apart.top.map { $0.rows.map(\.id) }, [["b", "a", "c"], ["e"], ["f"], ["d"]],
                       "a session known by its name only, which two repositories share, joins neither")

        let sameOwner = fix("g", clone(home + "/elsewhere/evercars-backend", remote: "gitlab.com/Ever-Cars/evercars-backend"), used: 3)
        XCTAssertEqual(SessionMenu.menu([a, sameOwner], destination: nil, now: now).top.map(\.header),
                       ["~/Code/ever/evercars-backend", "~/elsewhere/evercars-backend"], "one owner and name on two hosts")

        let w1 = fix("w1", clone(mine, remote: "github.com/Ever-Cars/evercars-backend", worktree: "one"), used: 1)
        let w2 = fix("w2", clone(mine, remote: "github.com/Ever-Cars/evercars-backend", worktree: "two"), used: 2)
        XCTAssertEqual(Set(SessionMenu.menu([w1, w2, b], destination: nil, now: now).topRows.map(\.title)),
                       ["Fix (one)", "Fix (two)", "Fix (~/.claude/kickflip/repos/ever-cars/evercars-backend)"],
                       "the other clone's row keeps its place when worktrees tell the main clone's rows apart")

        let nearer = fix("n", clone(home + "/Code/evercars-backend", remote: "github.com/Ever-Cars/evercars-backend"), used: 3)
        XCTAssertEqual(SessionMenu.menu([a, nearer], destination: nil, now: now).topRows.map(\.details), ["~/Code/ever/evercars-backend", ""],
                       "outside dot folders, the shorter path is the main clone")
        let beside = fix("m", clone(home + "/Code/aaaa/evercars-backend", remote: "github.com/Ever-Cars/evercars-backend"), used: 3)
        XCTAssertEqual(SessionMenu.menu([a, beside], destination: nil, now: now).topRows.map(\.details), ["~/Code/ever/evercars-backend", ""],
                       "with paths of one length, the first by path is the main clone")

        let startInMine = AgentDestination(id: SessionStart.newRowID(folder: mine), name: "New session", detail: "evercars-backend",
                                           address: .claudeSession(""), lastUsed: now.addingTimeInterval(-600),
                                           place: clone(mine, remote: "github.com/Ever-Cars/evercars-backend"), hasOwnName: false,
                                           folder: mine, start: .new(folder: mine))
        let offered = DestinationChoice.Candidates(destinations: [b, short], complete: true, fresh: true, startable: [startInMine])
        XCTAssertEqual(SessionMenu.noteSession("s", among: offered)?.title, "Fix (~/.k/evercars-backend)",
                       "live ink's note words a card's title over its start rows too, so a clone with only a start row is the main one")
    }

    @MainActor
    func testALiveNoteWordsItsTargetAgainWhenAStartRowArrivesAndTheTargetStays() {
        let now = Date()
        let mine = SessionPlaces.home + "/Code/ever/evercars-backend", remote = "github.com/Ever-Cars/evercars-backend"
        func fix(_ id: String, in root: String, used: Double) -> AgentDestination {
            AgentDestination(id: id, name: "Fix", address: .claudeSession(id), lastUsed: now.addingTimeInterval(-used * 60),
                             place: .repository(name: "evercars-backend", root: root, remote: remote, worktree: nil, subfolder: nil))
        }
        let b = fix("b", in: SessionPlaces.home + "/.claude/kickflip/repos/ever-cars/evercars-backend", used: 1)
        let short = fix("s", in: SessionPlaces.home + "/.k/evercars-backend", used: 3)
        let startInMine = AgentDestination(id: SessionStart.newRowID(folder: mine), name: "New session", detail: "evercars-backend",
                                           address: .claudeSession(""), lastUsed: now.addingTimeInterval(-600),
                                           place: .repository(name: "evercars-backend", root: mine, remote: remote, worktree: nil, subfolder: nil),
                                           hasOwnName: false, folder: mine, start: .new(folder: mine))
        let note = LiveNotePopover(at: PopoverPlace(anchor: nil, at: .zero, edge: .below, body: .zero, foot: .zero), target: .session(short))
        var sentTitle: String?
        note.onAsk = { _, _, title in sentTitle = title }
        note.setSessions(.init(destinations: [b, short], complete: true, fresh: true))
        XCTAssertEqual(note.content.session.accessibilityLabel(), "Goes to Fix", "of two clones in dot folders, the shorter path is the main one")

        note.setSessions(.init(destinations: [b, short], complete: true, fresh: true, startable: [startInMine]))
        XCTAssertEqual(note.target, .session(short))
        XCTAssertEqual(note.content.session.accessibilityLabel(), "Goes to Fix (~/.k/evercars-backend)",
                       "a start row in the main clone, listed later, tells the target's clone apart")
        note.content.field.stringValue = "Why is this red?"
        note.send()
        XCTAssertEqual(sentTitle, "Fix (~/.k/evercars-backend)", "and a card sent to it is titled as the target reads")
        note.setSessions(.init(destinations: [b, short], complete: true, fresh: true))
        XCTAssertEqual(note.content.session.accessibilityLabel(), "Goes to Fix (~/.k/evercars-backend)",
                       "a sent note keeps the name it was sent with until the conversation takes its place")
    }
}
