import AppKit

/// The pin popover's content: its rows, top to bottom, and the Command keys (`CommandKeyView`). Every
/// change moves. Each row sits in a slot whose height is a spring, and the rows are laid out from
/// those heights at every step, so a row that comes opens its slot, fading in as it is uncovered, a
/// row that goes folds its slot away, fading out, and the rows after them follow, never overlapping.
/// The popover's height is the slots' (`onHeight`). The foot, the last row, stretches with its slot
/// instead, so it grows and shrinks with the popover. A row that goes takes no presses and is gone from
/// VoiceOver. Each slot and each fade is a spring of its own, so a change that comes during another
/// keeps its velocity. A row is the same row from one change to the next while it is the same view.
@MainActor
final class PinPopoverColumn: CommandKeyView {
    /// The popover's height, at every step of its springs.
    var onHeight: ((CGFloat) -> Void)?
    /// Every row has come to rest, so a row that moved under a still pointer can say whether it is under it.
    var onSettle: (() -> Void)?
    /// The view the rows go under: the popover's rim.
    weak var cover: NSView?
    private let width: CGFloat
    private let inset: CGFloat
    private let spacing: CGFloat
    /// The rows top to bottom, those fading out kept where they were.
    private var order: [ObjectIdentifier] = []
    private var places: [ObjectIdentifier: Place] = [:]
    private var link: ScreenLink?
    /// The last step's time. The springs start at the first step, so main-thread work done with the
    /// change that started them delays their motion instead of skipping it.
    private var lastTick: CFTimeInterval?
    private var duration: Double = 0
    private var givenHeight: CGFloat?

    /// A row in its slot, which clips it while the row is taller than the slot. The slot holds the
    /// row's height and the spacing under it.
    private struct Place {
        let view: NSView
        let slot: NSView
        let top: NSLayoutConstraint
        let slotHeight: NSLayoutConstraint
        var rowHeight: CGFloat
        var extent: Spring
        var alpha: Spring
        var leaving: Bool

        var settled: Bool { extent.settled && alpha.settled }
    }

    /// A critically damped spring, stepped in closed form (`Tween.spring`).
    private struct Spring {
        var value: CGFloat
        var velocity: CGFloat = 0
        var target: CGFloat

        init(_ value: CGFloat) {
            self.value = value
            target = value
        }

        var settled: Bool { value == target && velocity == 0 }

        mutating func step(_ dt: Double, settling duration: Double) {
            guard !settled else { return }
            (value, velocity) = Tween.spring(value: value, velocity: velocity, target: target, settling: duration, dt: dt)
            if Tween.settled(value: value, velocity: velocity, target: target) {
                value = target
                velocity = 0
            }
        }
    }

