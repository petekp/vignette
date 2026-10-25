import AppKit
import Combine
import SwiftUI

/// The concepts for setup's live ink page that Pete is choosing between. Each is tried on the page
/// with the real chord and the real ink, and answered by Vignette itself: nothing is asked of an
/// agent, and nothing leaves the Mac. The page shows only with `debug`.
enum SetupInkConcept: String, CaseIterable, Identifiable {
    /// A small illustrated scene with one thing wrong in it, to circle.
    case findTheBug = "find-the-bug"
    /// The window steps aside, and Vignette names whatever is circled on the screen.
    case desktop
    /// The page speaks in ink, and the person answers by drawing.
    case writesBack = "writes-back"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .findTheBug: "Find the bug"
        case .desktop: "Your desktop"
        case .writesBack: "Writes back"
        }
    }

    private static let key = "setupInkConcept"

    /// The concept a debug setup shows, the one opened last with `vignette://setup-ink`.
    static var chosen: SetupInkConcept {
        get { UserDefaults.standard.string(forKey: key).flatMap(SetupInkConcept.init) ?? .findTheBug }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// Placeholder copy for the live ink page, until Pete picks the words.
enum SetupInkCopy {
    static let costNote = "When you ask, Claude sees a picture of the window, its title and its URL, through your own Claude Code. An ask costs about one to four cents."
}

/// The live ink page's try: the chord, what was drawn, and how Vignette answered. It outlives the
/// page's view, which goes while the window is aside.
@MainActor
final class SetupInkTry: ObservableObject {
    enum Phase: Equatable {
        case waiting
        case inking
        /// Circled something that is not the odd one out.
        case missed
        case found
        /// Named what was circled on the screen.
        case saw(String)
    }

    @Published private(set) var phase = Phase.waiting
    @Published private(set) var chordDown = false
    @Published private(set) var steppedAside = false
    /// Answers that were right, each of which spins the coin again.
    @Published private(set) var successes = 0

    /// The scene's odd one out, and the scene, in global top-left points.
    var oddOneOut: () -> CGRect? = { nil }
    var scene: () -> CGRect? = { nil }

    private weak var liveInk: LiveInk?
    /// Asked each time: the page appears before the window it is in has been handed over.
    private var findWindow: () -> NSWindow? = { nil }
    private var window: NSWindow? { findWindow() }
    private var concept = SetupInkConcept.findTheBug
    private var shown = Set<Mark.ID>()
    private var home: NSRect?
    private var later: DispatchWorkItem?

    func begin(_ concept: SetupInkConcept, liveInk: LiveInk?, window: @escaping () -> NSWindow?) {
        end()
        self.concept = concept
        self.liveInk = liveInk
        findWindow = window
        phase = .waiting
        liveInk?.practise(LiveInk.Practice(
            area: { [weak self] in self?.windowFrame ?? .null },
            chord: { [weak self] down in self?.chord(down) },
            released: { [weak self] ink in self?.released(ink) }))
        Log.write("[setup] live ink try concept=\(concept.rawValue)")
        // Where the try is on the screen, for a script that draws there, once the page has slid in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.concept == concept, let frame = self.windowFrame else { return }
            let target = self.oddOneOut().map { " target=\(Self.numbers($0))" } ?? ""
            Log.write("[setup] live ink try window=\(Self.numbers(frame))\(target)")
        }
    }

    private static func numbers(_ rect: CGRect) -> String {
        [rect.minX, rect.minY, rect.width, rect.height].map { String(Int($0.rounded())) }.joined(separator: ",")
    }

    func end() {
        later?.cancel()
        later = nil
        liveInk?.practise(nil)
        liveInk = nil
        shown = []
        chordDown = false
        comeBack()
    }

    /// The window, in global top-left points.
    private var windowFrame: CGRect? {
        window.map { CGRect(x: $0.frame.minX, y: StateReport.primaryHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
    }

    private func chord(_ down: Bool) {
        chordDown = down
        guard down else { return }
        later?.cancel()
        // A new try: the last one's ink and answer leave.
        liveInk?.letGoOfPractice(shown, .dismissed)
        shown = []
        phase = .inking
        if concept == .desktop { stepAside() }
    }

    private func released(_ ink: [Mark]) {
        shown.formUnion(ink.map(\.id))
        guard !ink.isEmpty else {
            phase = .waiting
            comeBack()
            return
        }
        switch concept {
        case .findTheBug: judge(ink)
        case .desktop: name(ink)
        case .writesBack: phase = .waiting
        }
    }

    // MARK: Find the bug

    private func judge(_ ink: [Mark]) {
        // The answer is drawn on the picture, clear of the page's words.
        guard let liveInk, let room = scene()?.insetBy(dx: -4, dy: -4) ?? windowFrame else { return }
        if let target = oddOneOut(), ink.contains(where: { Self.points(at: target, $0) }) {
            let answer = LiveAnswer(say: "A fish, flying with the birds.", marks: [AnswerMark(kind: .circle, label: "Fish don't fly")])
            shown.formUnion(liveInk.showPracticeAnswer(answer, targets: [target], about: ink, room: room, overDark: false))
            phase = .found
            // The coin comes once the answer has drawn itself on.
            after(0.55 * Settings.shared.motionScale) { [weak self] in self?.successes += 1 }
        } else if let circled = ink.compactMap(\.shapeExtent).last {
            let answer = LiveAnswer(say: "That one belongs.", marks: [AnswerMark(kind: .circle, label: "Nothing wrong here")])
            shown.formUnion(liveInk.showPracticeAnswer(answer, targets: [circled], about: ink, room: room, overDark: false))
            phase = .missed
        }
    }

    /// Whether `mark` circles `target`, or an arrow ends on it.
    private static func points(at target: CGRect, _ mark: Mark) -> Bool {
        switch mark.geometry {
        case .ellipse(let frame):
            return frame.insetBy(dx: -8, dy: -8).contains(CGPoint(x: target.midX, y: target.midY))
        case .arrow(let arrow):
            return target.insetBy(dx: -24, dy: -24).contains(arrow.end)
        default:
            return false
        }
    }

    // MARK: Your desktop

    private func name(_ ink: [Mark]) {
        guard let liveInk, let circled = ink.compactMap(\.shapeExtent).last else { return }
        let point = CGPoint(x: circled.midX, y: circled.midY)
        let said = Self.describe(at: point)
        let screen = NSScreen.screens.first { Self.global($0.frame).contains(point) } ?? NSScreen.main
        let room = screen.map { Self.global($0.visibleFrame) } ?? circled.insetBy(dx: -400, dy: -300)
        let answer = LiveAnswer(say: said, marks: [AnswerMark(kind: .circle, label: said)])
        shown.formUnion(liveInk.showPracticeAnswer(answer, targets: [circled], about: ink, room: room, overDark: false))
        phase = .saw(said)
        Log.write("[setup] live ink try saw \"\(said)\"")
        // Long enough to read the label, then the ink is done and the window comes back for the check.
        after(2.2) { [weak self] in
            guard let self else { return }
            self.liveInk?.letGoOfPractice(self.shown, .done)
            self.shown = []
            self.comeBack()
            self.after(0.35 * Settings.shared.motionScale) { [weak self] in self?.successes += 1 }
        }
    }

    /// What Vignette can say about what is at `point` without a capture: the window's app, and its
    /// title or page from Accessibility.
    static func describe(at point: CGPoint) -> String {
        if let screen = NSScreen.screens.first(where: { global($0.frame).contains(point) }),
           point.y - global(screen.frame).minY < NSStatusBar.system.thickness {
            return "The menu bar"
        }
        guard let window = LiveWindows.window(under: point) else { return "Your desktop" }
        let app = window.app ?? "A window"
        let page = LivePacket.page(pid: window.pid, frame: window.frame)?.location
        let host = page.flatMap { URL(string: $0)?.host }
        let detail = host ?? title(pid: window.pid, frame: window.frame)
        let words = [app, detail].compactMap { $0 }.joined(separator: ": ")
        return words.count > LiveAnswer.maxLabel ? String(words.prefix(LiveAnswer.maxLabel - 1)) + "…" : words
    }

    /// The title of the app's window at `frame`, from Accessibility, which needs no Screen Recording.
    private static func title(pid: pid_t, frame: CGRect) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let windows = WindowAccessibility.attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for window in windows {
            guard let position = WindowAccessibility.attribute(window, kAXPositionAttribute) else { continue }
            var origin = CGPoint.zero
            AXValueGetValue(position as! AXValue, .cgPoint, &origin)
            guard abs(origin.x - frame.minX) < 2, abs(origin.y - frame.minY) < 2 else { continue }
            return (WindowAccessibility.attribute(window, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        return nil
    }

    /// A screen rect in AppKit's coordinates, in global top-left points.
    private static func global(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: StateReport.primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The window shrinks into a strip at the foot of the screen, so the whole screen can be drawn on.
    private func stepAside() {
        guard !steppedAside, let window, let screen = window.screen ?? NSScreen.main else { return }
        home = window.frame
        steppedAside = true
        let size = NSSize(width: 360, height: 72)
        let visible = screen.visibleFrame
        move(window, to: NSRect(x: visible.midX - size.width / 2, y: visible.minY + 28, width: size.width, height: size.height))
    }

    private func comeBack() {
        guard steppedAside, let home, let window else { return }
        steppedAside = false
        self.home = nil
        move(window, to: home)
    }

    private func move(_ window: NSWindow, to frame: NSRect) {
        let motion = Settings.shared.motionScale
        guard motion > 0 else {
            window.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5 * motion
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1)
            window.animator().setFrame(frame, display: true)
        }
    }

    private func after(_ seconds: TimeInterval, _ work: @escaping () -> Void) {
        let item = DispatchWorkItem(block: work)
        later = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }
}

/// Setup's live ink page, in the concept the model names.
struct LiveInkPage: View {
    @ObservedObject var model: SetupModel
    @ObservedObject private var settings = Settings.shared
    @State private var trusted = ModifierTap.trusted(prompt: false)
    @State private var screenRecording = ScreenRecording.granted
    @State private var askedScreenRecording = false
    private let poll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var tried: SetupInkTry { model.inkTry }

    var body: some View {
        VStack(spacing: 4) {
            switch model.inkConcept {
            case .findTheBug: findTheBug
            case .desktop: desktop
            case .writesBack: writesBack
            }
            permissions
        }
        .overlay(alignment: .top) {
            // A preview chooses its concept here.
            if model.isPreview {
                Picker("Concept", selection: $model.inkConcept) {
                    ForEach(SetupInkConcept.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
                .padding(.top, 6)
            }
        }
        .onAppear(perform: begin)
        .onChange(of: model.inkConcept) {
            SetupInkConcept.chosen = model.inkConcept
            begin()
        }
        .onReceive(poll) { _ in
            trusted = ModifierTap.trusted(prompt: false)
            screenRecording = ScreenRecording.granted
        }
    }

    private func begin() {
        // The page's switch starts on: someone who reached this page installed Vignette to use it.
        if !settings.data.liveInk, !model.inkSwitchShown { settings.update { $0.liveInk = true } }
        model.inkSwitchShown = true
        tried.begin(model.inkConcept, liveInk: model.callbacks.liveInk) { [weak model] in model?.window }
    }

    // MARK: Find the bug

    private var findTheBug: some View {
        VStack(spacing: 10) {
            OddOneOutScene(found: tried.phase == .found, onFish: { tried.oddOneOut = $0 })
                .background(ScreenRect { tried.scene = $0 })
                .padding(.top, 30)
            Text("Find the bug").font(.title).bold()
            HStack(spacing: 8) {
                ChordKeys(motion: settings.motionScale)
                Text("Hold these and circle what doesn't belong.").foregroundStyle(.secondary)
            }
            status(found: tried.phase == .found) {
                switch tried.phase {
                case .waiting, .saw(_): "Draw with the pointer while you hold them."
                case .inking: "Now circle it."
                case .missed: "Not that one. Try again."
                case .found: "Found it. That's live ink."
                }
            }
        }
    }

    // MARK: Your desktop

    private var desktop: some View {
        VStack(spacing: 10) {
            DesktopPicture().padding(.top, 30)
            Text("Draw on anything").font(.title).bold()
            HStack(spacing: 8) {
                ChordKeys(motion: settings.motionScale)
                Text("Hold these and circle something on your screen.").foregroundStyle(.secondary)
            }
            status(found: tried.successes > 0) {
                if case .saw(let said) = tried.phase { "Vignette saw \(said)." } else { "This window will step aside." }
            }
        }
    }

    // MARK: Writes back

    private var writesBack: some View {
        VStack(spacing: 12) {
            Text("Writes back").font(.title).bold().padding(.top, 60)
            ChordKeys(motion: settings.motionScale)
        }
    }

    // MARK: Pieces

    /// The line under the heading that answers the try, with the check coin once it has worked.
    private func status(found: Bool, _ text: () -> String) -> some View {
        HStack(spacing: 8) {
            if found {
                CheckCoin(diameter: 20).id(tried.successes).transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "hand.draw").foregroundStyle(Color.accentColor).transition(.opacity)
            }
            Text(text()).contentTransition(.opacity)
        }
        .animation(Anim.spring(0.3 * settings.motionScale), value: found)
        .animation(Anim.spring(0.3 * settings.motionScale), value: tried.phase)
        .frame(height: 24)
    }

    /// The switch and what live ink needs: Accessibility for the chord, and Screen Recording for asking.
    private var permissions: some View {
        Form {
            Section {
                Toggle("Live Ink", isOn: Binding(get: { settings.data.liveInk }, set: { on in settings.update { $0.liveInk = on } }))
                if settings.data.liveInk, !trusted {
                    PermissionRow(symbol: "lock.fill", title: "Needs Accessibility permission",
                                  reason: SettingsView.liveInkAccessibilityReason, status: .ask, isDefault: true) { Accessibility.request() }
                }
            }
            if settings.data.liveInk {
                Section {
                    if screenRecording {
                        PermissionRow(symbol: "rectangle.dashed.badge.record", title: "Vignette can see what you ask about", status: .granted) {}
                    } else {
                        PermissionRow(symbol: "rectangle.dashed.badge.record", title: "Asking needs Screen Recording", status: .ask,
                                      isDefault: trusted, button: askedScreenRecording ? "Open Settings…" : "Allow…") {
                            if askedScreenRecording { ScreenRecording.openSystemSettings() } else { ScreenRecording.request() }
                            askedScreenRecording = true
                        }
                    }
                } footer: {
                    Text(SetupInkCopy.costNote).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped).scrollDisabled(true).fixedSize(horizontal: false, vertical: true)
    }
}

/// The window while it is aside: the keys and what to do, at the foot of the screen.
struct SteppedAside: View {
    @ObservedObject var model: SetupModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 12) {
            ChordKeys(motion: settings.motionScale, height: 40)
            Text(model.inkTry.chordDown ? "Circle anything on your screen." : "Let go to see what Vignette saw.")
                .font(.headline).contentTransition(.opacity)
        }
        .animation(Anim.spring(0.25 * settings.motionScale), value: model.inkTry.chordDown)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Control and Option as keycaps that go down while the person holds them, as the shortcut page's
/// keys do.
struct ChordKeys: View {
    var motion = 1.0
    var height: CGFloat = 44
    @StateObject private var held = HeldModifiers()

    var body: some View {
        HStack(spacing: 6) {
            key("⌃", word: "control", down: held.flags.contains(.control))
            key("⌥", word: "option", down: held.flags.contains(.option))
        }
        .onAppear { held.start() }
        .onDisappear { held.stop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Control and Option")
    }

    private func key(_ glyph: String, word: String, down: Bool) -> some View {
        KeyboardKey(width: height * 1.2, height: height, down: down, motion: motion) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(glyph).font(.system(size: height * 0.3))
                Spacer(minLength: 0)
                Text(word).font(.system(size: height * 0.2))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// A sky over hills, with birds flying and a fish flying with them.
struct OddOneOutScene: View {
    var found = false
    /// Hands over where the fish is on the screen, asked again whenever it is needed.
    let onFish: (@escaping () -> CGRect?) -> Void

    static let size = CGSize(width: 330, height: 116)

    var body: some View {
        let w = Self.size.width, h = Self.size.height
        ZStack {
            LinearGradient(colors: [Color(red: 0.55, green: 0.80, blue: 0.98), Color(red: 0.86, green: 0.95, blue: 1)],
                           startPoint: .top, endPoint: .bottom)
            Ellipse().fill(Color(red: 0.49, green: 0.76, blue: 0.43)).frame(width: w * 0.9, height: h * 0.7).position(x: w * 0.25, y: h * 1.08)
            Ellipse().fill(Color(red: 0.38, green: 0.68, blue: 0.36)).frame(width: w, height: h * 0.62).position(x: w * 0.8, y: h * 1.12)
            symbol("sun.max.fill", 30, .yellow).position(x: w * 0.88, y: h * 0.24)
            symbol("cloud.fill", 34, .white).position(x: w * 0.16, y: h * 0.24)
            symbol("cloud.fill", 24, .white.opacity(0.9)).position(x: w * 0.66, y: h * 0.16)
            symbol("bird.fill", 15, Color(white: 0.25)).position(x: w * 0.34, y: h * 0.36)
            symbol("bird.fill", 12, Color(white: 0.3)).position(x: w * 0.44, y: h * 0.24)
            symbol("bird.fill", 14, Color(white: 0.25)).scaleEffect(x: -1).position(x: w * 0.6, y: h * 0.38)
            symbol("fish.fill", 17, Color(red: 0.98, green: 0.55, blue: 0.2))
                .background(ScreenRect(found: onFish))
                .rotationEffect(.degrees(found ? -10 : 0))
                .position(x: w * 0.5, y: h * 0.34)
            symbol("tree.fill", 38, Color(red: 0.2, green: 0.5, blue: 0.25)).position(x: w * 0.16, y: h * 0.7)
            symbol("house.fill", 32, Color(red: 0.91, green: 0.53, blue: 0.35)).position(x: w * 0.74, y: h * 0.72)
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .animation(Anim.spring(0.4, bounce: 0.5), value: found)
        .accessibilityHidden(true)
    }

    private func symbol(_ name: String, _ size: CGFloat, _ color: Color) -> some View {
        Image(systemName: name).font(.system(size: size)).foregroundStyle(color)
    }
}

/// A desktop in miniature: a few windows on a wallpaper, for the page that draws on the real one.
struct DesktopPicture: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.78), Color(red: 0.75, green: 0.5, blue: 0.75)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            window(width: 150, height: 74).position(x: 110, y: 56)
            window(width: 120, height: 64).position(x: 225, y: 70)
            Ellipse().strokeBorder(Color.white.opacity(0.9), lineWidth: 2.5).frame(width: 82, height: 46).position(x: 228, y: 72)
        }
        .frame(width: 330, height: 116)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .accessibilityHidden(true)
    }

    private func window(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.5)).frame(width: 5, height: 5) }
                Spacer()
            }
            .padding(5)
            Spacer()
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.85)))
    }
}

/// Reads where the view it is behind is on the screen, in global top-left points.
struct ScreenRect: NSViewRepresentable {
    let found: (@escaping () -> CGRect?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        found { [weak view] in
            guard let view, let window = view.window else { return nil }
            let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
            return CGRect(x: rect.minX, y: StateReport.primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
