import AppKit
import SwiftUI

/// A debug window for trying and tuning live ink's pointer field, the ring and the wake
/// (docs/live-ink-cursor-2026-10-10.md). The sliders are the `ui` settings live ink draws with, so a
/// value chosen here is the one inking shows. Hold on Screen keeps the field up at the inking level
/// while every press passes through. Opened from the tweak panel or `vignette://pointer-lab` (needs
/// `debug`).
@MainActor
final class PointerLabController: NSObject, NSWindowDelegate {
    private let preview: (Bool) -> Void
    private var panel: NSPanel?
    private let model = PointerLabModel()

    init(preview: @escaping (Bool) -> Void) {
        self.preview = preview
    }

    /// Holds the field on screen, or lets it go. The URL's `preview=` comes here too, so the switch
    /// always says what the screen shows.
    func hold(_ on: Bool) {
        model.holding = on
        preview(on)
    }

    func show() {
        let p = panel ?? make()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.canCapture = CGPreflightScreenCaptureAccess()
    }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 760),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Pointer Lab"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: PointerLabView(model: model, hold: { [weak self] on in self?.hold(on) }))
        if let v = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: v.midX - 280, y: v.midY - 380))
        }
        panel = p
        return p
    }

    func windowWillClose(_ notification: Notification) {
        if model.holding { preview(false) }
        model.holding = false
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "pointer lab closed") }
    }
}

@MainActor
final class PointerLabModel: ObservableObject {
    @Published var holding = false
    @Published var canCapture = true
}

