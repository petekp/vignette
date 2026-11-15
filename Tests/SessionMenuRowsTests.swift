import AppKit
import XCTest

@MainActor
final class SessionMenuRowsTests: XCTestCase {
    private func row(_ session: AgentDestination, now: Date = Date()) -> SessionMenu.Row {
        SessionMenu.row(of: session, among: [session], now: now)
    }

    func testTheBadgeSaysWorkingWhileBusyElseWhenTheSessionWasLastActive() {
        let now = Date()
        var s = AgentDestination(id: "a", name: "a", address: .claudeSession("a"), lastUsed: now.addingTimeInterval(-3 * 3600))
        XCTAssertEqual(row(s, now: now).badge, "3 hr ago")
        s.turn = .waiting
        XCTAssertEqual(row(s, now: now).badge, "3 hr ago", "a drawing unread in the inbox is not the agent waiting for the person")
        s.turn = .busy
        XCTAssertEqual(row(s, now: now).badge, "Working")
        s.turn = .waiting
        s.lastUsed = nil
        XCTAssertNil(row(s, now: now).badge)
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
    }
}
