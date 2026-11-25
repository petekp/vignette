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
    /// The font AppKit draws an item's subtitle in.
    static let subtitleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

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

    /// Sets `text` as the item's subtitle, cut to the width AppKit draws on one line. Before
    /// macOS 14.4 an item has no subtitle, and the tooltip is all there is.
    @MainActor
    static func setSubtitle(_ text: String, on item: NSMenuItem) {
        guard #available(macOS 14.4, *) else { return }
        let titleDrawn = (item.title as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
        item.subtitle = fitted(text, width: max(titleDrawn, subtitleWidth), font: subtitleFont)
    }

    /// One row as an item, on one line: the agent's logo, its title, and at its right what the
    /// session is doing. The tooltip holds the title and the session's details whole.
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
    static func add(_ sessions: Menu, to menu: NSMenu, highlightingFirstRow: Bool = false,
                    make: @escaping (Row) -> NSMenuItem) -> SessionMenuSearch {
        let search = SessionMenuSearch(sessions: sessions, menu: menu, make: make)
        search.install(highlightingFirstRow: highlightingFirstRow)
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
    private let field = QuietSearchField()
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

    /// `highlightingFirstRow` highlights the first row once the field has the keys, the row
    /// Return in the empty field picks.
    func install(highlightingFirstRow: Bool = false) {
        let holder = FieldHolder(frame: NSRect(x: 0, y: 0, width: 260, height: 34))
        holder.autoresizingMask = [.width]
        field.frame = NSRect(x: 10, y: 5, width: holder.frame.width - 20, height: 24)
        field.autoresizingMask = [.width]
        field.placeholderString = "Search sessions"
        field.delegate = self
        field.focusRingType = .none
        // In a menu, a search field's bezel draws an opaque text box, darker than the glass around
        // it. The holder draws the field's fill instead.
        field.isBezeled = false
        field.drawsBackground = false
        holder.addSubview(field)
        let item = NSMenuItem()
        item.view = holder
        menu.insertItem(item, at: 0)
        start = menu.numberOfItems
        SessionMenu.addAll(sessions, to: menu, make: make)
        indicators.refresh()
        holder.field = field
        if highlightingFirstRow { holder.hasKeys = Self.pressDown(in:) }
    }

    /// One Down key to the menu's own window, which its tracking takes as a person's Down from the
    /// field: it highlights the row below. AppKit has no call that highlights a menu item.
    private static func pressDown(in window: NSWindow) {
        guard window.isVisible else { return }
        let down = "\u{F701}"   // NSDownArrowFunctionKey
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                           context: nil, characters: down, charactersIgnoringModifiers: down,
                                           isARepeat: false, keyCode: 125) else { return }
        NSApp.postEvent(event, atStart: false)
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
        if SessionMenu.searchWords(in: query).isEmpty {
            SessionMenu.addAll(sessions, to: menu, make: make)
            return
        }
        let matches = SessionMenu.matching(query, in: sessions)
        if matches.isEmpty {
            let none = NSMenuItem(title: SessionMenu.noMatch, action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            SessionMenu.add(matches, to: menu, make: make)
        }
    }
}

/// A search field without a bezel. NSSearchFieldCell draws and edits a borderless field's text from
/// the field's left edge, under the magnifier, so this cell puts it between the magnifier and the
/// clear button, centred on the field's height. In the menu's window, the field editor and its clip
/// view drew `textBackgroundColor` over that space while editing, an opaque box inside the
/// holder's fill, though the field draws no background. So their background is clear, which
/// draws nothing even when AppKit turns their background on.
private final class QuietSearchField: NSSearchField {
    override class var cellClass: AnyClass? {
        get { QuietSearchFieldCell.self }
        set {}
    }
}

private final class QuietSearchFieldCell: NSSearchFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let font = font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
        let left = searchButtonRect(forBounds: rect).maxX
        let right = cancelButtonRect(forBounds: rect).minX
        return NSRect(x: left, y: rect.midY - lineHeight / 2, width: max(right - left, 0), height: lineHeight)
    }

    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj)
        Self.clearBackground(of: editor)
        return editor
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
        Self.clearBackground(of: textObj)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
        Self.clearBackground(of: textObj)
    }

    /// The clip view exists only once AppKit has put the editor in the field, after the setup.
    private static func clearBackground(of editor: NSText) {
        editor.drawsBackground = false
        editor.backgroundColor = .clear
        guard let clip = editor.superview as? NSClipView else { return }
        clip.drawsBackground = false
        clip.backgroundColor = .clear
    }
}

/// The view of the search row. It draws the field's fill, puts the backing in the menu's glass and
/// gives its field the keyboard once the menu's window exists.
private final class FieldHolder: NSView {
    weak var field: NSControl?
    /// Runs once, when the field has first taken the keyboard, with the menu's window.
    var hasKeys: ((NSWindow) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        guard let field else { return }
        let fill = field.frame
        NSColor.tertiarySystemFill.setFill()
        NSBezierPath(roundedRect: fill, xRadius: fill.height / 2, yRadius: fill.height / 2).fill()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        SessionMenuBacking.install(in: window)
        DispatchQueue.main.async { [weak self] in
            guard let self, let field, let window = field.window, window.makeFirstResponder(field) else { return }
            let hasKeys = self.hasKeys
            self.hasKeys = nil
            hasKeys?(window)
        }
    }
}

/// A fill of the window colour behind the session menu's rows, inside the menu's own glass, so the
/// windows behind the menu show only as a faint hue. NSMenu has no API for its background, so this
/// finds the glass in AppKit's menu window, whose views are not public. When a macOS draws the menu
/// some other way, nothing is added and the menu keeps the system's look.
@MainActor
final class SessionMenuBacking: NSView {
    /// How much of the glass the window colour covers.
    static let opacity: CGFloat = 0.78

    /// Adds a backing to `window`, a menu's window, unless Reduce Transparency already makes menus
    /// opaque or the window has one. Logs what it found.
    static func install(in window: NSWindow) {
        let outcome = place(in: window)
        Log.write("[send] session menu backing \(outcome) window=\(type(of: window))")
    }

    private static func place(in window: NSWindow) -> String {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency { return "skipped: reduce transparency" }
        guard #available(macOS 26.0, *) else { return "skipped: no glass before macOS 26" }
        guard let root = window.contentView?.superview ?? window.contentView else { return "skipped: no views" }
        guard let glass = firstGlass(in: root) else { return "skipped: no glass" }
        guard let content = glass.contentView else { return "skipped: glass holds no view" }
        if content.subviews.contains(where: { $0 is SessionMenuBacking }) { return "kept" }
        let backing = SessionMenuBacking(frame: content.bounds)
        backing.autoresizingMask = [.width, .height]
        backing.layer?.cornerRadius = glass.cornerRadius
        backing.layer?.cornerCurve = .continuous
        content.addSubview(backing, positioned: .below, relativeTo: nil)
        return "added"
    }

    @available(macOS 26.0, *)
    private static func firstGlass(in view: NSView) -> NSGlassEffectView? {
        if let glass = view as? NSGlassEffectView { return glass }
        for subview in view.subviews {
            if let glass = firstGlass(in: subview) { return glass }
        }
        return nil
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(Self.opacity).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
