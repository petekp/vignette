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
            if let section = TweakCatalog.section("Pointer") { TweakGroups(section: section, ui: settings.data.ui) }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 520)
    }
}
