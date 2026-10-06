import AppKit

/// The buttons under a session's answer, one for each action it offered, such as "Fix both": the
/// first filled in the agent's colour, the rest outlined in it. A click sends the button's words
/// back to the session (`LiveInk.act`). A panel of its own, so a click on it never reaches the
/// window under the answer, and one that never takes the keys.
@MainActor
final class LiveAnswerActions: NSPanel {
    var onPick: ((String) -> Void)?

    private var hiding = false

    /// A button's height, its side padding and the gap between buttons, in points, and the room
    /// round the row for the buttons' shadows.
    static let height: CGFloat = 26
    private static let pad: CGFloat = 12
    private static let gap: CGFloat = 6
    private static let margin: CGFloat = 6
    /// The room an answer keeps under its reply for the row.
    static let room: CGFloat = height + 8

    /// Opens with its first button's top-left corner at `corner`, in global top-left points.
    init(_ actions: [String], at corner: CGPoint, color: CGColor) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        var x = Self.margin
        let row = NSView()
        row.wantsLayer = true
        for (index, action) in actions.enumerated() {
            let width = ceil((action as NSString).size(withAttributes: [.font: font]).width) + Self.pad * 2
            let button = ActionButton(frame: CGRect(x: x, y: Self.margin, width: width, height: Self.height),
                                      title: action, font: font, color: color, filled: index == 0)
            button.onClick = { [weak self] in self?.onPick?(action) }
            row.addSubview(button)
            x += width + Self.gap
        }
        let size = CGSize(width: x - Self.gap + Self.margin, height: Self.height + Self.margin * 2)
        row.frame = CGRect(origin: .zero, size: size)
        contentView = row
        setContentSize(size)
        place(at: corner)

        let motion = Settings.shared.motionScale
        alphaValue = 0
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

    /// The buttons, in global top-left points.
    var globalFrame: CGRect {
        CGRect(x: frame.minX, y: StateReport.primaryHeight - frame.maxY, width: frame.width, height: frame.height)
            .insetBy(dx: Self.margin, dy: Self.margin)
    }

    /// Each button's words and frame, in global top-left points, for `[state]`.
    var buttons: [(title: String, frame: CGRect)] {
        (contentView?.subviews ?? []).compactMap { view -> (title: String, frame: CGRect)? in
            guard let button = view as? ActionButton else { return nil }
            let rect = convertToScreen(button.convert(button.bounds, to: nil))
            return (button.title, CGRect(x: rect.minX, y: StateReport.primaryHeight - rect.maxY, width: rect.width, height: rect.height))
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

    /// Fades out and closes.
    func hide() {
        guard !hiding else { return }
        hiding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15 * Settings.shared.motionScale
            animator().alphaValue = 0
        } completionHandler: {
            self.orderOut(nil)
            self.close()
        }
    }

    /// A pill that takes a press without activating the app, and counts a release inside it as the click.
    private final class ActionButton: NSView {
        var onClick: (() -> Void)?
        let title: String
        private let pill = CALayer()

        init(frame: CGRect, title: String, font: NSFont, color: CGColor, filled: Bool) {
            self.title = title
            super.init(frame: frame)
            wantsLayer = true
            pill.frame = bounds
            pill.cornerRadius = bounds.height / 2
            pill.backgroundColor = filled ? color : CGColor(gray: 1, alpha: 1)
            pill.borderColor = filled ? CGColor(gray: 1, alpha: 1) : color
            pill.borderWidth = 1.5
            pill.shadowColor = CGColor(gray: 0, alpha: 1)
            pill.shadowOpacity = 0.22
            pill.shadowRadius = 3
            pill.shadowOffset = CGSize(width: 0, height: -1)
            layer?.addSublayer(pill)
            let label = CATextLayer()
            label.string = NSAttributedString(string: title, attributes: [
                .font: font, .foregroundColor: filled ? NSColor.white : (NSColor(cgColor: color) ?? .labelColor),
            ])
            label.alignmentMode = .center
            label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            let lineHeight = ceil(font.ascender - font.descender)
            label.frame = CGRect(x: 0, y: (bounds.height - lineHeight) / 2, width: bounds.width, height: lineHeight)
            pill.addSublayer(label)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) { pill.opacity = 0.75 }

        override func mouseUp(with event: NSEvent) {
            pill.opacity = 1
            if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
        }
    }
}