private struct PointerLabView: View {
    @ObservedObject var model: PointerLabModel
    let hold: (Bool) -> Void
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Hold on screen", isOn: Binding(get: { model.holding }, set: { hold($0) }))
                if !model.canCapture {
                    Text("Bending the screen needs Screen Recording. Without it, the ring glows and nothing bends.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                StylePicker(path: \.liveInkFieldStyle, names: ["Glass", "Lens", "Squircle", "Droplet", "Lamp", "Caustic"])
                let ring = Int(settings.data.ui.liveInkFieldStyle.rounded())
                Tweak("Size", \.liveInkFieldSize, 0...120, unit: "pt")
                if ring != 4 {
                    Tweak("Bend", \.liveInkFieldBend, 0...1.8, step: 0.05)
                    Tweak("Colour split", \.liveInkFieldSplit, 0...2, step: 0.05)
                }
                if ring == 5 {
                    Tweak("Depth", \.liveInkFieldDepth, 0.04...0.3, step: 0.01)
                }
                if ring == 1 {
                    Tweak("Zoom", \.liveInkFieldZoom, 1...1.6, step: 0.02)
                }
                if ring == 1 || ring == 4 {
                    Tweak("Clear middle", \.liveInkFieldClear, 0...1, step: 0.05)
                }
                if ring == 1 || ring == 5 {
                    Tweak("Shine", \.liveInkFieldShine, 0...1, step: 0.05)
                    Tweak("Shade", \.liveInkFieldShade, 0...1, step: 0.05)
                }
                if ring == 2 {
                    Tweak("Squareness", \.liveInkFieldSquareness, 2...8, step: 0.1)
                    Tweak("Break", \.liveInkFieldBreak, 0...1, step: 0.05)
                }
                if ring == 4 {
                    Tweak("Spread", \.liveInkFieldSpread, 0.8...3, step: 0.05)
                }
                Tweak("Glow", \.liveInkFieldGlow, 0...1, step: 0.05)
                Tweak("Follow", \.liveInkFieldFollow, 0...0.5, step: 0.01, unit: "s")
                Tweak("Stretch", \.liveInkFieldStretch, 0...1, step: 0.05)
            } header: {
                Text("Ring")
            } footer: {
                Text(Self.ringNotes[min(max(Int(settings.data.ui.liveInkFieldStyle.rounded()), 0), 5)]
                     + " It shows while Control and Option are held, tightens while the button is down, and Size 0 turns it off. Follow 0 holds it on the pointer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Tweak("Delay", \.liveInkFieldDelay, 0...1, step: 0.05, unit: "s")
                Tweak("Fade", \.liveInkFieldFade, 0...1, step: 0.05, unit: "s")
                Tweak("Opacity", \.liveInkFieldOpacity, 0...1, step: 0.05)
            } header: {
                Text("Showing")
            } footer: {
                Text("The field waits for the delay, or for a press, so the chord on its way to a shortcut does not flash it. It fades in and out, and the ring grows in, over the fade.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                StylePicker(path: \.liveInkWakeStyle, names: ["Ribbon", "Silk", "Mist", "Frost", "Ripples"])
                let wake = Int(settings.data.ui.liveInkWakeStyle.rounded())
                Tweak("Strength", \.liveInkWakeStrength, 0...1, step: 0.05)
                Tweak("Size", \.liveInkWakeSize, 10...600, unit: "pt")
                Tweak("Duration", \.liveInkWakeDuration, 0.1...3, step: 0.05, unit: "s")
                if wake != 4 {
                    Tweak("Lift", \.liveInkWakeLift, 0...20, step: 0.5, unit: "pt")
                    Tweak("Widen", \.liveInkWakeWiden, 0...0.8, step: 0.05)
                    Tweak("Rise", \.liveInkWakeRise, 0.02...0.5, step: 0.01)
                    Tweak("Fade starts", \.liveInkWakeHold, 0...0.7, step: 0.05)
                }
                if wake == 0 || wake == 2 || wake == 3 {
                    Tweak("Swell", \.liveInkWakeSwell, -1...1, step: 0.05)
                }
                if wake == 0 {
                    Tweak("Colour split", \.liveInkWakeSplit, 0...1, step: 0.05)
                }
                if wake == 3 {
                    Tweak("Blur", \.liveInkWakeBlur, 0...6, step: 0.1, unit: "pt")
                }
                if wake == 0 || wake == 2 || wake == 3 {
                    Tweak("Light", \.liveInkWakeLight, 0...1, step: 0.05)
                }
                if wake == 2 {
                    Tweak("Clumps", \.liveInkWakeMist, 0...1, step: 0.05)
                }
            } header: {
                Text("Wake")
            } footer: {
                Text(Self.wakeNotes[min(max(Int(settings.data.ui.liveInkWakeStyle.rounded()), 0), 4)]
                     + " Strength 0 turns it off. While the field is held, any drag makes a wake.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 520)
    }

    private static let ringNotes = [
        "Glass: a soft ridge of glass round the pointer that bends the screen and glows in the ink colour. What the pointer is on stays still.",
        "Lens: a clear bead. Its rim draws the screen in, Zoom magnifies its middle about the arrow's tip, and a rim light, a highlight and a soft shadow let it read on any page.",
        "Squircle: the glass ridge on a rounded square, the shape of an app icon. Break leaves only its corners.",
        "Droplet: the glass ring at rest. Moving, it pulls into a teardrop, a round head leading and a soft tail behind, as long as Stretch lets it.",
        "Lamp: no edge, only a soft pool of ink-coloured light round the arrow. It never reads the screen.",
        "Caustic: light through a glass on a table. A bright crescent gathers to a point on the side away from the light, fringed by Colour split.",
    ]

    private static let wakeNotes = [
        "Ribbon: a beat behind the pen, the screen near the stroke spreads outward in one smooth swell, wider and flatter as it fades. Below 0, Swell pulls it in.",
        "Silk: the screen leans the way the pen went, as if dragged, and settles back.",
        "Mist: a plume of ink-coloured light in slow clumps that drifts up a little as it fades, over a very slight swell.",
        "Frost: the band behind the pen goes soft, as if breathed on, and clears from its edges.",
        "Ripples: rings of waves spread from the pen, as before.",
    ]
}

/// Picks a style, which the file keeps as a number.
private struct StylePicker: View {
    let path: WritableKeyPath<UITweaks, Double>
    let names: [String]
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Picker("Style", selection: Binding(get: { Int(settings.data.ui[keyPath: path].rounded()) },
                                           set: { v in settings.update { $0.ui[keyPath: path] = Double(v) } })) {
            ForEach(names.indices, id: \.self) { Text(names[$0]).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}
