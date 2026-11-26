import AppKit

/// What the editor keeps for its pins beside the core: their layers, the popover by the open pin, the
/// list a cluster opens, and a VoiceOver element for each pin.
@MainActor
final class EditorPinUI: NSObject {
    let pins = EditorPins()
    /// The width in screen pt of the frame the whole picture fits, from the host, or 0 when it gives
    /// none and the view's own size is the fit.
    var fittedWidth: CGFloat = 0
    var composer: PinPopover?
    /// The card the pin under the pointer grows into.
    var hoverCard: PinHoverCard?
    /// A drag runs with the popover open: a resize of its pin's area, which took the keys from its field.
    var resizingOpenPin = false
    /// The menu of pins a cluster or the toolbar's Pins button opened, from its asking until it closes.
    var list: NSMenu?
    let listActions = PinListActions()
    var elements: [Pin.ID: PinElement] = [:]
    /// The order VoiceOver's Pins rotor goes through, by number.
    var rotorOrder: [Pin.ID] = []
    /// Called with how many pins have a number, when that changes: the toolbar's Pins button shows it.
    var onCount: ((Int) -> Void)?
    var count = 0
    /// Show this rect of a pin, in image px, panning a magnified picture just far enough.
    var onReveal: ((CGRect) -> Void)?
    weak var view: EditorView?
}

extension EditorView {
    /// The host's fitted frame's width; see `EditorPinUI.fittedWidth`.
    var fittedWidth: CGFloat {
        get { pinUI.fittedWidth }
        set {
            guard newValue != pinUI.fittedWidth else { return }
            pinUI.fittedWidth = newValue
            if core.isOpen { zoomChanged() }
        }
    }

    /// The zoom at which the picture fits the frame, in screen pt per image px.
    private var fitZoom: CGFloat {
        let width = CGFloat(core.drawing.pixels.width), height = CGFloat(core.drawing.pixels.height)
        guard width > 0, height > 0 else { return 0 }
        if pinUI.fittedWidth > 0 { return pinUI.fittedWidth / width }
        return bounds.isEmpty ? zoom : min(bounds.width / width, bounds.height / height)
    }

    /// A zoom step: the core hears where the picture sits, then the zoom, which redraws.
    func zoomChanged() {
        message(.viewChanged(fit: fitZoom, visible: resolution.visible))
        handle(.zoomChanged(zoom))
    }

    func showPins() {
        let placement = core.pinPlacement, outlined = core.outlinedPins
        let carded = hoverCardPin(placement)
        // The card covers its teardrop, so the teardrop's selection ring would show at its corner.
        let ringed = core.selection.subtracting(carded.map { [$0] } ?? [])
        pinUI.pins.show(EditorPins.Shown(placement: placement, outlined: core.drawing.pins.filter { outlined.contains($0.id) },
                                         marching: core.marchingPins, selected: ringed, markStyle: core.markStyle,
                                         outlineWidth: core.metrics.selectionOutlineWidth, dropScale: core.drawing.pointScale * core.fitZoom,
                                         marchSpeed: core.markStyle.pin.areaSpeed * Settings.shared.motionScale, transform: toView))
        pinUI.composer?.follow(anchor(of: pinUI.composer?.pin, in: placement), area: area(of: pinUI.composer?.pin))
        let resizing = core.composer != nil && core.gesture != nil
        if pinUI.resizingOpenPin, !resizing { pinUI.composer?.takeKeys() }
        pinUI.resizingOpenPin = resizing
        showPinElements(placement)
        showHoverCard(carded, placement)
        if pinUI.rotorOrder.count != pinUI.count {
            pinUI.count = pinUI.rotorOrder.count
            pinUI.onCount?(pinUI.count)
        }
    }

    /// The hovered pin with a number, drawn on its own, while no popover, menu or drag is under way:
    /// the one that grows into its card.
    private func hoverCardPin(_ placement: PinPlacement) -> Pin.ID? {
        let quiet = core.composer == nil && core.gesture == nil && pinUI.list == nil
        guard quiet, case .pin(let id)? = core.hover, let pin = core.pin(id), pin.number > 0,
              placement.drops.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private func showHoverCard(_ carded: Pin.ID?, _ placement: PinPlacement) {
        guard let id = carded, let pin = core.pin(id), let drop = placement.drops.first(where: { $0.id == id }) else {
            pinUI.hoverCard?.leave()
            pinUI.hoverCard = nil
            return
        }
        if pinUI.hoverCard?.pin != id {
            pinUI.hoverCard?.leave()
            let card = PinHoverCard(pin: id)
            addSubview(card)
            pinUI.hoverCard = card
        }
        pinUI.hoverCard?.show(pin, body: drop.square.applying(toView), orientation: drop.orientation, inside: visibleRect)
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

    /// Every pin with a number, in number order, in a menu under `rect` in `view`: the toolbar's Pins button.
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
        for pin in pins { menu.addItem(pinListItem(pin)) }
        pinUI.listActions.pick = { [weak self] id in DispatchQueue.main.async { self?.openFromList(id) } }
        pinUI.list = menu
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, let view, pinUI.list === menu else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: view.isFlipped ? rect.maxY : rect.minY), in: view)
            if pinUI.list === menu { pinUI.list = nil }
        }
    }

    /// A pin's row: its teardrop as it looks on screen, then its first comment on one line, an agent's
    /// in the system's monospaced face, as an agent's pin number is. The tooltip holds the comment whole.
    func pinListItem(_ pin: Pin) -> NSMenuItem {
        let ui = Settings.shared.data.ui, menuFont = NSFont.menuFont(ofSize: 0)
        let agent = pin.color == .agent
        let font = agent ? NSFont.monospacedSystemFont(ofSize: menuFont.pointSize, weight: .regular) : menuFont
        let first = pin.comments.first?.text.asOneLine ?? ""
        let item = NSMenuItem(title: "", action: #selector(PinListActions.picked(_:)), keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: SessionMenu.fitted(first, width: ui.pinListTitleWidth, font: font), attributes: [.font: font])
        item.target = pinUI.listActions
        item.representedObject = pin.id
        item.toolTip = pin.comments.first?.text
        item.setAccessibilityLabel("\(pin.spokenName): \(first)")
        item.image = Self.pinImage(number: pin.number, maker: pin.maker, side: ui.pinListImageSize, markStyle: core.markStyle)
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
        return item
    }

    /// The teardrop of a pin `maker` made, `side` pt across, wearing `number` or its maker's face, drawn
    /// flat, as a menu's row shows it.
    static func pinImage(number: Int, maker: PinMaker, side: CGFloat, markStyle: MarkStyle) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext, markStyle.pin.side > 0 else { return false }
            let pointScale = side / markStyle.pin.side, inset = markStyle.pin.rimWidth * pointScale
            let drop = PinTeardrop(number: number, agent: maker.isAgent, tip: CGPoint(x: rect.minX + inset, y: rect.maxY - inset), orientation: .upRight,
                                   side: side - 2 * inset, style: markStyle.pin)
            drop.drawFlat(in: ctx, maker: maker, face: PinFace(maker), pointScale: pointScale, markStyle: markStyle)
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

/// The target of a pin list's items: a pick names its pin.
final class PinListActions: NSObject {
    var pick: ((Pin.ID) -> Void)?

    @objc func picked(_ item: NSMenuItem) {
        if let id = item.representedObject as? Pin.ID { pick?(id) }
    }
}
