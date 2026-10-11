import AppKit
import SwiftUI

/// A debug window for trying and tuning live ink's pointer field and wake
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
                Tweak("Size", \.liveInkFieldSize, 0...120, unit: "pt")
                Tweak("Bend", \.liveInkFieldBend, 0...2, step: 0.05)
                Tweak("Colour split", \.liveInkFieldSplit, 0...1, step: 0.05)
                Tweak("Glow", \.liveInkFieldGlow, 0...1, step: 0.05)
                Tweak("Follow", \.liveInkFieldFollow, 0...0.5, step: 0.01, unit: "s")
                Tweak("Stretch", \.liveInkFieldStretch, 0...1, step: 0.05)
            } header: {
                Text("Pointer field")
            } footer: {
                Text("A ring round the pointer while Control and Option are held. It bends the screen and glows in the ink colour, and what the pointer is on stays still. Size 0 turns it off, and Follow 0 holds it on the pointer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Tweak("Delay", \.liveInkFieldDelay, 0...1, step: 0.05, unit: "s")
                Tweak("Fade", \.liveInkFieldFade, 0...1, step: 0.05, unit: "s")
                Tweak("Opacity", \.liveInkFieldOpacity, 0...1, step: 0.05)
            } header: {
                Text("Showing")
            } footer: {
                Text("The field waits for the delay, or for a press, so the chord on its way to a shortcut does not flash it. It fades in and out, and grows in, over the fade.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Tweak("Strength", \.liveInkWakeStrength, 0...1, step: 0.05)
                Tweak("Size", \.liveInkWakeSize, 10...300, unit: "pt")
                Tweak("Duration", \.liveInkWakeDuration, 0.1...3, step: 0.05, unit: "s")
            } header: {
                Text("Wake")
            } footer: {
                Text("Rings spread behind the pen as you draw and bend the screen under them. Strength 0 turns it off. While the field is held, any drag makes rings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 520)
    }
}
