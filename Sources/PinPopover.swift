import AppKit

/// The popover beside an open pin: its comments, oldest first, each one a click away from being
/// edited and with a Delete of its own, and under them the composer, the field a comment is written in,
/// a capsule with its post button inside. A ✓ on the first comment resolves the pin, posting the
/// field's words first while it holds some. A resolved pin's popover opens on who resolved it, its
/// comments are muted, and its ✓ reopens it. Every change in it moves (`PinPopoverColumn`). Its keys
/// are the composer's (`EditorCore.ComposerInput`): Return posts, Shift+Return or Option+Return breaks
/// the line, Cmd+Return posts and finishes, and Esc posts and closes.
@MainActor
final class PinPopover: NSObject, NSPopoverDelegate, NSTextFieldDelegate {
    static var width: CGFloat { Settings.shared.data.ui.pinPopoverWidth }
    private static var inset: CGFloat { Settings.shared.data.ui.pinPopoverInset }
    /// The rows' width.
    static var rowWidth: CGFloat { width - 2 * inset }
    let pin: Pin.ID
    private let popover = NSPopover()
    private let controller = NSViewController()
    private let column: PinPopoverColumn
    let field = ComposerField()
    let post = NSButton()
    private var composer = NSView()
    /// Who resolved the pin, over its comments.
    let resolveControls: PinResolveControls
    /// The state the popover shows, set by `showState`.
    var shownState: (resolved: Pin.Resolution?, number: Int)?
    private let rim = PinGelRim()
    private var rimColor: SRGB?
    let send: (EditorCore.ComposerInput) -> Void
    var shown: (comments: [Pin.Comment], editing: Int?)?
    /// What the comments' deliveries say (`PinLiveComments`).
    var live = PinLiveComments()
    /// The rows over the composer, and the views they reuse from one change to the next.
    var rows: [NSView] = []
    var commentRows: [UUID: CommentRow] = [:]
    var separators: [String: NSView] = [:]
    var working: (client: AgentClient, row: NSView)?
    /// The comment that carries the ✓.
    weak var firstRow: CommentRow?
    private var anchor = CGRect.null
    /// When the popover opened: each comment's time is said as of then, and holds still while it is open.
    let opened = Date()
    private var aroundArea = false
    /// One line of the field's words, and the field's height, which grows with them up to
    /// `ui.pinComposerLines` lines.
    var lineHeight: CGFloat = 0
    var fieldHeight: NSLayoutConstraint?
    /// Closed by the core, so the popover's own close says nothing back.
    private var closing = false
    /// The view that keeps the keys while the popover the editor opened on its own comes up.
    private weak var keepsKeys: NSView?

    /// `zoom` takes the editor's zoom keys while the field has the keys.
    init(pin: Pin, composer: EditorCore.Composer, live: PinLiveComments, send: @escaping (EditorCore.ComposerInput) -> Void,
         zoom: @escaping (EditorCore.ZoomRequest) -> Void) {
        self.pin = pin.id
        self.send = send
        let ui = Settings.shared.data.ui
        resolveControls = PinResolveControls(width: Self.rowWidth)
        column = PinPopoverColumn(width: Self.width, inset: Self.inset, spacing: ui.pinPopoverSpacing)
        super.init()
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .labelColor
        field.isEditable = true
        let body = NSFont.preferredFont(forTextStyle: .body)
        field.font = body
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.lineBreakMode = .byWordWrapping
        // The field editor's clip view reaches 2 points above the field, so a field scrolled past
        // `ui.pinComposerLines` lines would show the bottom of the line above its first.
        field.clipsToBounds = true
        field.preferredMaxLayoutWidth = Self.fieldWidth
        field.delegate = self
        field.setAccessibilityLabel(pin.number > 0 ? "Comment on pin \(pin.number)" : "Comment on new pin")
        column.commandReturn = { [weak self] in self?.send(.finish) }
        column.zoom = zoom
        column.onHeight = { [weak self] height in
            self?.popover.contentSize = CGSize(width: Self.width, height: height)
        }
        column.onSettle = { [weak self] in self?.commentRows.values.forEach { $0.readPointer() } }
        let size = ui.pinPostSize
        post.isBordered = false
        post.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Post comment")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .regular))
        post.imageScaling = .scaleProportionallyDown
        post.target = self
        post.action = #selector(postPressed)
        post.toolTip = "Post comment"
        self.composer = composerRow(postSize: size, padding: ui.pinFieldPadding)
        controller.view = column
        column.addSubview(rim)
        column.cover = rim
        popover.contentViewController = controller
        popover.behavior = .applicationDefined
        popover.delegate = self
        update(pin, composer: composer, live: live)
    }

    /// Opens by the pin's teardrop, `rect` in `view`, as `PinPopoverPlace` says from the pin's `area`
    /// and the room on the screen. With `takesKeys` false the keys stay with `view`'s window until
    /// the person clicks into the popover.
    func show(from rect: CGRect, area: CGRect?, of view: NSView, takesKeys: Bool) {
        let onScreen = view.window.map { $0.convertToScreen(view.convert(rect, to: nil)) }
        let screen = view.window?.screen?.visibleFrame
        let roomOnRight = onScreen.flatMap { drop in screen.map { drop.maxX + PinPopoverPlace.reach(width: Self.width) <= $0.maxX } } ?? true
        let place = PinPopoverPlace(teardrop: rect, area: area, roomOnRight: roomOnRight)
        anchor = place.rect
        aroundArea = place.aroundArea
        popover.show(relativeTo: place.rect, of: view, preferredEdge: place.edge)
        field.window?.autorecalculatesKeyViewLoop = true
        guard takesKeys else {
            keepsKeys = view
            holdNoFocus()
            return
        }
        field.window?.makeFirstResponder(field)
    }

