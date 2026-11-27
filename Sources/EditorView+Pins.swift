import AppKit

/// What the editor keeps for its pins beside the core: their layers, the popover by the open pin, the
/// list a cluster opens, and a VoiceOver element for each pin.
@MainActor
final class EditorPinUI: NSObject {
    let pins = EditorPins()
    var composer: PinPopover?
    /// The card the pin under the pointer grows into.
    var hoverCard: PinHoverCard?
    /// The last card shown, while it is still on screen going back into its teardrop.
    weak var lastCard: PinHoverCard?
    /// The pin a press landed on, which grows no card until the pointer has left it.
    var pressedPin: Pin.ID?
    /// A press on a card's panel, held to its release: the card, where the press began on screen, and the
    /// centre of the card's teardrop on screen when it began on the card.
    var cardPress: (card: PinHoverCard, origin: CGPoint, pin: CGPoint?)?
    /// Where the last press on a card was, in the window, so the second press of a double-click there
    /// does not land on what was under the card.
    var cardClick: CGRect?
    /// A drag runs with the popover open: a resize of its pin's area, which took the keys from its field.
    var resizingOpenPin = false
    /// The menu of pins a cluster or the toolbar's Pins button opened, from its asking until it closes.
    var list: NSMenu?
    let listActions = PinListActions()
    var elements: [Pin.ID: PinElement] = [:]
    /// The order VoiceOver's Pins rotor goes through, by number.
    var rotorOrder: [Pin.ID] = []
    /// Called with how many pins have a number, and how many of those are open, when that changes: the
    /// toolbar's Pins button shows them.
    var onCount: ((PinCount) -> Void)?
    var count = PinCount()
    /// Show this rect of a pin, in image px, panning a magnified picture just far enough.
    var onReveal: ((CGRect) -> Void)?
    weak var view: EditorView?
}

extension EditorView {
    /// A zoom step: the core hears the part of the picture in view, then the zoom, which redraws.
    func zoomChanged() {
        message(.viewChanged(visible: resolution.visible))
        handle(.zoomChanged(zoom))
    }

    func showPins() {
        let placement = core.pinPlacement, outlined = core.outlinedPins
        let carded = hoverCardPin(placement)
        // The card covers its teardrop, so the teardrop's selection ring would show at its corner.
        let ringed = core.selection.subtracting(carded.map { [$0] } ?? [])
        pinUI.pins.show(EditorPins.Shown(placement: placement, outlined: core.drawing.pins.filter { outlined.contains($0.id) },
                                         drifting: core.activePins, selected: ringed, handles: core.areaPinCorners, markStyle: core.markStyle,
                                         outlineWidth: core.metrics.selectionOutlineWidth, transform: toView))
        pinUI.composer?.follow(anchor(of: pinUI.composer?.pin, in: placement), area: area(of: pinUI.composer?.pin))
        let resizing = core.composer != nil && core.gesture != nil
        if pinUI.resizingOpenPin, !resizing { pinUI.composer?.takeKeys() }
        pinUI.resizingOpenPin = resizing
        showPinElements(placement)
        showHoverCard(carded, placement)
        let numbered = core.drawing.pins.filter { $0.number > 0 }
        let count = PinCount(all: numbered.count, open: numbered.filter { !$0.isResolved }.count)
        if count != pinUI.count {
            pinUI.count = count
            pinUI.onCount?(count)
        }
    }

