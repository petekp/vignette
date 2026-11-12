import AppKit

/// The target menu's items answer here: AppKit calls an item's action on an object.
@MainActor
final class TargetMenuActions: NSObject {
    var onPick: ((AgentDestination, _ menuLine: String?) -> Void)?
    /// The menu open now, the rows it was built from, and its search, which must live while it is open.
    var open: (root: NSMenu, sessions: SessionMenu.Menu, search: SessionMenuSearch)?

    @objc func pick(_ item: NSMenuItem) {
        if let destination = item.representedObject as? AgentDestination { onPick?(destination, menuLine(picking: item)) }
    }

    /// `[send] menu top=<rows> list=top|project|search [submenu=<n>] [rows=<rows>] picked=<row> row=<n>`:
    /// the five rows the menu opened with, the list the pick was made in, and the picked row's place
    /// in it, counted from 1. Rows are named by `loggedName` alone, so the line holds no title or folder.
    private func menuLine(picking item: NSMenuItem) -> String? {
        guard let open, let list = item.menu, let picked = item.representedObject as? AgentDestination else { return nil }
        let rows = list.items.compactMap { $0.action == nil ? nil : $0.representedObject as? AgentDestination }
        guard let row = rows.firstIndex(where: { $0.id == picked.id }) else { return nil }
        let top = open.sessions.topRows.map(\.destination)
        let names = { (rows: [AgentDestination]) in rows.map(Self.loggedName).joined(separator: ",") }
        var line = "[send] menu top=\(names(top))"
        if list !== open.root {
            let submenus = open.root.items.compactMap(\.submenu)
            line += " list=project submenu=\((submenus.firstIndex { $0 === list } ?? -1) + 1) rows=\(names(rows))"
        } else if !open.search.isSearching {
            line += " list=top"
        } else {
            line += " list=search rows=\(names(rows))"
        }
        return line + " picked=\(Self.loggedName(picked)) row=\(row + 1)"
    }

    /// A row's name in the log: a running session's id, `resume:<id>` for a project's Continue last
    /// session, and `new` for its New session, whose row id holds its folder.
    static func loggedName(_ destination: AgentDestination) -> String {
        switch destination.start {
        case nil: return destination.id
        case .resume: return "resume:\(destination.id)"
        case .new: return "new"
        }
    }
}
