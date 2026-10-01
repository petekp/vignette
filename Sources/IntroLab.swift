import AppKit
import SwiftUI

/// A debug window for tuning how setup's window goes into the menu bar icon
/// (docs/intro-funnel-2026-09-30.md). Its preview draws the funnel over a picture of the screen at
/// any moment of the flight, and Play on Screen runs the real intro from a stand-in for setup's
/// window. The sliders are the `ui` settings the intro reads, so a value chosen here is the one it
/// plays with. Opened from the tweak panel or `vignette://intro-lab` (needs `debug`).
@MainActor
final class IntroLabController: NSObject, NSWindowDelegate {
    /// Plays the intro from `window` into the menu bar icon and closes the window. False when the
    /// icon cannot be seen, and the window is left open.
    private let play: (NSWindow) -> Bool
    /// The menu bar icon's frame on screen, or nil when it cannot be seen.
    private let iconFrame: () -> NSRect?
    private var panel: NSPanel?
    private let model = IntroLabModel()

    init(play: @escaping (NSWindow) -> Bool, iconFrame: @escaping () -> NSRect?) {
        self.play = play
        self.iconFrame = iconFrame
    }

    func show() {
        let p = panel ?? make()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if model.scene == nil { capture() }
    }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 760),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Intro Lab"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: IntroLabView(model: model,
                                                             playOnScreen: { [weak self] in self?.playOnScreen() },
                                                             recapture: { [weak self] in self?.capture() }))
        if let v = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: v.minX + 40, y: v.midY - 380))
        }
        panel = p
        return p
    }

    /// Setup's shortcut page in a window like setup's. It has no callbacks, so its Done and its
    /// closing apply nothing: no settings, no plugins, no login item.
    private func standIn() -> NSWindow {
        let setup = SetupModel(protectedArea: nil, agents: [], callbacks: .init())
        setup.page = .shortcut
        let win = NSWindow(contentViewController: NSHostingController(rootView: SetupView(model: setup)))
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.title = "Intro Lab stand-in"
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: SetupView.width, height: SetupView.height))
        win.center()
        setup.done = { [weak self, weak win] in
            guard let self, let win, !self.play(win) else { return }
            win.close()
        }
        return win
    }

    /// Shows the stand-in for a moment and takes the picture the intro would fly, for the preview.
    private func capture() {
        guard let screen = NSScreen.main else { return }
        let win = standIn()
        // Key, as setup's window is when Done is pressed: an inactive window's controls are grey.
        win.makeKeyAndOrderFront(nil)
        model.status = "Capturing setup's window…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MenuBarIntro.funnelPicture(of: win) { picture in
                win.close()
                guard let self else { return }
                self.panel?.makeKeyAndOrderFront(nil)
                guard let picture else { self.model.status = "Could not capture the window."; return }
                let icon = self.iconFrame() ?? NSRect(x: screen.frame.maxX - 200, y: screen.frame.maxY - 24, width: 30, height: 24)
                self.model.scene = IntroLabModel.Scene(picture: picture.image, margin: picture.margin, window: win.frame,
                                                       icon: icon, screen: screen.frame,
                                                       menuBar: screen.frame.maxY - screen.visibleFrame.maxY)
                self.model.status = self.iconFrame() == nil ? "The menu bar icon is hidden; the preview guesses its place." : ""
            }
        }
    }

    /// The real intro, from a stand-in shown long enough to see what flies.
    private func playOnScreen() {
        let win = standIn()
        win.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, win.isVisible else { return }
            if !self.play(win) {
                self.model.status = "The menu bar icon cannot be seen, so there is nothing to fly into."
                win.close()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.looping = false
        DispatchQueue.main.async { FocusReturn.shared.restore(reason: "intro lab closed") }
    }
}

@MainActor
final class IntroLabModel: ObservableObject {
    /// What the preview draws: the picture, and where the window, the icon and the screen are, in
    /// screen points with y up.
    struct Scene {
        let picture: CGImage
        let margin: CGFloat
        let window: NSRect, icon: NSRect, screen: NSRect
        let menuBar: CGFloat
    }

    @Published var scene: Scene?
    @Published var status = ""
    /// The moment the preview holds, 0 to 1, while it is not looping.
    @Published var scrub = 0.35
    @Published var looping = false
    /// The loop's speed, as a fraction of the intro's own.
    @Published var speed = 0.25
    private var loopStart = CACurrentMediaTime()

