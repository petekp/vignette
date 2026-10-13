import AppKit
import SwiftUI

/// A debug window for tuning the success check on copied and sent cards: the coin, its light, its
/// spin and its bloom (docs/check-lab-2026-10-11.md). It shows the check large, and the Copied notice
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
        model.spin = .once
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "check lab closed") }
    }
}

@MainActor
final class CheckLabModel: ObservableObject {
    /// `once`: every check spins once from when it appears, as on a card. `loop`: the spin runs over
    /// and over at `speed`. `hold`: it stays at `place`.
    enum Spin: Hashable { case once, loop, hold }

    /// Each change replays, so going back to Once spins again.
    @Published var spin = Spin.once {
        didSet { if spin != oldValue { replay() } }
    }
    /// The loop's speed, as a fraction of the spin's own.
    @Published var speed = 0.25
    @Published var place = 0.3
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

    /// Where the previews' spin is at `now`, 0 to 1, or nil when each runs its own.
    func place(at now: Date) -> Double? {
        switch spin {
        case .once: return nil
        case .hold: return place
        case .loop:
            let length = max(CheckSpin(Settings.shared.data.ui).length, 0.05) / max(speed, 0.01)
            let rest = 0.6
            let phase = now.timeIntervalSince(loopStart).truncatingRemainder(dividingBy: length + rest)
            return min(1, phase / length)
        }
    }
}

private struct CheckLabView: View {
    @ObservedObject var model: CheckLabModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.animation(paused: model.spin != .loop)) { context in
                previews.environment(\.checkSpinPlace, model.place(at: context.date))
            }
            .id(model.take)
            .padding(10)
            controls
            Form {
                if let section = TweakCatalog.section("Check") {
                    TweakGroups(section: section, ui: settings.data.ui)
                    Section {
                        Button("Reset the check to its defaults") {
                            settings.update { data in section.tweaks.forEach { $0.reset(&data.ui) } }
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
                Picker("Spin", selection: $model.spin) {
                    Text("Once").tag(CheckLabModel.Spin.once)
                    Text("Loop").tag(CheckLabModel.Spin.loop)
                    Text("Hold").tag(CheckLabModel.Spin.hold)
                }
                .pickerStyle(.segmented).frame(width: 220)
                Spacer()
                Button("Replay", action: model.replay).keyboardShortcut(.defaultAction)
            }
            switch model.spin {
            case .once:
                row("", Text(settings.motionScale > 0 ? "Replay shows the notices as a card does." : "Motion is off, so cards do not spin. Hold still turns it here.")
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
                CheckCoin(diameter: 120)
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
