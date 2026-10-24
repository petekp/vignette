import AppKit

/// The session menu as AppKit items: headers over rows, then one submenu per project. Both menus
/// build their items here and add only their own action and what the action needs.
extension SessionMenu {

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

    /// Adds the top groups, then, after a separator, one submenu per project holding all of its
    /// sessions, with their count as a badge.
    @MainActor
    static func add(_ sessions: Menu, to menu: NSMenu, make: (Row) -> NSMenuItem) {
        add(sessions.top, to: menu, make: make)
        guard !sessions.projects.isEmpty else { return }
        menu.addItem(.separator())
        for project in sessions.projects {
            let item = NSMenuItem(title: project.header, action: nil, keyEquivalent: "")
            item.badge = NSMenuItemBadge(count: project.rows.count)
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for row in project.rows { submenu.addItem(make(row)) }
            item.submenu = submenu
            menu.addItem(item)
        }
    }
}
