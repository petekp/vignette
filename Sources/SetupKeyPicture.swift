import AppKit
import SwiftUI

/// The shortcut as keys on a keyboard: one wide keycap marked ×2 for a double tap, or a keycap for
/// each key of a combination. A modifier's keycap goes down while the person holds that key, so
/// the picture answers their hand before the shortcut works. Each time the shortcut fires, the ×2
/// turns into a check.
struct KeyPicture: View {
    let spec: HotKeySpec?
    var fires = 0
    /// `Settings.motionScale`: 0 with Reduce Motion, and then a held key darkens without moving.
    var motion = 1.0
    @StateObject private var held = HeldModifiers()
    /// The check's width, a little more than the ×2's height.
    private static let checkDiameter: CGFloat = 24

    var body: some View {
        Group {
            if let key = spec?.doubleTapKey, case let .doubleTap(code)? = spec {
                // A right-hand modifier has its label on the right, as Apple's keyboards print it.
                keycap(width: 118, down: held.codes.contains(code)) {
                    VStack(alignment: key.isRight ? .trailing : .leading) {
                        Text(key.glyph).font(.system(size: 17))
                        Spacer()
                        Text(key.word).font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity, alignment: key.isRight ? .trailing : .leading)
                }
                // The badge takes the corner the label leaves free.
                .overlay(alignment: key.isRight ? .topLeading : .topTrailing) {
                    badge.offset(x: key.isRight ? -10 : 10, y: -10)
                }
            } else {
                let modifiers = spec?.keycapModifiers ?? []
                HStack(spacing: 8) {
                    ForEach(Array((spec?.keycaps ?? []).enumerated()), id: \.offset) { index, cap in
                        let modifier = index < modifiers.count ? modifiers[index] : []
                        keycap(width: 56, down: !modifier.isEmpty && held.flags.contains(modifier)) {
                            Text(cap).font(.system(size: 20)).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if fires > 0 { badge.offset(x: 10, y: -10).transition(.scale.combined(with: .opacity)) }
                }
                // The combination's own key never reaches the window, since the hotkey takes it, so
                // its firing is what presses the picture.
                .keyframeAnimator(initialValue: 1.0, trigger: fires) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    CubicKeyframe(motion > 0 ? 0.94 : 1, duration: 0.07)
                    SpringKeyframe(1, duration: 0.35 * max(motion, 0.01), spring: .bouncy)
                }
            }
        }
        .animation(Anim.spring(0.3 * motion), value: fires > 0)
        .onAppear { held.start() }
        .onDisappear { held.stop() }
        .accessibilityHidden(true)
    }

    /// ×2 until the shortcut has worked, then the check on a copied or sent card (`CheckCoin`),
    /// which spins as it appears.
    @ViewBuilder private var badge: some View {
        if fires > 0 {
            CheckCoin(diameter: Self.checkDiameter)
                .transition(.scale.combined(with: .opacity))
        } else {
            Text("×2").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(minWidth: 18, minHeight: 17)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor))
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func keycap<Content: View>(width: CGFloat, down: Bool, @ViewBuilder _ content: @escaping () -> Content) -> some View {
        KeyboardKey(width: width, down: down, motion: motion, content: content)
    }
}

/// A keycap, raised on its shadow, or `down`: sunk onto the surface, a shade darker and a little
/// smaller. It goes down at once, as a key does, and springs back up.
struct KeyboardKey<Content: View>: View {
    let width: CGFloat
    var height: CGFloat = 56
    let down: Bool
    let motion: Double
    /// Between the cap's edge and what is printed on it.
    var inset: CGFloat = 8
    /// The colour the cap's edge lights in while it is down, if any.
    var light: Color? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        let moves = motion > 0
        let cap = RoundedRectangle(cornerRadius: min(9, height / 4), style: .continuous)
        let lit = down && light != nil
        return content()
            .foregroundStyle(.secondary)
            .padding(inset)
            .frame(width: width, height: height)
            .background(cap.fill(Color(nsColor: .controlColor))
                .brightness(down ? -0.08 : 0)
                .shadow(color: .black.opacity(down ? 0 : 0.25), radius: 1, y: down ? 0 : 1))
            .overlay(cap.strokeBorder(light ?? .clear, lineWidth: 1.5).opacity(lit ? 1 : 0))
            .shadow(color: (light ?? .clear).opacity(lit ? 0.8 : 0), radius: lit ? 7 : 0)
            .scaleEffect(down && moves ? 0.95 : 1)
            .offset(y: down && moves ? 1 : 0)
            .animation(down ? Anim.spring(0.06 * motion) : Anim.spring(0.3 * motion, bounce: 0.4), value: down)
    }
}

/// Which modifier keys the person is holding, by key code, so a picture of a key can go down with
/// it. It hears them while a Vignette window is key, and anywhere once Vignette is trusted for
/// Accessibility, which is also when a double tap starts to work. It reads a key as `ModifierTap`
/// does: the key's code, and whether its modifier is still set.
@MainActor
final class HeldModifiers: ObservableObject {
    @Published private(set) var codes: Set<UInt16> = []
    var flags: NSEvent.ModifierFlags { codes.reduce(into: []) { $0.insert(ModifierTap.flag(forKeyCode: $1)) } }
    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }
        let changed: (NSEvent) -> Void = { [weak self] event in MainActor.assumeIsolated { self?.changed(event) } }
        monitors = [NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { changed($0); return $0 },
                    NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: changed)].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        codes = []
    }

    private func changed(_ event: NSEvent) {
        guard HotKeySpec.modifierCodes.values.contains(event.keyCode) else { return }
        if event.modifierFlags.contains(ModifierTap.flag(forKeyCode: event.keyCode)) {
            codes.insert(event.keyCode)
        } else {
            codes.remove(event.keyCode)
        }
    }
}
