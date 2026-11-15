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

    /// Puts `client`'s logo on `item`, where a menu draws an item's image. From macOS 27 AppKit hides
    /// an item's image unless the item asks for it.
    @MainActor
    static func showLogo(of client: AgentClient, on item: NSMenuItem) {
        item.image = logo(for: client)
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
    }

    /// Puts a clear image of a logo's size on `item`. macOS 27 starts the title of an item with no
    /// image at the menu's left, yet measures it from where the others' titles start, so its words
    /// after a tab stop end short of theirs.
    @MainActor
    static func showSpace(on item: NSMenuItem) {
        item.image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
    }

    /// The widest a row's title is drawn. A menu with less room on screen than a title needs measures
    /// it as two lines and draws its first, cut mid-sentence on a row a line too tall. 400 pt keeps a
    /// row with its logo and the words at its right inside a menu about 530 pt wide.
    static let titleWidth: CGFloat = 400
    /// AppKit measures an item's subtitle as two lines once it is wider than its title or than this,
    /// whichever is wider, then draws it on one line across the menu: the row keeps an empty line
    /// and its logo sits below its text. Measured on macOS 27.2: between 282 and 288 pt of 11 pt text.
    static let subtitleWidth: CGFloat = 280

    /// `text`, cut at its end with "…" when it is wider than `width` in `font`.
    static func fitted(_ text: String, width: CGFloat, font: NSFont) -> String {
        let fits = { (line: String) in (line as NSString).size(withAttributes: [.font: font]).width <= width }
        if fits(text) { return text }
        let cut = { (kept: Int) in String(text.prefix(kept)).trimmingCharacters(in: .whitespaces.union(["·"])) + "…" }
        var low = 0, high = text.count
        while low < high {
            let mid = (low + high + 1) / 2
            if fits(cut(mid)) { low = mid } else { high = mid - 1 }
        }
        return cut(low)
    }

    /// Sets `text` as the item's second line, cut to the width AppKit draws on one line. Before
    /// macOS 14.4 an item has no subtitle, and the tooltip is all there is.
    @MainActor
    static func setSubtitle(_ text: String, on item: NSMenuItem) {
        guard #available(macOS 14.4, *) else { return }
        let titleDrawn = (item.title as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
        item.subtitle = fitted(text, width: max(titleDrawn, subtitleWidth), font: .systemFont(ofSize: NSFont.smallSystemFontSize))
    }

    /// One row as an item: the agent's logo, its title, a second line, each on one line, and at its
    /// right what the session is doing.
    @MainActor
    static func item(for row: Row, selected: Bool) -> NSMenuItem {
        let title = fitted(row.title, width: titleWidth, font: .menuFont(ofSize: 0))
        let item = switch row.activity {
        case .working: IndicatorItem(title: title, indicator: .working)
        case .lastActive(let ago): IndicatorItem(title: title, indicator: .lastActive(ago))
        case nil: NSMenuItem(title: title, action: nil, keyEquivalent: "")
        }
        showLogo(of: row.destination.client, on: item)
        item.state = selected ? .on : .off
        item.toolTip = row.tooltip
        if !row.subtitle.isEmpty { setSubtitle(row.subtitle, on: item) }
        return item
    }

    /// Adds each group to `menu`: its header, then its rows as `make` builds them.
    @MainActor
    static func add(_ groups: [Group], to menu: NSMenu, make: (Row) -> NSMenuItem) {
        for group in groups {
            menu.addItem(header(group.header))
            for row in group.rows { menu.addItem(make(row)) }
        }
    }

    /// Adds a search field as the menu's first row, then the top groups and, after a separator, one
    /// submenu per project holding all of its running sessions, with their count at its right. Typing in
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
            let item = IndicatorItem(title: project.header, indicator: .count(project.rows.count))
            showSpace(on: item)
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
    private let indicators: SessionMenuIndicators
    /// Where the rows start: after the search row and whatever the menu held before it.
    private var start = 0
    /// Whether a query is typed, so the rows below are its matches.
    var isSearching: Bool { !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty }

    init(sessions: SessionMenu.Menu, menu: NSMenu, make: @escaping (SessionMenu.Row) -> NSMenuItem) {
        self.sessions = sessions
        self.menu = menu
        self.make = make
        indicators = SessionMenuIndicators(menu: menu)
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
        indicators.refresh()
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
        rebuild()
        indicators.refresh()
    }

    private func rebuild() {
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
