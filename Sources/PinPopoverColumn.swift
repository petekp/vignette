import AppKit

/// The pin popover's content: its rows, top to bottom, and the Command keys (`CommandKeyView`). Every
/// change moves. A row that comes fades in where it lands, a row that goes fades out where it was, the
/// rows after them slide to their places, and the height springs to the rows', which the popover
/// follows (`onHeight`). Each place, each fade and the height is a spring of its own, so a change
/// that comes during another keeps its velocity.
@MainActor
final class PinPopoverColumn: CommandKeyView {
    /// A row, under the key that names what it shows. A row given again with the same view stays and
    /// moves; a new view under an old key takes the old one's place, the two crossfading.
    struct Row {
        let key: String
        let view: NSView
    }

    /// The popover's height, at every step of its spring.
    var onHeight: ((CGFloat) -> Void)?
    /// The view the rows go under: the popover's rim.
    weak var cover: NSView?
    private let width: CGFloat
    private let inset: CGFloat
    private let spacing: CGFloat
    private var places: [ObjectIdentifier: Place] = [:]
    private var height = Spring(0)
    private var link: ScreenLink?
    private var lastTick: CFTimeInterval = 0
    private var duration: Double = 0
    private var givenHeight: CGFloat?

    /// A row's spot: its top's constraint, and the springs of its top and its fade. A row that goes
    /// keeps its spot until it has faded.
    private struct Place {
        let view: NSView
        let top: NSLayoutConstraint
        var y: Spring
        var alpha: Spring
        var leaving: Bool
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

    /// Shows `rows`, top to bottom, moving to them on springs that settle in `duration`, or at once
    /// when it is 0 or the column is not on screen yet.
    func show(_ rows: [Row], over duration: Double) {
        let moves = duration > 0 && window != nil && !NSScreen.screens.isEmpty
        self.duration = duration
        let kept = Set(rows.map { ObjectIdentifier($0.view) })
        for (id, place) in places where !kept.contains(id) {
            if moves {
                places[id]?.leaving = true
                places[id]?.alpha.target = 0
            } else {
                place.view.removeFromSuperview()
                places[id] = nil
            }
        }
        var y = inset
        for row in rows {
            let id = ObjectIdentifier(row.view)
            if var place = places[id] {
                place.leaving = false
                place.alpha.target = 1
                place.y.target = y
                if !moves {
                    place.y = Spring(y)
                    place.alpha = Spring(1)
                }
                places[id] = place
            } else {
                places[id] = add(row.view, at: y, fadingIn: moves)
            }
            y += row.view.fittingSize.height + spacing
        }
        height.target = rows.isEmpty ? 2 * inset : y - spacing + inset
        if !moves { height = Spring(height.target) }
        apply()
        if moves, !(height.settled && places.values.allSatisfy({ $0.y.settled && $0.alpha.settled })) {
            if link == nil {
                lastTick = CACurrentMediaTime()
                link = ScreenLink(self, #selector(tick))
            }
        } else {
            stopTicking()
        }
    }

    private func add(_ view: NSView, at y: CGFloat, fadingIn: Bool) -> Place {
        view.translatesAutoresizingMaskIntoConstraints = false
        if let cover, cover.superview === self { addSubview(view, positioned: .below, relativeTo: cover) } else { addSubview(view) }
        let top = view.topAnchor.constraint(equalTo: topAnchor, constant: y)
        [top, view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
                                     view.widthAnchor.constraint(equalToConstant: width - 2 * inset)].forEach { $0.isActive = true }
        var alpha = Spring(fadingIn ? 0 : 1)
        alpha.target = 1
        return Place(view: view, top: top, y: Spring(y), alpha: alpha, leaving: false)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = now - lastTick
        lastTick = now
        height.step(dt, settling: duration)
        for id in Array(places.keys) {
            places[id]?.y.step(dt, settling: duration)
            places[id]?.alpha.step(dt, settling: duration)
        }
        apply()
        if height.settled && places.values.allSatisfy({ $0.y.settled && $0.alpha.settled }) { stopTicking() }
    }

    /// Puts each row at its spring's place and fade, drops the rows that have faded out, and gives the
    /// popover its height.
    private func apply() {
        for (id, place) in places {
            if place.leaving && place.alpha.settled {
                place.view.removeFromSuperview()
                places[id] = nil
                continue
            }
            if place.top.constant != place.y.value { place.top.constant = place.y.value }
            if place.view.alphaValue != place.alpha.value { place.view.alphaValue = place.alpha.value }
        }
        if givenHeight != height.value {
            givenHeight = height.value
            onHeight?(height.value)
        }
    }

    private func stopTicking() {
        link?.invalidate()
        link = nil
    }
}

/// Fades in the pin popover, on `Tween`'s spring.
@MainActor
enum PopoverFade {
    private static var running: [ObjectIdentifier: (view: NSView, tween: Tween)] = [:]

    /// Fades `view` to `alpha` over `duration`, or sets it at once when that is 0 or the view is not on
    /// screen, then calls `then`. A fade already running turns toward the new alpha.
    static func alpha(_ view: NSView, to alpha: CGFloat, over duration: Double, then: (() -> Void)? = nil) {
        let key = ObjectIdentifier(view)
        let current = running[key].flatMap { $0.view === view ? $0.tween : nil }
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
        if before.string != after.string, after.length > 0 {
            label.alphaValue = 0
            alpha(label, to: 1, over: duration)
        }
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
