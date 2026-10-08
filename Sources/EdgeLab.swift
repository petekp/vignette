import AppKit
import SwiftUI

/// A debug window for trying and tuning live ink's look along the screen's edges
/// (docs/live-ink-edge-lab-2026-10-08.md). The sliders are the `ui` settings live ink draws with, so
/// a value chosen here is the one inking shows. Hold on Screen keeps the look up at the inking level
/// while every press passes through. Opened from the tweak panel or `vignette://edge-lab` (needs
/// `debug`).
@MainActor
final class EdgeLabController: NSObject, NSWindowDelegate {
    private let preview: (Bool) -> Void
    private var panel: NSPanel?
    private let model = EdgeLabModel()

    init(preview: @escaping (Bool) -> Void) {
        self.preview = preview
    }

    /// Holds the look on screen, or lets it go. The URL's `preview=` comes here too, so the switch
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
        p.title = "Edge Lab"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: EdgeLabView(model: model, hold: { [weak self] on in self?.hold(on) }))
        if let v = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: v.midX - 280, y: v.midY - 380))
        }
        panel = p
        return p
    }

    func windowWillClose(_ notification: Notification) {
        if model.holding { preview(false) }
        model.holding = false
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "edge lab closed") }
    }
}

@MainActor
final class EdgeLabModel: ObservableObject {
    @Published var holding = false
    @Published var canCapture = true
}

private struct EdgeLabView: View {
    @ObservedObject var model: EdgeLabModel
    let hold: (Bool) -> Void
    @ObservedObject private var settings = Settings.shared

    private var style: EdgeLensLayer.Style {
        EdgeLensLayer.Style(rawValue: Int(settings.data.ui.liveInkEdgeStyle.rounded())) ?? .glow
    }

    private var palette: EdgeLensLayer.Palette {
        EdgeLensLayer.Palette(rawValue: Int(settings.data.ui.liveInkEdgeColors.rounded())) ?? .ink
    }

    private var blend: EdgeLensLayer.Blend {
        EdgeLensLayer.Blend(rawValue: Int(settings.data.ui.liveInkEdgeBlend.rounded())) ?? .normal
    }

    var body: some View {
        Form {
            Section {
                Picker("Look", selection: Binding(get: { style }, set: { pick($0) })) {
                    ForEach(EdgeLensLayer.Style.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(style.summary).font(.caption).foregroundStyle(.secondary)
                Toggle("Hold on screen", isOn: Binding(get: { model.holding }, set: { hold($0) }))
                if style.drawsFromScreen && !model.canCapture {
                    Text("This look draws from a live picture of the screen, so it needs Screen Recording. Without it, live ink shows the glow.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Tuning") {
                if style == .glow {
                    Tweak("Width", \.liveInkGlowWidth, 0...80, unit: "pt")
                } else {
                    Tweak("Width", \.liveInkEdgeWidth, 4...160, unit: "pt")
                }
                ForEach(style.sliders, id: \.label) { slider in
                    Tweak(slider.label, slider.path, slider.range, step: slider.step, unit: slider.unit)
                }
                if style != .glow {
                    Tweak("Screen corners", \.liveInkEdgeCorner, 0...30, unit: "pt")
                }
                Tweak("Opacity", \.liveInkGlowOpacity, 0...1, step: 0.05)
                Tweak("Fade", \.liveInkGlowFade, 0...1, step: 0.05, unit: "s")
                Button("Reset this look") { pick(style) }
            }
            if style.hasAuroraLight {
                Section("Colour") {
                    Picker("Colours", selection: Binding(get: { palette }, set: { picked in
                        settings.update { $0.ui.liveInkEdgeColors = Double(picked.rawValue) }
                    })) {
                        ForEach(EdgeLensLayer.Palette.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch palette {
                    case .ink: Tweak("Hue swing", \.liveInkEdgeVariation, 0...1, step: 0.01)
                    case .rainbow: EmptyView()
                    case .twoColours:
                        ColorTweak("First colour", \.liveInkEdgeColor1)
                        ColorTweak("Second colour", \.liveInkEdgeColor2)
                    }
                    Tweak("Repeats", \.liveInkEdgeRepeats, 1...8)
                    Tweak("Hue shift", \.liveInkEdgeHue, 0...1, step: 0.01)
                    Tweak("Saturation", \.liveInkEdgeSaturation, 0...2, step: 0.01)
                    Tweak("Brightness", \.liveInkEdgeBrightness, 0...3, step: 0.01)
                    Tweak("Drift", \.liveInkEdgeDrift, 0...0.5, step: 0.01)
                    if style == .auroraRipple {
                        Picker("Blend", selection: Binding(get: { blend }, set: { picked in
                            settings.update { $0.ui.liveInkEdgeBlend = Double(picked.rawValue) }
                        })) {
                            ForEach(EdgeLensLayer.Blend.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                    }
                }
            }
            Section {
                Tweak("Strength", \.liveInkWakeStrength, 0...1, step: 0.05)
                Tweak("Size", \.liveInkWakeSize, 10...300, unit: "pt")
                Tweak("Duration", \.liveInkWakeDuration, 0.1...3, step: 0.05, unit: "s")
            } header: {
                Text("Wake")
            } footer: {
                Text("Rings spread behind the pen as you draw and bend the screen under them, with any look. Strength 0 turns it off. While the look is held, any drag makes rings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 520)
    }

    /// Shows `look` from its starting values.
    private func pick(_ look: EdgeLensLayer.Style) {
        settings.update { data in
            data.ui.liveInkEdgeStyle = Double(look.rawValue)
            for (path, value) in look.startingValues { data.ui[keyPath: path] = value }
        }
    }
}
