import AppKit
import SwiftUI

/// The target's darker fill while its menu is open, as a macOS pop-up button darkens. The menu opens
/// in the turn of the press and runs its own event loop until it closes, and a SwiftUI change made
/// inside that loop jumped instead of animating. So the shade is a layer whose spring is committed
/// before the menu opens, and the window server runs it.
final class TargetShade: NSView {
    /// How dark the shade is over the target's own fill, by appearance.
    private static let openOpacity: (dark: Float, light: Float) = (0.5, 0.14)
    private let shade = CALayer()
    private var open = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        shade.backgroundColor = NSColor.black.cgColor
        shade.cornerRadius = 7
        shade.cornerCurve = .continuous
        shade.opacity = 0
        layer?.addSublayer(shade)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shade.frame = bounds
        CATransaction.commit()
    }

    /// Springs the shade in or out. Each spring is added to the ones still running, so a menu that
    /// opens again while the shade is still leaving turns it around without a jump.
    func show(open: Bool) {
        guard open != self.open else { return }
        self.open = open
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let target: Float = open ? (dark ? Self.openOpacity.dark : Self.openOpacity.light) : 0
        let from = shade.opacity
        let duration = 0.12 * Settings.shared.motionScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shade.opacity = target
        if duration > 0 {
            let spring = CASpringAnimation(perceptualDuration: duration, bounce: 0)
            spring.keyPath = "opacity"
            spring.isAdditive = true
            spring.fromValue = from - target
            spring.toValue = 0
            spring.duration = spring.settlingDuration
            shade.add(spring, forKey: nil)
        }
        CATransaction.commit()
        CATransaction.flush()
    }
}

/// The target's own fill, with its shade over it.
struct TargetFill: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.09))
            TargetShadeSpot().allowsHitTesting(false)
        }
    }
}

private struct TargetShadeSpot: NSViewRepresentable {
    func makeNSView(context: Context) -> TargetShade { TargetShade() }
    func updateNSView(_ nsView: TargetShade, context: Context) {}
}

extension AnnotatorToolbar {
    /// The target's shade, wherever SwiftUI put it in the bar.
    var targetShade: TargetShade? { Self.shade(in: barView) }

    private static func shade(in view: NSView) -> TargetShade? {
        if let shade = view as? TargetShade { return shade }
        return view.subviews.lazy.compactMap { shade(in: $0) }.first
    }
}
