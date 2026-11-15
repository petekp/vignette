import AppKit

/// The session menu as AppKit items: headers over rows, then one submenu per project. Both menus
/// build their items here and add only their own action and what the action needs.
extension SessionMenu {

    /// The agent's logo at a menu icon's size, or the fallback symbol. A menu draws an item's image
    /// at the image's own size.
    @MainActor
    static func logo(for client: AgentClient) -> NSImage? {
        guard let logo = Agent.logo(for: client.rawValue) else {
            return NSImage(systemSymbolName: Agent.fallbackSymbol, accessibilityDescription: client.label)
        }
        let small = logo.copy() as? NSImage ?? logo
        small.size = NSSize(width: 16, height: 16)
        return small
    }

    /// One row as an item: the agent's logo, its title, a second line, and a badge. Before macOS 14.4
    /// an item has no subtitle, so the tooltip, which holds the second line, is all there is.
    @MainActor
    static func item(for row: Row, selected: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
        item.image = logo(for: row.destination.client)
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

    /// Adds a search field as the menu's first row, then the top groups and, after a separator, one
    /// submenu per project holding all of its running sessions, with their count as a badge. Typing in
    /// the field replaces everything the menu holds from here on with the sessions that match, the
    /// rows that start a session included. The returned search must stay alive while the menu is open.
    @MainActor
    static func add(_ sessions: Menu, to menu: NSMenu, make: @escaping (Row) -> NSMenuItem) -> SessionMenuSearch {
        let search = SessionMenuSearch(sessions: sessions, menu: menu, make: make)
        search.install()
        return search
    }

    /// The menu's items with no query: the top groups, then the project submenus.
    @MainActor
    static func addAll(_ sessions: Menu, to menu: NSMenu, make: (Row) -> NSMenuItem) {
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

    static let noMatch = "No session matches"
}

/// The search row of the session menu and what it does to the rows below it. The field lives in a
/// menu item's view, so it is part of the menu and not a window of its own.
@MainActor
final class SessionMenuSearch: NSObject, NSSearchFieldDelegate {
    private let sessions: SessionMenu.Menu
    private let menu: NSMenu
    private let make: (SessionMenu.Row) -> NSMenuItem
    private let field = NSSearchField()
    /// Where the rows start: after the search row and whatever the menu held before it.
    private var start = 0
    /// Whether a query is typed, so the rows below are its matches.
    var isSearching: Bool { !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty }

    init(sessions: SessionMenu.Menu, menu: NSMenu, make: @escaping (SessionMenu.Row) -> NSMenuItem) {
        self.sessions = sessions
        self.menu = menu
        self.make = make
    }

    func install() {
        let holder = FieldHolder(frame: NSRect(x: 0, y: 0, width: 260, height: 34))
        holder.autoresizingMask = [.width]
        field.frame = NSRect(x: 10, y: 5, width: holder.frame.width - 20, height: 24)
        field.autoresizingMask = [.width]
        field.placeholderString = "Search sessions"
        field.delegate = self
        field.focusRingType = .none
        holder.addSubview(field)
        let item = NSMenuItem()
        item.view = holder
        menu.insertItem(item, at: 0)
        start = menu.numberOfItems
        SessionMenu.addAll(sessions, to: menu, make: make)
        holder.field = field
    }

    private func pickFirstMatch() {
        guard let index = menu.items.indices.dropFirst(start).first(where: { menu.items[$0].action != nil }) else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: index)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        pickFirstMatch()
        return true
    }

    func controlTextDidChange(_ note: Notification) {
        while menu.numberOfItems > start { menu.removeItem(at: start) }
        let query = field.stringValue
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            SessionMenu.addAll(sessions, to: menu, make: make)
            return
        }
        let matches = SessionMenu.matching(query, in: sessions.everyone)
        if matches.isEmpty {
            let none = NSMenuItem(title: SessionMenu.noMatch, action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            SessionMenu.add(matches, to: menu, make: make)
        }
    }
}

/// The view of the search row. It gives its field the keyboard once the menu's window exists.
private final class FieldHolder: NSView {
    weak var field: NSControl?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let field = self?.field else { return }
            field.window?.makeFirstResponder(field)
        }
    }
}
