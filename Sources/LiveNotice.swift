import AppKit

/// A line that says what live ink needs, drawn beside the pointer while the chord is held: the
/// overlay adds it, and it fades in and out with `Settings.motionUI`'s scale.
@MainActor
final class LiveNotice: NSView {
    /// How long the notice stays up, before its fade-out.
    static let duration: TimeInterval = 4

    private let label: NSTextField
    private var hideTimer: Timer?

    init(text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        label.preferredMaxLayoutWidth = 260
        addSubview(label)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        layer?.cornerRadius = 8
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// Places the notice so its top-left is `origin` in its superview's coordinates, and fades it in.
    func show(at origin: CGPoint) {
        label.sizeToFit()
        let inset: CGFloat = 10
        frame = CGRect(origin: origin, size: CGSize(width: label.frame.width + 2 * inset, height: label.frame.height + 2 * inset))
        label.frame.origin = CGPoint(x: inset, y: inset)
        fade(to: 1)
        hideTimer = Timer.scheduledTimer(withTimeInterval: Self.duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    /// Fades out and leaves its superview.
    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        NSAnimationContext.runAnimationGroup({ [weak self] context in
            context.duration = 0.2 * Settings.shared.motionScale
            self?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.removeFromSuperview() }
        })
    }

    private func fade(to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2 * Settings.shared.motionScale
            animator().alphaValue = alpha
        }
    }
}
