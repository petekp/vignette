import AppKit

/// The session menu as AppKit items: headers over rows, then the More Sessions submenu. Both menus
/// build their items here and add only their own action and what the action needs.
extension SessionMenu {
    static let moreSessions = "More Sessions"

    /// One row as an item: its title, a second line, and a badge. Before macOS 14.4 an item has no
    /// subtitle, so the tooltip, which holds the second line, is all there is.
    @MainActor
    static func item(for row: Row, selected: Bool, image: NSImage?) -> NSMenuItem {
        let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
        item.image = image
        item.state = selected ? .on : .off
        item.toolTip = row.tooltip
        if #available(macOS 14.4, *), !row.subtitle.isEmpty { item.subtitle = row.subtitle }
        if let badge = row.badge { item.badge = NSMenuItemBadge(string: badge) }
        return item
    }

    /// Adds each group to `menu`: its header, then its rows as `make` builds them.
    @MainActor
    static func add(_ groups: [Group], to menu: NSMenu, make: (Row) -> NSMenuItem) {
        for group in groups {
            menu.addItem(.sectionHeader(title: group.header))
            for row in group.rows { menu.addItem(make(row)) }
        }
    }

    /// Adds the top groups, then the More Sessions submenu when there are rows for it.
    @MainActor
    static func add(_ sessions: Menu, to menu: NSMenu, make: (Row) -> NSMenuItem) {
        add(sessions.top, to: menu, make: make)
        guard !sessions.more.isEmpty else { return }
        let more = NSMenuItem(title: moreSessions, action: nil, keyEquivalent: "")
        more.submenu = NSMenu()
        more.submenu?.autoenablesItems = false
        add(sessions.more, to: more.submenu!, make: make)
        menu.addItem(more)
    }
}
