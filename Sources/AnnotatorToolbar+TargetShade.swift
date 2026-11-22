import AppKit
import SwiftUI

/// The target's darker fill while its menu is open, as a macOS pop-up button darkens. The menu opens
/// in the turn of the press and runs its own event loop until it closes, and a SwiftUI change made
/// inside that loop jumped instead of animating. So the shade is a layer whose spring is committed
/// before the menu opens, and the window server runs it.
/// Inside the message field's box, the target is parted from the words by a hairline at its
/// trailing edge, which gives way to the shade on the same spring.
final class TargetShade: NSView {
    /// How dark the shade is over the target's own fill, by appearance.
    private static let openOpacity: (dark: Float, light: Float) = (0.5, 0.14)
    private static let hairlineHeight: CGFloat = 16
    private let shade = CALayer()
    private let hairline = CALayer()
    private var open = false
    /// Nil until SwiftUI first says, which sets the hairline without a spring.
    private var joined: Bool?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        shade.backgroundColor = NSColor.black.cgColor
        shade.cornerRadius = 7
        shade.cornerCurve = .continuous
        shade.opacity = 0
        hairline.opacity = 0
        layer?.addSublayer(shade)
        layer?.addSublayer(hairline)
        colorHairline()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shade.frame = bounds
        hairline.frame = CGRect(x: bounds.maxX - 1, y: (bounds.height - Self.hairlineHeight) / 2, width: 1, height: Self.hairlineHeight)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        colorHairline()
    }

    private func colorHairline() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            hairline.backgroundColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
        }
        CATransaction.commit()
    }

    private var hairlineOpacity: Float { joined == true && !open ? 1 : 0 }

    /// The target sits inside the message field's box, or alone with its own fill.
    func join(_ joined: Bool) {
        guard joined != self.joined else { return }
        let first = self.joined == nil
        self.joined = joined
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shade.maskedCorners = joined ? [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        if first { hairline.opacity = hairlineOpacity } else { spring(hairline, to: hairlineOpacity) }
        CATransaction.commit()
    }

    /// Springs the shade in or out. Each spring is added to the ones still running, so a menu that
    /// opens again while the shade is still leaving turns it around without a jump.
    func show(open: Bool) {
        guard open != self.open else { return }
        self.open = open
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spring(shade, to: open ? (dark ? Self.openOpacity.dark : Self.openOpacity.light) : 0)
        spring(hairline, to: hairlineOpacity)
        CATransaction.commit()
        CATransaction.flush()
    }

    private func spring(_ layer: CALayer, to target: Float) {
        let from = layer.opacity
        guard from != target else { return }
        layer.opacity = target
        let duration = 0.12 * Settings.shared.motionScale
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
/// box is its fill.
struct TargetFill: View {
    let joined: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(joined ? 0 : 0.09))
            TargetShadeSpot(joined: joined).allowsHitTesting(false)
        }
    }
}

private struct TargetShadeSpot: NSViewRepresentable {
    let joined: Bool
    func makeNSView(context: Context) -> TargetShade { TargetShade() }
    func updateNSView(_ nsView: TargetShade, context: Context) { nsView.join(joined) }
}

extension AnnotatorToolbar {
    /// The target's shade, wherever SwiftUI put it in the bar.
    var targetShade: TargetShade? { Self.shade(in: barView) }

    private static func shade(in view: NSView) -> TargetShade? {
        if let shade = view as? TargetShade { return shade }
        return view.subviews.lazy.compactMap { shade(in: $0) }.first
    }
}