    /// The hovered pin with a number, drawn on its own, while no popover, menu or drag is under way:
    /// the one that grows into its card.
    private func hoverCardPin(_ placement: PinPlacement) -> Pin.ID? {
        let hovered: Pin.ID? = if let card = pinUI.hoverCard, pointerIsOn(card) { card.pin }
            else if case .pin(let id)? = core.hover { id } else { nil }
        if pinUI.pressedPin != hovered { pinUI.pressedPin = nil }
        let quiet = core.composer == nil && core.gesture == nil && pinUI.list == nil
        guard quiet, let id = hovered, id != pinUI.pressedPin, let pin = core.pin(id), pin.number > 0,
              placement.drops.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private func showHoverCard(_ carded: Pin.ID?, _ placement: PinPlacement) {
        guard let id = carded, let pin = core.pin(id), let drop = placement.drops.first(where: { $0.id == id }) else {
            // The card goes back into its teardrop when the pointer leaves the pin. A press, an open popover
            // or a parked editor takes it away at once, so it never lingers over the popover or the flight.
            if core.isOpen, core.composer == nil, core.gesture == nil { pinUI.hoverCard?.leave() } else { pinUI.lastCard?.close() }
            pinUI.hoverCard = nil
            return
        }
        if pinUI.hoverCard?.pin != id {
            pinUI.hoverCard?.leave()
            let card = PinHoverCard(pin: id)
            card.onPress = { [weak self, weak card] event, onCard in
                guard let self, let card else { return }
                self.relay(event, onCard: onCard, from: card)
            }
            pinUI.hoverCard = card
            pinUI.lastCard = card
        }
        pinUI.hoverCard?.show(pin, body: drop.square.applying(toView), orientation: drop.orientation, in: self)
    }

    /// A press on the editor. A pressed pin grows no card until the pointer has left it.
    func press(_ event: NSEvent) {
        let doubleClickOnCard = event.clickCount > 1 && pinUI.cardClick?.contains(event.locationInWindow) == true
        pinUI.cardClick = nil
        if doubleClickOnCard { return }
        handle(.pointerPressed(pointer(event), clickCount: event.clickCount), event: event)
        if case .pin(let id)? = core.hover { pinUI.pressedPin = id }
    }

    /// A press on a pin's card is a press on its teardrop, which the card covers: a click opens the pin's
    /// popover with any tool, and a drag moves the pin. A press on the card's shadow lands where it is.
    private func relay(_ event: FlightPress.Event, onCard: Bool, from card: PinHoverCard) {
        if case .pressed = event.phase {
            let teardrop = onCard ? card.teardrop.map { convert(CGPoint(x: $0.midX, y: $0.midY), to: nil) } : nil
            pinUI.cardPress = (card, event.screen, teardrop.flatMap { window?.convertPoint(toScreen: $0) })
        }
        guard let press = pinUI.cardPress else { return }
        var relayed = event
        if let pin = press.pin {
            relayed.screen = CGPoint(x: pin.x + event.screen.x - press.origin.x, y: pin.y + event.screen.y - press.origin.y)
        }
        take(relayed)
        switch event.phase {
        case .pressed:
            if press.pin != nil {
                pinUI.pressedPin = card.pin
                pinUI.cardClick = window.map { NSRect(origin: $0.convertPoint(fromScreen: event.screen), size: .zero).insetBy(dx: -4, dy: -4) }
            }
        case .dragged:
            pinUI.cardClick = nil
        case .released:
            pinUI.cardPress = nil
        }
    }

    private func pointerIsOn(_ card: PinHoverCard) -> Bool {
        guard let window else { return false }
        return card.covers(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    /// The rect in the view a popover on pin `id` hangs from: its teardrop, or its cluster's capsule.
    private func anchor(of id: Pin.ID?, in placement: PinPlacement) -> CGRect? {
        guard let id else { return nil }
        if let drop = placement.drops.first(where: { $0.id == id }) { return drop.square.applying(toView) }
        return placement.clusters.first { $0.pins.contains(id) }?.frame.applying(toView)
    }

    /// Pin `id`'s area in the view, or nil for a point pin.
    private func area(of id: Pin.ID?) -> CGRect? {
        guard let id, case .area(let frame, _)? = core.pin(id)?.place else { return nil }
        return frame.applying(toView)
    }

    // MARK: The pin popover

    func showComposer(_ composer: EditorCore.Composer?) {
        guard let composer, let pin = core.pin(composer.pin), let rect = anchor(of: pin.id, in: core.pinPlacement) else {
            pinUI.composer?.close()
            pinUI.composer = nil
            return
        }
        if let open = pinUI.composer, open.pin == pin.id {
            open.update(pin, composer: composer)
            return
        }
        pinUI.composer?.close()
        let popover = PinPopover(pin: pin, composer: composer, send: { [weak self] input in self?.handle(.composer(input)) },
                                 zoom: { [weak self] request in self?.onZoom?(request) })
        pinUI.composer = popover
        popover.show(from: rect, area: area(of: pin.id), of: self, takesKeys: composer.takesKeys)
    }

    /// The editor came up on its screenshot: the first pin's popover opens, leaving the keys here.
    func openFirstPin() {
        handle(.composer(.openFirst))
    }

    // MARK: A cluster's list and the toolbar's

    func showCluster(_ ids: [Pin.ID], at frame: CGRect) {
        showPinList(ids.compactMap(core.pin), under: frame.applying(toView), of: self)
    }

    /// Every pin with a number, in a menu under `rect` in `view`: the toolbar's Pins button. The open
    /// pins come first, then the resolved ones under a Resolved heading, each in number order.
    func showPinList(from rect: CGRect, of view: NSView) {
        let pins = core.drawing.pins.filter { $0.number > 0 }.sorted { $0.number < $1.number }
        showPinList(pins, under: rect, of: view)
    }

    /// Opens pin `id` chosen in a list, first bringing its teardrop and area into view: the picture
    /// pans to show them, or zooms to fit when they are larger than what is in view.
    func openFromList(_ id: Pin.ID) {
        guard let pin = core.pin(id) else { return }
        let placement = core.pinPlacement, visible = core.visible
        let teardrop = placement.drops.first { $0.id == id }?.square ?? placement.clusters.first { $0.pins.contains(id) }?.frame
        let place: CGRect
        switch pin.place {
        case .point(let point): place = CGRect(origin: point, size: .zero)
        case .area(let frame, _): place = frame
        }
        let shown = teardrop.map(place.union) ?? place
        if shown.width > visible.width || shown.height > visible.height { onZoom?(.fit) } else { pinUI.onReveal?(shown) }
        handle(.composer(.open(id)))
    }

    /// The image changed or the editor is leaving: a list open from it goes.
    func closePinList() {
        pinUI.list?.cancelTracking()
        pinUI.list = nil
    }

    /// `pins` as a menu under `rect` in `view`, a pull-down's place. It opens a turn later, as the
    /// target's menu does: opened inside the editor's keyDown, a menu took no keys. A pick is applied a
    /// turn later too, once the menu's event loop has ended.
    private func showPinList(_ pins: [Pin], under rect: CGRect, of view: NSView) {
        closePinList()
        let menu = NSMenu()
        menu.autoenablesItems = false
        let open = pins.filter { !$0.isResolved }, resolved = pins.filter(\.isResolved)
        for pin in open { menu.addItem(pinListItem(pin)) }
        if !resolved.isEmpty {
            if !open.isEmpty { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: "Resolved"))
            for pin in resolved { menu.addItem(pinListItem(pin)) }
        }
        pinUI.listActions.pick = { [weak self] id in DispatchQueue.main.async { self?.openFromList(id) } }
        pinUI.list = menu
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, let view, pinUI.list === menu else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: view.isFlipped ? rect.maxY : rect.minY), in: view)
            if pinUI.list === menu { pinUI.list = nil }
        }
    }

    /// A pin's row: its teardrop as it looks on screen, then its first comment on one line, an agent's
    /// in the system's monospaced face, as an agent's pin number is, and a resolved pin's in the secondary
    /// label colour. The tooltip holds the comment whole.
    func pinListItem(_ pin: Pin) -> NSMenuItem {
        let ui = Settings.shared.data.ui, menuFont = NSFont.menuFont(ofSize: 0)
        let agent = pin.color == .agent
        let font = agent ? NSFont.monospacedSystemFont(ofSize: menuFont.pointSize, weight: .regular) : menuFont
        let first = pin.comments.first?.text.asOneLine ?? ""
        let item = NSMenuItem(title: "", action: #selector(PinListActions.picked(_:)), keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: SessionMenu.fitted(first, width: ui.pinListTitleWidth, font: font), attributes: [
            .font: font, .foregroundColor: pin.isResolved ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ])
        item.target = pinUI.listActions
        item.representedObject = pin.id
        item.toolTip = pin.comments.first?.text
        item.setAccessibilityLabel("\(pin.spokenName): \(first)")
        item.image = Self.pinImage(number: pin.number, maker: pin.maker, resolved: pin.isResolved, side: ui.pinListImageSize, markStyle: core.markStyle)
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
        return item
    }

    /// The teardrop of a pin `maker` made, `side` pt across, wearing `number` or its maker's face, drawn
    /// flat, grey when `resolved`, as a menu's row shows it.
    static func pinImage(number: Int, maker: PinMaker, resolved: Bool = false, side: CGFloat, markStyle: MarkStyle) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext, markStyle.pin.side > 0 else { return false }
            let pointScale = side / markStyle.pin.side, inset = markStyle.pin.rimWidth * pointScale
            let drop = PinTeardrop(number: number, agent: maker.isAgent, tip: CGPoint(x: rect.minX + inset, y: rect.maxY - inset), orientation: .upRight,
                                   side: side - 2 * inset, style: markStyle.pin)
            drop.drawFlat(in: ctx, maker: maker, resolved: resolved, face: PinFace(maker), pointScale: pointScale, markStyle: markStyle)
            return true
        }
    }

    // MARK: VoiceOver

    private func showPinElements(_ placement: PinPlacement) {
        let pins = core.drawing.pins.filter { $0.number > 0 }.sorted { $0.number < $1.number }
        pinUI.view = self
        pinUI.rotorOrder = pins.map(\.id)
        let kept = Set(pinUI.rotorOrder)
        pinUI.elements = pinUI.elements.filter { kept.contains($0.key) }
        for pin in pins {
            let element = pinUI.elements[pin.id] ?? PinElement()
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(pin.spokenName)
            if let rect = anchor(of: pin.id, in: placement) { element.setAccessibilityFrameInParentSpace(rect) }
            let id = pin.id
            element.press = { [weak self] in self?.handle(.composer(.open(id))) }
            // The pin's popover opens, as a press opens it, and the resolve or the reopen is its own.
            let change: EditorCore.ComposerInput = pin.isResolved ? .reopen : .resolve
            element.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: pin.isResolved ? "Reopen" : "Resolve") { [weak self] in
                self?.handle(.composer(.open(id)))
                self?.handle(.composer(change))
                return true
            }])
            pinUI.elements[pin.id] = element
        }
    }

    override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + pinUI.rotorOrder.compactMap { pinUI.elements[$0] }
    }

    override func accessibilityCustomRotors() -> [NSAccessibilityCustomRotor] {
        [NSAccessibilityCustomRotor(label: "Pins", itemSearchDelegate: pinUI)]
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard core.isOpen else { return nil }
        return [NSAccessibilityCustomAction(name: "Add Pin") { [weak self] in
            self?.handle(.addPin)
            return true
        }]
    }
}

