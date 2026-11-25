import XCTest

final class SessionMenuSearchTests: XCTestCase {
    private func session(_ id: String, used hours: Double, place: Place = .none, now: Date) -> AgentDestination {
        AgentDestination(id: id, name: id, address: .claudeSession(id), lastUsed: now.addingTimeInterval(-hours * 3600), place: place)
    }

    private func repo(_ name: String, at root: String? = nil) -> Place {
        .repository(name: name, root: root ?? "/Users/p/Code/\(name)", worktree: nil, subfolder: nil)
    }

    func testSearchFindsEveryWordInTheTitleTheSecondLineOrTheHeader() {
        let now = Date()
        var tabbed = session("a", used: 1, place: repo("vignette"), now: now)
        tabbed.hostLabel = "Café menu"
        tabbed.goal = "Search the sessions"
        let list = [tabbed,
                    session("b", used: 2, place: repo("inbox"), now: now),
                    session("c", used: 3, place: repo("vignette"), now: now)]
        let menu = SessionMenu.menu(list, destination: nil, now: now)
        func ids(_ query: String) -> [[String]] { SessionMenu.matching(query, in: menu).map { $0.rows.map(\.id) } }
        XCTAssertEqual(ids("CAFE"), [["a"]], "case and accents are ignored")
        XCTAssertEqual(ids("cafe-menu"), [["a"]], "a hyphen parts words as a space does")
        XCTAssertEqual(ids("search_sessions"), [["a"]], "so does an underscore")
        XCTAssertEqual(ids("search sessions"), [["a"]], "every word must be found, in any order")
        XCTAssertEqual(ids("inbox"), [["b"]], "the header counts")
        XCTAssertEqual(ids("vignette"), [["a", "c"]], "a header matches all of its rows")
        XCTAssertEqual(ids("  "), [["a", "c"], ["b"]], "no words, no filtering")
        XCTAssertEqual(ids("zzz"), [])
    }

    func testSearchPutsTheGroupWithTheFreshestMatchFirstAndRunningSessionsBeforeRowsThatStartOne() {
        let now = Date()
        var fresh = session("fresh", used: 1, place: .folder(fromHome: "~/Code/ever/worktrees/evercars-backend"), now: now)
        fresh.hostLabel = "PDK Lead Assignment"
        var older = session("older", used: 30, place: repo("evercars-backend"), now: now)
        older.goal = "Lead assignment review"
        var oldest = session("oldest", used: 40, place: repo("evercars-backend"), now: now)
        oldest.goal = "Lead assignment docs"
        var resume = AgentDestination(id: "resume", name: "resume", address: .claudeSession("resume"), lastUsed: now,
                                      start: .resume(folder: "/Users/p/Code/lead-assignment"))
        resume.place = repo("lead-assignment")
        let stale = AgentDestination(id: "stale", name: "Lead assignment thread", address: .codexThread(uuid: "stale"),
                                     lastUsed: now.addingTimeInterval(-48 * 3600), place: repo("threads"))
        let menu = SessionMenu.menu([oldest, resume, older, fresh], destination: stale, now: now)
        XCTAssertEqual(SessionMenu.matching("lead assignment", in: menu).map { $0.rows.map(\.id) },
                       [["fresh"], ["older", "oldest"], ["stale"], ["resume"]],
                       "the freshest match leads from Other folders, a group keeps its order, and a running session no longer active still comes before a row that starts one")
        XCTAssertEqual(SessionMenu.matching("lead", in: SessionMenu.menu([resume], destination: stale, now: now)).map { $0.rows.map(\.id) },
                       [["stale"], ["resume"]], "with only rows that start a session in the top rows, a running match still leads")
        var staleBeside = stale
        staleBeside.place = resume.place
        XCTAssertEqual(SessionMenu.matching("lead", in: SessionMenu.menu([resume], destination: staleBeside, now: now)).map { $0.rows.map(\.id) },
                       [["stale", "resume"]], "in one group too, the running session comes before the row that starts one")
        XCTAssertEqual(SessionMenu.searchWords(in: " - _ "), [], "a query of only hyphens and underscores searches for nothing")
    }
}
