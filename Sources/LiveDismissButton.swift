import AppKit

/// The × that takes a session's answer off the screen, shown at the top-left corner of the answer's
/// note while the pointer is over it, as a notification's close button is. A panel of its own, so a
/// click on it never reaches the window under the answer, and one that never takes the keys.
@MainActor
final class LiveDismissButton: NSPanel {
    var onClick: (() -> Void)?

    private let disc = CAShapeLayer()
    private let cross = CAShapeLayer()
    private var hiding = false

    /// The disc's diameter, in points, and the room round it for its shadow.
    private static let size: CGFloat = 20
    private static let margin: CGFloat = 6

    /// Opens centred on `corner`, in global top-left points.
    init(at corner: CGPoint) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        let side = Self.size + Self.margin * 2
        let view = ClickView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view.wantsLayer = true
        view.onPress = { [weak self] pressed in self?.disc.opacity = pressed ? 0.8 : 1 }
        view.onClick = { [weak self] in self?.onClick?() }
        contentView = view
        let rect = CGRect(x: Self.margin, y: Self.margin, width: Self.size, height: Self.size)
        disc.frame = rect
        disc.path = CGPath(ellipseIn: CGRect(origin: .zero, size: rect.size), transform: nil)
        disc.fillColor = CGColor(gray: 0.97, alpha: 1)
        disc.strokeColor = CGColor(gray: 0, alpha: 0.18)
        disc.lineWidth = 0.5
        disc.shadowColor = CGColor(gray: 0, alpha: 1)
        disc.shadowOpacity = 0.28
        disc.shadowRadius = 2.5
        disc.shadowOffset = CGSize(width: 0, height: -1)
        let arm = Self.size * 0.17, middle = Self.size / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: middle - arm, y: middle - arm))
        path.addLine(to: CGPoint(x: middle + arm, y: middle + arm))
        path.move(to: CGPoint(x: middle - arm, y: middle + arm))
        path.addLine(to: CGPoint(x: middle + arm, y: middle - arm))
        cross.path = path
        cross.strokeColor = CGColor(gray: 0.3, alpha: 1)
        cross.lineWidth = 1.6
        cross.lineCap = .round
        disc.addSublayer(cross)
        view.layer?.addSublayer(disc)

        place(at: corner)
        alphaValue = 0
        orderFrontRegardless()
        let motion = Settings.shared.motionScale
        let grow = CASpringAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.5
        grow.toValue = 1
        grow.stiffness = 400
        grow.damping = 18
        grow.duration = grow.settlingDuration
        if motion > 0 { disc.add(grow, forKey: "grow") }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12 * motion
            animator().alphaValue = 1
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The disc, in global top-left points.
    var globalFrame: CGRect {
        CGRect(x: frame.minX, y: StateReport.primaryHeight - frame.maxY, width: frame.width, height: frame.height)
            .insetBy(dx: Self.margin, dy: Self.margin)
    }

    /// Centres the disc on `corner`, in global top-left points, as the note moves with its window.
    func place(at corner: CGPoint) {
        let side = Self.size + Self.margin * 2
        let origin = CGPoint(x: corner.x - side / 2, y: StateReport.primaryHeight - corner.y - side / 2)
        guard abs(origin.x - frame.minX) > 0.25 || abs(origin.y - frame.minY) > 0.25 || frame.width != side else { return }
        setFrame(CGRect(origin: origin, size: CGSize(width: side, height: side)), display: true)
    }

    /// Fades out and closes.
    func hide() {
        guard !hiding else { return }
        hiding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12 * Settings.shared.motionScale
            animator().alphaValue = 0
        } completionHandler: {
            self.orderOut(nil)
            self.close()
        }
    }

    /// Takes a press without activating the app, and counts a release inside it as the click.
    private final class ClickView: NSView {
        var onPress: ((Bool) -> Void)?
        var onClick: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) { onPress?(true) }

        override func mouseUp(with event: NSEvent) {
            onPress?(false)
            if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
        }
    }
}
