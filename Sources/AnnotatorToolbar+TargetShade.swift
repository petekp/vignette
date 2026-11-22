import AppKit
import SwiftUI

/// The target's darker fill while its menu is open, as a macOS pop-up button darkens. The menu opens
/// in the turn of the press and runs its own event loop until it closes, and a SwiftUI change made
/// inside that loop jumped instead of animating. So the shade is a layer whose spring is committed
/// before the menu opens, and the window server runs it.
/// Inside the message field's box, the target is parted from the words by a hairline at its
/// trailing edge, which gives way to the shade on the same spring. There every highlight the target
/// shows is one rounded rectangle inset in the box and short of the hairline, its corners concentric
/// with the box's, so nothing it draws meets the box's edge or the box's focus ring: the shade,
/// faint under the pointer and darker while the menu is open, and the keyboard's focus ring,
/// drawn inside that same rectangle.
final class TargetShade: NSView {
    /// How dark the shade is over the target's own fill, by appearance.
    private static let openOpacity: (dark: Float, light: Float) = (0.5, 0.14)
    private static let hoverOpacity: (dark: Float, light: Float) = (0.22, 0.06)
    private static let hairlineHeight: CGFloat = 16
    private static let hairlineWidth: CGFloat = 1
    /// The corner radius of the target's own fill and of the message field's box.
    private static let radius: CGFloat = 7
    /// 5 pixels at 2x. The box's focus ring reaches 0.5 pt inside its edge.
    private static let insetInBox: CGFloat = 2.5
    /// 4 pixels at 2x, inside the inset rectangle.
    private static let focusRingWidth: CGFloat = 2
    private let shade = CALayer()
    private let focusRing = CALayer()
    private let hairline = CALayer()
    private var open = false
    private var hovered = false
    private var focused = false
    /// Nil until SwiftUI first says, which sets the hairline without a spring.
    private var joined: Bool?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        shade.backgroundColor = NSColor.black.cgColor
        shade.cornerCurve = .continuous
        shade.opacity = 0
        focusRing.cornerCurve = .continuous
        focusRing.borderWidth = Self.focusRingWidth
        focusRing.opacity = 0
        hairline.opacity = 0
        layer?.addSublayer(shade)
        layer?.addSublayer(focusRing)
        layer?.addSublayer(hairline)
        colorLayers()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeShade()
        hairline.frame = CGRect(x: bounds.maxX - Self.hairlineWidth, y: (bounds.height - Self.hairlineHeight) / 2,
                                width: Self.hairlineWidth, height: Self.hairlineHeight)
        CATransaction.commit()
    }

    private func placeShade() {
        guard joined == true else {
            shade.frame = bounds
            shade.cornerRadius = Self.radius
            focusRing.frame = bounds
            focusRing.cornerRadius = Self.radius
            return
        }
        let inset = Self.insetInBox
        let frame = CGRect(x: inset, y: inset,
                           width: max(0, bounds.width - Self.hairlineWidth - 2 * inset),
                           height: max(0, bounds.height - 2 * inset))
        shade.frame = frame
        shade.cornerRadius = Self.radius - inset
        focusRing.frame = frame
        focusRing.cornerRadius = Self.radius - inset
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        colorLayers()
        apply(animated: false)
    }

    private func colorLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            hairline.backgroundColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
            focusRing.borderColor = NSColor.keyboardFocusIndicatorColor.cgColor
        }
        CATransaction.commit()
    }

    private var hairlineOpacity: Float { joined == true && !open ? 1 : 0 }

    /// The menu open, or else the pointer on the target inside the box. The target alone draws its
    /// own hover fill (`TargetFill`).
    private var shadeOpacity: Float {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if open { return dark ? Self.openOpacity.dark : Self.openOpacity.light }
        if hovered && joined == true { return dark ? Self.hoverOpacity.dark : Self.hoverOpacity.light }
        return 0
    }

    /// The target alone takes SwiftUI's focus ring around it (`FocusRing`).
    private var focusRingOpacity: Float { focused && joined == true ? 1 : 0 }

    /// The target sits inside the message field's box, or alone with its own fill.
    func join(_ joined: Bool) {
        guard joined != self.joined else { return }
        let first = self.joined == nil
        self.joined = joined
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeShade()
        CATransaction.commit()
        apply(animated: !first)
    }

    /// The pointer is on the target, and the keyboard's focus is on it.
    func set(hovered: Bool, focused: Bool) {
        guard hovered != self.hovered || focused != self.focused else { return }
        self.hovered = hovered
        self.focused = focused
        apply(animated: true)
    }

    /// Springs the shade in or out for the menu. Each spring is added to the ones still running, so a
    /// menu that opens again while the shade is still leaving turns it around without a jump.
    func show(open: Bool) {
        guard open != self.open else { return }
        self.open = open
        apply(animated: true)
        CATransaction.flush()
    }

    private func apply(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spring(shade, to: shadeOpacity, duration: animated ? 0.12 : 0)
        spring(hairline, to: hairlineOpacity, duration: animated ? 0.12 : 0)
        spring(focusRing, to: focusRingOpacity, duration: animated ? 0.2 : 0)
        CATransaction.commit()
    }

    private func spring(_ layer: CALayer, to target: Float, duration: Double) {
        let from = layer.opacity
        guard from != target else { return }
        layer.opacity = target
        let duration = duration * Settings.shared.motionScale
        guard duration > 0 else { return }
        let spring = CASpringAnimation(perceptualDuration: duration, bounce: 0)
        spring.keyPath = "opacity"
        spring.isAdditive = true
        spring.fromValue = from - target
        spring.toValue = 0
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: nil)
    }
}

/// The target's own fill, with its shade over it. Inside the message field's box (`joined`), the
/// box is its fill, and the shade draws the hover and the keyboard's focus ring inset in it. Alone,
/// it lightens under the pointer as the bar's other buttons do (`TactileButtonStyle`).
struct TargetFill: View {
    let joined: Bool
    let hovered: Bool
    let focused: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovered && !joined ? 0.18 : 0))
                .animation(Anim.spring(0.12 * Settings.shared.motionScale), value: hovered)
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(joined ? 0 : 0.09))
            TargetShadeSpot(joined: joined, hovered: hovered, focused: focused).allowsHitTesting(false)
        }
    }
}

/// The target's button: no fill of its own, which `TargetFill` draws. Alone, a press shrinks it as
/// `TactileButtonStyle` does. Inside the box it stays put, since the box does not move with it.
struct TargetButtonStyle: ButtonStyle {
    let joined: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .animation(Anim.spring(0.2 * Settings.shared.motionScale, bounce: 0.3)) {
                $0.scaleEffect(configuration.isPressed && !joined ? 0.9 : 1)
            }
    }
}

private struct TargetShadeSpot: NSViewRepresentable {
    let joined: Bool
    let hovered: Bool
    let focused: Bool
    func makeNSView(context: Context) -> TargetShade { TargetShade() }
    func updateNSView(_ nsView: TargetShade, context: Context) {
        nsView.join(joined)
        nsView.set(hovered: hovered, focused: focused)
    }
}

extension AnnotatorToolbar {
    /// The target's shade, wherever SwiftUI put it in the bar.
    var targetShade: TargetShade? { Self.shade(in: barView) }

    private static func shade(in view: NSView) -> TargetShade? {
        if let shade = view as? TargetShade { return shade }
        return view.subviews.lazy.compactMap { shade(in: $0) }.first
    }
}