    func popoverDidShow(_ notification: Notification) {
        rim.popoverShown()
        holdNoFocus()
        keepsKeys = nil
    }

    /// Opened without the keys, the popover focuses none of its views, so with Full Keyboard Access
    /// on no comment shows a focus ring before the person moves there, and the view it opened from
    /// is the first responder again, so the tool letters and Esc reach the editor.
    private func holdNoFocus() {
        guard let keepsKeys, let window = keepsKeys.window else { return }
        field.window?.makeFirstResponder(nil)
        window.makeKey()
        window.makeFirstResponder(keepsKeys)
    }

    /// A press on the picture took the keys, as a resize does: they come back to the field, with the
    /// caret or the selection where it was, where AppKit would select all the words.
    func takeKeys() {
        guard let window = field.window, popover.isShown else { return }
        window.makeKey()
        guard field.currentEditor() == nil else { return }
        window.makeFirstResponder(field)
        guard let editor = field.currentEditor() else { return }
        let length = (editor.string as NSString).length
        let kept = field.endedSelection ?? NSRange(location: length, length: 0)
        let location = min(kept.location, length)
        editor.selectedRange = NSRange(location: location, length: min(kept.length, length - location))
    }

    /// The pin's teardrop, and its area, moved with the zoom or a drag: the popover moves with them.
    func follow(_ rect: CGRect?, area: CGRect?) {
        guard let rect, popover.isShown else { return }
        let place = PinPopoverPlace(teardrop: rect, area: area, aroundArea: aroundArea)
        guard place.rect != anchor else { return }
        anchor = place.rect
        popover.positioningRect = place.rect
    }

    func update(_ pin: Pin, composer: EditorCore.Composer, live: PinLiveComments) {
        let duration = Settings.shared.motionUI.pinPopoverDuration
        if field.stringValue != composer.draft { field.stringValue = composer.draft }
        let stateChanged = shownState.map { $0.resolved != pin.resolved || $0.number != pin.number } ?? true
        if stateChanged { showState(of: pin, over: duration) }
        if stateChanged || shown?.comments != pin.comments || shown?.editing != composer.editing || self.live != live {
            shown = (pin.comments, composer.editing)
            self.live = live
            showComments(of: pin, editing: composer.editing, over: duration)
            // A row pressed from the keyboard had the focus, and went with the rows.
            if let window = field.window, window.isKeyWindow, field.currentEditor() == nil {
                let focus = window.firstResponder
                let focusWent = focus == nil || focus === window
                    || (focus as? CommentRow).map { row in !commentRows.values.contains { $0 === row } } ?? false
                if focusWent { window.makeFirstResponder(field) }
            }
        }
        showPlaceholder(resolved: pin.isResolved, over: duration)
        showPostable(over: duration)
        fit(over: duration)
    }

    /// The post button works only when the field holds words: an empty Return is how a comment is deleted or the popover closed.
    /// The ✓ posts them before it resolves while it does.
    func showPostable(over duration: Double) {
        post.isEnabled = replying
        post.contentTintColor = post.isEnabled ? .controlAccentColor : .tertiaryLabelColor
        firstRow?.show(words: firstRowWords.text, color: firstRowWords.color, status: firstRowWords.status, note: firstRowWords.note,
                       resolve: resolveAction, over: duration)
    }

    private var replying: Bool { !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// What the ✓ does, which a new pin goes without.
    var resolveAction: ResolveAction? {
        guard let shownState, shownState.number > 0 else { return nil }
        return shownState.resolved == nil ? .resolve(replying: replying) : .reopen
    }

    /// Whether the pin is resolved, and by whom: the line over its comments and its rim's colour, the
    /// old colour fading out over the new.
    private func showState(of pin: Pin, over duration: Double) {
        shownState = (pin.resolved, pin.number)
        let ui = Settings.shared.data.ui
        resolveControls.show(pin, now: opened, over: duration)
        let color = PinShading.color(of: pin.maker, resolved: pin.isResolved, markStyle: ui.markStyle)
        if let old = rimColor, old != color, duration > 0, rim.window != nil {
            let fading = PinGelRim()
            column.addSubview(fading, positioned: .above, relativeTo: rim)
            fading.wear(old, edge: .popover)
            PopoverFade.alpha(fading, to: 0, over: duration) { fading.removeFromSuperview() }
        }
        rimColor = color
        rim.wear(color, edge: .popover)
    }

    @objc private func postPressed() { send(.post) }

    func resolvePressed() { send(shownState?.resolved == nil ? .resolve : .reopen) }

    func close() {
        closing = true
        popover.close()
    }

    /// The rows and the composer, the field at its words' height, moving to their places over `duration`.
    func fit(over duration: Double) {
        fieldHeight?.constant = wrappedHeight
        column.show(rows, foot: composer, over: duration)
    }

    func popoverDidClose(_ notification: Notification) {
        if !closing { send(.close) }
    }
}