    /// Rows `width` wide less `inset` on each side, `spacing` apart, `inset` from the top and the bottom.
    init(width: CGFloat, inset: CGFloat, spacing: CGFloat) {
        self.width = width
        self.inset = inset
        self.spacing = spacing
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: 2 * inset))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows `rows`, top to bottom, then `foot`, moving to them on springs that settle in `duration`,
    /// or at once when it is 0 or the column is not on screen yet.
    func show(_ rows: [NSView], foot: NSView, over duration: Double) {
        let moves = duration > 0 && window != nil && !NSScreen.screens.isEmpty
        self.duration = duration
        let rows = rows + [foot]
        let ids = rows.map(ObjectIdentifier.init)
        let kept = Set(ids)
        var merged = ids
        for (index, id) in order.enumerated() where !kept.contains(id) {
            guard moves, var place = places[id] else {
                places[id]?.slot.removeFromSuperview()
                places[id] = nil
                continue
            }
            place.leaving = true
            place.extent.target = 0
            place.alpha.target = 0
            places[id] = place
            let before = order[..<index].last { merged.contains($0) }
            merged.insert(id, at: before.flatMap { merged.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        }
        order = merged
        for row in rows {
            let id = ObjectIdentifier(row)
            let rowHeight = row.fittingSize.height
            var place = places[id] ?? add(row, opening: moves, stretching: row === foot)
            place.leaving = false
            place.rowHeight = rowHeight
            place.extent.target = rowHeight + spacing
            place.alpha.target = 1
            if !moves {
                place.extent = Spring(rowHeight + spacing)
                place.alpha = Spring(1)
            }
            places[id] = place
        }
        apply()
        if moves, !places.values.allSatisfy(\.settled) {
            if link == nil {
                lastTick = nil
                link = ScreenLink(self, #selector(tick))
            }
        } else {
            stopTicking()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        var view = hit
        while let ancestor = view, ancestor !== self {
            if places[ObjectIdentifier(ancestor)]?.leaving == true { return self }
            view = ancestor.superview
        }
        return hit
    }

    override func accessibilityChildren() -> [Any]? {
        let leaving = places.values.filter(\.leaving).map(\.view)
        return super.accessibilityChildren()?.filter { child in
            guard let view = child as? NSView else { return true }
            return !leaving.contains { view === $0 || view.isDescendant(of: $0) }
        }
    }

    /// A slot for `view`, shut and clear when it opens on screen. A stretching view is as tall as its slot.
    private func add(_ view: NSView, opening: Bool, stretching: Bool) -> Place {
        let slot = NSView()
        slot.wantsLayer = true
        slot.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        slot.addSubview(view)
        if let cover, cover.superview === self { addSubview(slot, positioned: .below, relativeTo: cover) } else { addSubview(slot) }
        let top = slot.topAnchor.constraint(equalTo: topAnchor, constant: inset)
        let slotHeight = slot.heightAnchor.constraint(equalToConstant: 0)
        [top, slotHeight, slot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
         slot.widthAnchor.constraint(equalToConstant: width - 2 * inset),
         view.topAnchor.constraint(equalTo: slot.topAnchor), view.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
         view.widthAnchor.constraint(equalTo: slot.widthAnchor)].forEach { $0.isActive = true }
        if stretching { view.bottomAnchor.constraint(equalTo: slot.bottomAnchor, constant: -spacing).isActive = true }
        return Place(view: view, slot: slot, top: top, slotHeight: slotHeight, rowHeight: 0, extent: Spring(0),
                     alpha: Spring(opening ? 0 : 1), leaving: false)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = lastTick.map { now - $0 } ?? 0
        lastTick = now
        for id in order {
            places[id]?.extent.step(dt, settling: duration)
            places[id]?.alpha.step(dt, settling: duration)
        }
        apply()
        if places.values.allSatisfy(\.settled) { stopTicking() }
    }

    /// Lays the slots out from their springs' heights, drops the rows that have folded away, and gives
    /// the popover its height.
    private func apply() {
        order.removeAll { id in
            guard let place = places[id], place.leaving, place.settled else { return false }
            place.slot.removeFromSuperview()
            places[id] = nil
            return true
        }
        var y = inset
        for id in order {
            guard let place = places[id] else { continue }
            if place.top.constant != y { place.top.constant = y }
            if place.slotHeight.constant != place.extent.value { place.slotHeight.constant = place.extent.value }
            if place.view.alphaValue != place.alpha.value { place.view.alphaValue = place.alpha.value }
            let clips = place.extent.value < place.rowHeight
            if place.slot.layer?.masksToBounds != clips { place.slot.layer?.masksToBounds = clips }
            y += place.extent.value
        }
        let height = order.isEmpty ? 2 * inset : max(2 * inset, y - spacing + inset)
        if givenHeight != height {
            givenHeight = height
            onHeight?(height)
        }
    }

    private func stopTicking() {
        guard let link else { return }
        link.invalidate()
        self.link = nil
        onSettle?()
    }
}

/// Fades in the pin popover, on `Tween`'s spring.
@MainActor
enum PopoverFade {
    private static var running: [ObjectIdentifier: (view: NSView, tween: Tween)] = [:]

    /// Fades `view` to `alpha` over `duration`, or sets it at once when that is 0 or the view is not on
    /// screen, then calls `then`. A fade already running turns toward the new alpha, unless `start`
    /// says where this one starts.
    static func alpha(_ view: NSView, from start: CGFloat? = nil, to alpha: CGFloat, over duration: Double, then: (() -> Void)? = nil) {
        let key = ObjectIdentifier(view)
        var current = running[key].flatMap { $0.view === view ? $0.tween : nil }
        if let start {
            current?.stop()
            current = nil
            running[key] = nil
            view.alphaValue = start
        }
        guard duration > 0, view.window != nil else {
            current?.stop()
            running[key] = nil
            view.alphaValue = alpha
            then?()
            return
        }
        let tween = current ?? Tween(initial: view.alphaValue) { [weak view] in view?.alphaValue = $0 }
        running[key] = (view, tween)
        tween.animate(to: alpha, duration: duration) {
            if running[key]?.tween === tween { running[key] = nil }
            then?()
        }
    }

    /// Changes a label with `change`. A copy of the label as it was fades out over it, and the label
    /// fades in under the copy when its words changed, or shows at once when only their colour did.
    static func change(_ label: NSTextField, over duration: Double, _ change: () -> Void) {
        let before = label.attributedStringValue
        let color = label.textColor
        change()
        guard duration > 0, label.window != nil, !label.isHidden, let superview = label.superview else { return }
        let after = label.attributedStringValue
        guard before != after else { return }
        if before.length > 0 { fadeOut(copy(of: before, color: color, like: label), at: label.frame, in: superview, above: label, over: duration) }
        if before.string != after.string, after.length > 0 { alpha(label, from: 0, to: 1, over: duration) }
    }

    /// `words` where `label` shows its own, fading out over `duration`: what a field's placeholder said.
    static func fadeOut(_ words: NSAttributedString, like label: NSTextField, over duration: Double) {
        guard duration > 0, label.window != nil, let superview = label.superview, words.length > 0 else { return }
        fadeOut(copy(of: words, color: nil, like: label), at: label.frame, in: superview, above: label, over: duration)
    }

    /// Changes a button's image with `change`, the old image fading out over the new one.
    static func change(_ button: NSButton, over duration: Double, _ change: () -> Void) {
        let before = button.image
        change()
        guard duration > 0, button.window != nil, button.alphaValue > 0, let before, before != button.image,
              let superview = button.superview else { return }
        let image = NSImageView(image: before)
        image.imageScaling = button.imageScaling
        image.contentTintColor = button.contentTintColor
        fadeOut(image, at: button.frame, in: superview, above: button, over: duration)
    }

    private static func copy(of words: NSAttributedString, color: NSColor?, like label: NSTextField) -> NSTextField {
        let copy = label.cell?.wraps == true ? NSTextField(wrappingLabelWithString: "") : NSTextField(labelWithString: "")
        copy.font = label.font
        if let color { copy.textColor = color }
        copy.lineBreakMode = label.lineBreakMode
        copy.maximumNumberOfLines = label.maximumNumberOfLines
        copy.attributedStringValue = words
        return copy
    }

    private static func fadeOut(_ ghost: NSView, at frame: CGRect, in superview: NSView, above view: NSView, over duration: Double) {
        ghost.translatesAutoresizingMaskIntoConstraints = true
        ghost.frame = frame
        ghost.setAccessibilityElement(false)
        superview.addSubview(ghost, positioned: .above, relativeTo: view)
        alpha(ghost, to: 0, over: duration) { ghost.removeFromSuperview() }
    }
}
