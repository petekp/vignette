import AppKit

/// The buttons under a session's answer, one for each action it offered, such as "Fix both": AppKit's
/// own push buttons, so they look as a popover's buttons do on each version of macOS. A click sends
/// the button's words back to the session (`LiveInk.act`), and the buttons then stay, all disabled,
/// with a checkmark on the one picked (`pick`). A panel of its own, so a click on it never reaches the
/// window under the answer, and one that never takes the keys. It is a child of the reply's window,
/// so a window raised over the answer covers it too. Pointing at a button reports its action
/// (`onPoint`), and leaving the buttons reports nil.
///
/// macOS draws them as it draws any control in an app that is not frontmost, which Vignette never is
/// while an answer shows, so none is filled with the accent colour, the recommended first one included.
@MainActor
final class LiveAnswerActions: NSPanel {
    var onPick: ((String) -> Void)?
    var onPoint: ((LiveAnswer.Action?) -> Void)?

    private var hiding = false
    private let row: NSStackView

    /// A button's height on this version of macOS, in points.
    static let height: CGFloat = ActionButton(title: "").intrinsicContentSize.height
    /// The room round the row for the buttons' shadows, in points.
    private static let margin: CGFloat = 6
    /// The room an answer keeps under its reply for the row.
    static let room: CGFloat = height + 8

    /// Opens with its first button's top-left corner at `corner`, in global top-left points, over
    /// `reply`, with `picked`'s button already checked.
    init(_ actions: [LiveAnswer.Action], at corner: CGPoint, over reply: ReplyPopover, picked: String?) {
        row = NSStackView()
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        for action in actions {
            let button = ActionButton(title: action.title)
            button.target = self
            button.action = #selector(clicked(_:))
            button.onHover = { [weak self] inside in self?.onPoint?(inside ? action : nil) }
            row.addArrangedSubview(button)
        }
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: Self.margin, left: Self.margin, bottom: Self.margin, right: Self.margin)
        row.wantsLayer = true
        contentView = row
        if let picked { check(picked) }
        setContentSize(row.fittingSize)
        place(at: corner)

        let motion = Settings.shared.motionScale
        alphaValue = 0
        reply.carry(self)
        orderFrontRegardless()
        let final = frame
        setFrame(final.offsetBy(dx: 0, dy: motion > 0 ? 4 : 0), display: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2 * motion
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(final, display: true)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var buttonViews: [ActionButton] { row.arrangedSubviews.compactMap { $0 as? ActionButton } }

    /// The buttons, in global top-left points.
    var globalFrame: CGRect {
        CGRect(x: frame.minX, y: StateReport.primaryHeight - frame.maxY, width: frame.width, height: frame.height)
            .insetBy(dx: Self.margin, dy: Self.margin)
    }

    /// Each button's words, its frame as drawn, in global top-left points, and whether it was picked,
    /// for `[state]`.
    var buttons: [(title: String, frame: CGRect, enabled: Bool, picked: Bool)] {
        buttonViews.map { button in
            let rect = convertToScreen(button.convert(button.alignmentRect(forFrame: button.bounds), to: nil))
            return (button.title, CGRect(x: rect.minX, y: StateReport.primaryHeight - rect.maxY, width: rect.width, height: rect.height),
                    button.isEnabled, button.image != nil)
        }
    }

    /// Puts the first button's top-left corner at `corner`, in global top-left points, as the
    /// answer moves with its window, or as near it as keeps the row on the screen.
    func place(at corner: CGPoint) {
        var origin = CGPoint(x: corner.x - Self.margin, y: StateReport.primaryHeight - corner.y - frame.height + Self.margin)
        let point = CGPoint(x: origin.x, y: origin.y + frame.height / 2)
        if let visible = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame {
            origin.x = max(visible.minX + 8 - Self.margin, min(origin.x, visible.maxX - 8 + Self.margin - frame.width))
            origin.y = max(visible.minY + 8 - Self.margin, origin.y)
        }
        guard abs(origin.x - frame.minX) > 0.25 || abs(origin.y - frame.minY) > 0.25 else { return }
        setFrameOrigin(origin)
    }

    /// The person picked `title`: every button is disabled and that one gains a checkmark, which
    /// widens it, so the row cross-fades to its new layout and the panel grows to the right.
    func pick(_ title: String) {
        let fade = 0.15 * Settings.shared.motionScale
        if fade > 0 {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = fade
            row.layer?.add(transition, forKey: "pick")
        }
        check(title)
        let top = frame.maxY
        let size = row.fittingSize
        setFrame(CGRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    private func check(_ title: String) {
        for button in buttonViews {
            button.isEnabled = false
            if button.title == title {
                button.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
                button.imagePosition = .imageLeading
            }
        }
    }

    @objc private func clicked(_ sender: ActionButton) { onPick?(sender.title) }

    /// Fades out and closes.
    func hide() {
        guard !hiding else { return }
        hiding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15 * Settings.shared.motionScale
            animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                self.parent?.removeChildWindow(self)
                self.orderOut(nil)
                self.close()
            }
        }
    }

    /// A push button that takes a click without activating the app, and reports the pointer while enabled.
    private final class ActionButton: NSButton {
        var onHover: ((Bool) -> Void)?
        private var hoverArea: NSTrackingArea?

        convenience init(title: String) {
            self.init(frame: .zero)
            self.title = title
            bezelStyle = .push
            controlSize = .large
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // The app is never active while the answer shows, so the area tracks whatever app is.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            hoverArea.map(removeTrackingArea)
            let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
            addTrackingArea(area)
            hoverArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            if isEnabled { onHover?(true) }
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            if isEnabled { onHover?(false) }
        }
    }
}
