import AppKit

// MARK: The target's menu

extension AnnotatorToolbar {
    /// A press on the target opens its menu at once, as a macOS pop-up button does. AppKit's menu
    /// tracking then has the press: dragging onto a row and releasing picks it, and a release with no
    /// drag leaves the menu open for a second click. The press reaches the target where its button
    /// would take it, the box and its slop, and not while a send is under way (`Resting`) or the bar
    /// is leaving.
    func pressTarget(_ event: NSEvent) -> Bool {
        guard model.shown, model.offer.offersTarget, !model.sending, let frame = targetFrame else { return false }
        let point = barView.convert(event.locationInWindow, from: nil)
        let pressed = CGPoint(x: point.x, y: barView.isFlipped ? point.y : barView.bounds.height - point.y)
        let slop = Self.targetSlop
        let pressable = CGRect(x: frame.minX - slop.leading, y: frame.minY - slop.top,
                               width: frame.width + slop.leading + slop.trailing, height: frame.height + slop.top + slop.bottom)
        guard pressable.contains(pressed) else { return false }
        showTargetMenu()
        return true
    }

    /// Space on the target, or an arrow off the message field, opens the menu a turn later. Opened
    /// from inside the editor's keyDown, the menu took no keys and read a press on its items as one
    /// outside the editor.
    func openTargetMenuFromKeys() {
        DispatchQueue.main.async { [weak self] in self?.showTargetMenu(fromKeys: true) }
    }

    /// The target's menu under it, with the rows `SessionMenu` orders and the target checked, and
    /// the likeliest other session first. AppKit's own menu, so Space on the focused target opens it
    /// as a press does. Opened from the keyboard (`fromKeys`), it opens with the first row
    /// highlighted, the row Return picks. The target looks pressed until the menu closes, however
    /// it closes, since `popUp` returns only then.
    func showTargetMenu(fromKeys: Bool = false) {
        guard model.offer.offersTarget, let frame = targetFrame else { return }
        let target = model.offer.destination
        let menu = NSMenu()
        menu.autoenablesItems = false
        let sessions = SessionMenu.menu(model.destinations + model.startable, destination: target, targetNotFirst: true)
        let search = SessionMenu.add(sessions, to: menu, highlightingFirstRow: fromKeys) { row in
            let item = SessionMenu.item(for: row, selected: row.id == target?.id)
            item.target = self.targetMenuActions
            item.action = #selector(TargetMenuActions.pick(_:))
            item.representedObject = row.destination
            return item
        }
        targetMenuActions.open = (menu, sessions, search)
        let below = barView.isFlipped ? frame.maxY + 4 : barView.bounds.height - frame.maxY - 4
        targetShade?.show(open: true)
        _ = menu.popUp(positioning: nil, at: NSPoint(x: frame.minX, y: below), in: barView)
        targetShade?.show(open: false)
    }
}
