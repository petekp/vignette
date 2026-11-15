import AppKit
import XCTest

@MainActor
final class SessionMenuRowsTests: XCTestCase {
    private func row(_ session: AgentDestination, now: Date = Date()) -> SessionMenu.Row {
        SessionMenu.row(of: session, among: [session], now: now)
    }

    func testARowSaysWorkingWhileBusyElseWhenTheSessionWasLastActive() {
        let now = Date()
        var s = AgentDestination(id: "a", name: "a", address: .claudeSession("a"), lastUsed: now.addingTimeInterval(-3 * 3600))
        XCTAssertEqual(row(s, now: now).activity, .lastActive("3 hr ago"))
        s.turn = .waiting
        XCTAssertEqual(row(s, now: now).activity, .lastActive("3 hr ago"), "a drawing unread in the inbox is not the agent waiting for the person")
        s.turn = .busy
        XCTAssertEqual(row(s, now: now).activity, .working)
        s.turn = .waiting
        s.lastUsed = nil
        XCTAssertNil(row(s, now: now).activity)
    }

    func testTheWordsAtTheRightEndInOneColumnPastEveryRowsText() {
        let now = Date()
        func session(_ id: String, _ title: String, folder: String, busy: Bool = false) -> AgentDestination {
            var s = AgentDestination(id: id, name: title, address: .claudeSession(id), lastUsed: now.addingTimeInterval(-600), place: .folder(fromHome: folder))
            if busy { s.turn = .busy }
            return s
        }
        let sessions = [
            session("a", "Fix", folder: "~/Code", busy: true),
            session("b", "A much longer title for this session", folder: "~/Code"),
            session("c", "Short", folder: "~/" + String(repeating: "worktree-", count: 12)),
        ]
        let menu = NSMenu()
        let problem = "Claude Code is not signed in. Run claude in a terminal and sign in, then try the note again."
        let responder = LiveNotePopover.Responder(client: .claude, name: "Claude Code", problem: problem, canPick: false)
        let wide = LiveNotePopover.item(for: responder, selected: false, action: #selector(NSObject.copy), target: self)
        menu.addItem(wide)
        let search = SessionMenu.add(SessionMenu.menu(sessions, destination: nil, now: now), to: menu) { SessionMenu.item(for: $0, selected: false) }
        let rows = menu.items.compactMap { $0 as? SessionMenu.IndicatorItem }
        XCTAssertEqual(rows.count, 3)
        let ends = Set(rows.map { $0.attributedTitle!.size().width })
        XCTAssertEqual(ends.count, 1, "every row's words end at one tab stop")
        XCTAssertGreaterThan(SessionMenu.subtitleWidth(of: wide), 250)
        XCTAssertGreaterThanOrEqual(ends.first!, SessionMenu.subtitleWidth(of: wide), "the words end at the right of a wider row without words")
        for row in rows {
            let lines = row.attributedTitle!.string.components(separatedBy: "\n")
            let words = lines[0].components(separatedBy: "\t")
            let title = (words[0] as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
            let indicator = row.attributedTitle!.attributedSubstring(from: NSRange(location: words[0].count + 1, length: lines[0].count - words[0].count - 1)).size().width
            XCTAssertGreaterThanOrEqual(ends.first! - indicator, title + SessionMenu.indicatorGap, row.text)
            row.drawsHighlighted = true
            row.render()
            XCTAssertNotNil(row.secondLine)
            XCTAssertEqual(row.attributedTitle!.string.components(separatedBy: "\n").last, row.secondLine, "a new title keeps the second line")
            if #available(macOS 14.4, *) { XCTAssertNil(row.subtitle, "AppKit would draw a subtitle twice") }
        }
        let quiet = AgentDestination(id: "d", name: "Fix", address: .claudeSession("d"), lastUsed: nil, place: .folder(fromHome: "~/Code"))
        let plain = NSMenu()
        plain.addItem(SessionMenu.item(for: row(quiet), selected: false))
        let oneRow = NSMenu()
        menu.removeItem(rows[0])
        oneRow.addItem(rows[0])
        XCTAssertEqual(oneRow.size.height, plain.size.height, "the dot and the tab keep the row two lines tall")
        withExtendedLifetime(search) {}
    }

    func testEveryRowIsAsTallAsItsLinesHoweverWideTheyAre() {
        func height(title: String, folder: String) -> CGFloat {
            let session = AgentDestination(id: "a", name: title, address: .claudeSession("a"), lastUsed: nil, place: .folder(fromHome: folder))
            let menu = NSMenu()
            menu.addItem(SessionMenu.item(for: row(session), selected: false))
            return menu.size.height
        }
        let twoLines = height(title: "Fix", folder: "~/Code")
        XCTAssertEqual(height(title: "Fix", folder: "~/" + String(repeating: "worktree-", count: 12)), twoLines,
                       "a second line far wider than its title")
        XCTAssertEqual(height(title: String(repeating: "a long title ", count: 10), folder: "~/" + String(repeating: "worktree-", count: 30)), twoLines,
                       "a second line wider than a long title")
        let problem = "Claude Code is not signed in. Run claude in a terminal and sign in, then try the note again."
        let responder = LiveNotePopover.Responder(client: .claude, name: "Claude Code", problem: problem, canPick: false)
        let menu = NSMenu()
        menu.addItem(LiveNotePopover.item(for: responder, selected: false, action: #selector(NSObject.copy), target: self))
        XCTAssertEqual(menu.size.height, twoLines, "a responder that cannot answer, with a long reason")
        XCTAssertEqual(menu.items[0].toolTip, problem)
    }
}
