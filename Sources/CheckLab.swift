import AppKit
import SwiftUI

/// A debug window for tuning the success check on copied and sent cards: its metal, its glare and
/// the glare's bloom (docs/check-lab-2026-10-11.md). It shows the check large, and the Copied notice
/// and a send's notice at their real size on a card. The sliders are the `check` settings every card
/// draws with, so a value chosen here is the one cards show. Opened from the tweak panel or
/// `vignette://check-lab` (needs `debug`).
@MainActor
final class CheckLabController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let model = CheckLabModel()

    func show() {
        let p = panel ?? make()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.replay()
    }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 820),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Check Lab"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: CheckLabView(model: model))
        if let v = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: v.midX - 280, y: v.midY - 410))
        }
        panel = p
        return p
    }

    func windowWillClose(_ notification: Notification) {
        model.glare = .once
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "check lab closed") }
    }
}

@MainActor
final class CheckLabModel: ObservableObject {
    /// `once`: every check runs its glare once from when it appears, as on a card. `loop`: the glare
    /// crosses over and over at `speed`. `hold`: it stays at `place`.
    enum Glare: Hashable { case once, loop, hold }

    @Published var glare = Glare.once
    /// The loop's speed, as a fraction of the glare's own.
    @Published var speed = 0.25
    @Published var place = 0.5
    /// Changed by Replay, so the previews appear again.
    @Published private(set) var take = 0
    @Published private(set) var sendState = SendNotice.State.sending
    private var loopStart = Date()

    /// Shows every preview again from its start, and the send going from Sending to Sent as a
    /// delivery that answers at once does.
    func replay() {
        take += 1
        loopStart = Date()
        sendState = .sending
        let replayed = take
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.take == replayed else { return }
            self.sendState = .sent
        }
    }

    /// Where the previews' glare is at `now`, or nil when each runs its own.
    func place(at now: Date) -> Double? {
        switch glare {
        case .once: return nil
        case .hold: return place
        case .loop:
            let crossing = max(Settings.shared.data.ui.checkGlareDuration, 0.05) / max(speed, 0.01)
            let rest = 0.4
            let phase = now.timeIntervalSince(loopStart).truncatingRemainder(dividingBy: crossing + rest)
            return min(1, phase / crossing)
        }
    }
}

private struct CheckLabView: View {
    @ObservedObject var model: CheckLabModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.animation(paused: model.glare != .loop)) { context in
                previews.environment(\.checkGlarePlace, model.place(at: context.date))
            }
            .id(model.take)
            .padding(10)
            controls
            Form {
                Section {
                    ColorTweak("Colour", \.checkColor)
                    Tweak("Shine", \.checkShine, 0...1, step: 0.01)
                    Tweak("Depth", \.checkDepth, 0...1, step: 0.01)
                    Tweak("Light angle", \.checkLightAngle, -180...180, unit: "°")
                    Tweak("Rim", \.checkRim, 0...1, step: 0.01)
                    Tweak("Rim width", \.checkRimWidth, 0...0.2, step: 0.005)
                    Tweak("Highlight", \.checkHighlight, 0...1, step: 0.01)
                    Tweak("Highlight size", \.checkHighlightSize, 0...1.2, step: 0.01)
                } header: {
                    Text("Metal")
                } footer: {
                    Text("The disc's gradient runs from the colour taken toward white by Shine, on the side the light comes from, to the colour taken toward black by Depth. The rim is light on that side and shade on the other. Light angle is in degrees clockwise from the top, and turns the gradient, the rim and the highlight together. Widths and sizes are fractions of the disc.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Check mark") {
                    Tweak("Size", \.checkGlyphSize, 0.2...0.8, step: 0.01)
                    Tweak("Shadow", \.checkGlyphShadow, 0...1, step: 0.01)
                }
                Section {
                    Tweak("Brightness", \.checkGlare, 0...1, step: 0.01)
                    Tweak("Width", \.checkGlareWidth, 0.05...1, step: 0.01)
                    Tweak("Tilt", \.checkGlareAngle, -60...60, unit: "°")
                    Tweak("Duration", \.checkGlareDuration, 0.1...2, step: 0.01, unit: "s")
                    Tweak("Delay", \.checkGlareDelay, 0...1, step: 0.01, unit: "s")
                } header: {
                    Text("Glare")
                } footer: {
                    Text("A band of light that crosses the disc once, Delay after the check appears. Brightness 0 turns it off. Tilt is from upright.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Tweak("Strength", \.checkBloom, 0...2, step: 0.01)
                    Tweak("Radius", \.checkBloomRadius, 0...0.8, step: 0.01)
                    Tweak("Threshold", \.checkBloomThreshold, 0...0.95, step: 0.01)
                } header: {
                    Text("Bloom")
                } footer: {
                    Text("The part of the glare brighter than Threshold, spread over Radius, a fraction of the disc, and added back, so the band glows past its edges and past the disc's. Strength 0 turns it off. It shows on the dark veil, not on the white ring of a send's badge.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Reset the check to its defaults") {
                        settings.update { settings in
                            let defaults = UITweaks()
                            settings.ui.checkColor = defaults.checkColor
                            for bound in UITweaks.bounds where bound.name.hasPrefix("check") {
                                settings.ui[keyPath: bound.path] = defaults[keyPath: bound.path]
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 540, minHeight: 760)
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack {
                Picker("Glare", selection: $model.glare) {
                    Text("Once").tag(CheckLabModel.Glare.once)
                    Text("Loop").tag(CheckLabModel.Glare.loop)
                    Text("Hold").tag(CheckLabModel.Glare.hold)
                }
                .pickerStyle(.segmented).frame(width: 220)
                Spacer()
                Button("Replay", action: model.replay).keyboardShortcut(.defaultAction)
            }
            switch model.glare {
            case .once:
                row("", Text(settings.motionScale > 0 ? "Replay shows the notices as a card does." : "Motion is off, so there is no glare.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading))
            case .loop:
                row("Speed", Slider(value: $model.speed, in: 0.05...1), value: String(format: "%.2f×", model.speed))
            case .hold:
                row("Place", Slider(value: $model.place, in: 0...1), value: String(format: "%.2f", model.place))
            }
        }
        .padding(.horizontal, 10)
    }

    private func row(_ label: String, _ content: some View, value: String = "") -> some View {
        HStack {
            Text(label).frame(width: 60, alignment: .leading)
            content
            Text(value).monospacedDigit().font(.caption).frame(width: 44, alignment: .trailing)
        }
    }

    /// The check large on the notices' veil, and the two notices at their real size on a card.
    private var previews: some View {
        let ui = settings.data.ui
        let card = CGSize(width: ui.cardMaxWidth, height: ui.cardMaxWidth * 0.62)
        return HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.12))
                MetalCheck(diameter: 120)
            }
            .frame(width: 190, height: 190)
            VStack(spacing: 14) {
                sampleCard(card) { CopiedOverlay(corner: ui.cardCornerRadius, label: "Copied") }
                sampleCard(card) {
                    SendOverlay(notice: SendNotice(request: "check-lab", client: .claude, project: "vignette", state: model.sendState),
                                corner: ui.cardCornerRadius, onUnsend: {}, onOverControl: { _ in })
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A card with a stand-in for a screenshot under `overlay`.
    private func sampleCard<Overlay: View>(_ size: CGSize, @ViewBuilder overlay: () -> Overlay) -> some View {
        RoundedRectangle(cornerRadius: settings.data.ui.cardCornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.86, green: 0.9, blue: 0.97), Color(red: 0.35, green: 0.47, blue: 0.7)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(overlay())
            .frame(width: size.width, height: size.height)
    }
}