    func restartLoop() { loopStart = CACurrentMediaTime() }

    /// The preview's moment: the scrubber's, or the loop's, which holds at each end for a moment.
    func progress() -> Double {
        guard looping else { return scrub }
        let flight = max(Settings.shared.data.ui.introDuration, 0.05) / max(speed, 0.01)
        let hold = 0.5
        let phase = (CACurrentMediaTime() - loopStart).truncatingRemainder(dividingBy: flight + 2 * hold)
        return min(1, max(0, (phase - hold) / flight))
    }
}

@MainActor
private struct IntroLabView: View {
    @ObservedObject var model: IntroLabModel
    let playOnScreen: () -> Void
    let recapture: () -> Void
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(spacing: 0) {
            preview
                .padding(10)
            HStack {
                Toggle("Loop", isOn: Binding(get: { model.looping }, set: { model.looping = $0; model.restartLoop() }))
                Text("Speed").foregroundStyle(.secondary)
                Slider(value: $model.speed, in: 0.05...1).frame(width: 110)
                Text(String(format: "%.2f×", model.speed)).monospacedDigit().font(.caption).frame(width: 40)
                Spacer()
                Button("Recapture", action: recapture)
                Button("Play on Screen", action: playOnScreen).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 10)
            HStack {
                Text("Moment").frame(width: 140, alignment: .leading)
                Slider(value: $model.scrub, in: 0...1).disabled(model.looping)
                Text(String(format: "%.2f", model.scrub)).monospacedDigit().font(.caption).frame(width: 52, alignment: .trailing)
            }
            .padding(.horizontal, 10).padding(.top, 6)
            if !model.status.isEmpty {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
            }
            Form {
                Section("Flight") {
                    Tweak("Duration", \.introDuration, 0.1...3, step: 0.05, unit: "s")
                    Tweak("Funnel strength", \.introFunnel, 0...1, step: 0.05)
                    Text("At 0 the intro flies the window as one piece, as it shipped; the preview then shows its rows moving together instead.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Pour") {
                    Tweak("Smoothing", \.introFunnelSmoothing, 0...1, step: 0.05)
                    Tweak("Corner", \.introFunnelCorner, 0...80, unit: "pt")
                    Tweak("Smear", \.introFunnelSmear, 0...1, step: 0.05)
                    Tweak("Rim light", \.introFunnelRim, 0...1, step: 0.05)
                    Tweak("Fade into icon", \.introFunnelFade, 0.05...1, step: 0.05)
                    Text("Smoothing eases each row's start and stop, which curves the sides. Corner is the radius the pour's corners grow to. Smear averages squeezed rows so text softens instead of breaking up. Rim light brightens the bent edges. Fade into icon is how much of each row's travel it fades over as it reaches the icon.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 560, minHeight: 700)
    }

    /// The screen at the preview's width: the menu bar, the icon's place, and the funnel.
    @ViewBuilder private var preview: some View {
        GeometryReader { space in
            if let scene = model.scene {
                let zoom = space.size.width / scene.screen.width
                let place = { (rect: NSRect) in
                    CGRect(x: (rect.minX - scene.screen.minX) * zoom, y: (scene.screen.maxY - rect.maxY) * zoom,
                           width: rect.width * zoom, height: rect.height * zoom)
                }
                let card = place(scene.window.insetBy(dx: -scene.margin, dy: -scene.margin))
                let icon = place(scene.icon)
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
                    Rectangle().fill(Color(white: 0.22)).frame(height: scene.menuBar * zoom)
                    RoundedRectangle(cornerRadius: 3 * zoom).stroke(Color.white.opacity(0.35), lineWidth: 1)
                        .frame(width: icon.width, height: icon.height).offset(x: icon.minX, y: icon.minY)
                    FunnelFlight(image: scene.picture, card: card, icon: icon,
                                 cardRadius: (MenuBarIntro.windowCornerRadius + scene.margin) * zoom, zoom: zoom,
                                 progress: { model.progress() })
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.12))
            }
        }
        .aspectRatio(model.scene.map { $0.screen.width / $0.screen.height } ?? 16 / 10, contentMode: .fit)
    }
}