extension EditorPinUI: @preconcurrency NSAccessibilityCustomRotorItemSearchDelegate {
    func rotor(_ rotor: NSAccessibilityCustomRotor, resultFor search: NSAccessibilityCustomRotor.SearchParameters)
        -> NSAccessibilityCustomRotor.ItemResult? {
        let order = rotorOrder.compactMap { elements[$0] }
        guard !order.isEmpty else { return nil }
        let current = (search.currentItem?.targetElement as? PinElement).flatMap { element in order.firstIndex { $0 === element } }
        let next: Int
        switch (search.searchDirection, current) {
        case (.next, let index?): next = index + 1
        case (.previous, let index?): next = index - 1
        case (.next, nil): next = 0
        default: next = order.count - 1
        }
        // NSAccessibilityElement takes this protocol in Objective-C, which Swift does not see.
        guard order.indices.contains(next), let target = order[next] as AnyObject as? NSAccessibilityElementProtocol else { return nil }
        return NSAccessibilityCustomRotor.ItemResult(targetElement: target)
    }
}

/// A pin as VoiceOver reads it: "Pin 3, area, 2 comments". Pressing it opens the pin.
final class PinElement: NSAccessibilityElement {
    var press: (() -> Void)?

    override func accessibilityPerformPress() -> Bool {
        press?()
        return press != nil
    }
}

/// How many pins have a number, and how many of those are open.
struct PinCount: Equatable {
    var all = 0
    var open = 0
}

/// The target of a pin list's items: a pick names its pin.
final class PinListActions: NSObject {
    var pick: ((Pin.ID) -> Void)?

    @objc func picked(_ item: NSMenuItem) {
        if let id = item.representedObject as? Pin.ID { pick?(id) }
    }
}
