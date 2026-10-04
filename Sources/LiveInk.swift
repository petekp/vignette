import AppKit

/// Live ink: drawing straight on the screen, over any app, while Control and Option are held
/// (docs/live-ink-integration-2026-10-04.md). A loop becomes an ellipse and any other stroke an
/// arrow, in the person's colour, and a tap on a mark erases it. The marks stay where they were drawn
/// until they are erased or cleared, live ink is turned off, or Vignette quits. Nothing is sent to an
/// agent yet.
@MainActor
final class LiveInk {
    /// In global top-left points, the coordinates `[state]` uses, at 1 px per pt. The newest is last.
    private(set) var marks: [Mark] = []
    /// The chord is held and the overlays take presses.
    private(set) var isInking = false
    private var overlays: [LiveInkOverlay] = []
    private var chord: ModifierChord?
    private var screenObserver: Any?
    private var glowTimer: Timer?
    private var glowing = false
    /// Runs while a stroke outlives the chord, until the button is up: inking ends then.
    private var releaseWatch: Timer?
    /// Asked when the chord goes down: false while the stack or the annotator holds the screen, which
    /// the raised overlays would cover and take presses from.
    private let mayInk: () -> Bool

    var isOn: Bool { chord != nil }

    init(mayInk: @escaping () -> Bool) {
        self.mayInk = mayInk
    }

    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            chord = ModifierChord([.control, .option], tag: "live-ink", name: "the chord") { [weak self] change in
                self?.chordChanged(change)
            }
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.makeOverlays() }
            }
            makeOverlays()
        } else {
            if isInking { stopInking() }
            chord = nil
            if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
            screenObserver = nil
            marks = []
            overlays.forEach { $0.close() }
            overlays = []
        }
        Log.write("[live-ink] \(on ? "on" : "off")")
    }

    /// What a stroke did, as `[live-ink]` lines and `live-ink-stroke` answer it.
    enum Outcome: Equatable {
        case drew(MarkKind)
        case erased(MarkKind)
        /// A tap on no mark.
        case missed
        /// A stroke that is no mark and no tap.
        case nothing

        var description: String {
            switch self {
            case .drew(let kind): "drew \(kind.rawValue)"
            case .erased(let kind): "erased \(kind.rawValue)"
            case .missed: "tap on no mark"
            case .nothing: "nothing"
            }
        }
    }

    /// Reads `points`, in global top-left points, as a stroke the person drew, and does what it says:
    /// adds its mark, or erases the mark a tap lands on. The debug command's strokes come here too,
    /// whether the stack or the annotator is up or not.
    @discardableResult
    func take(_ points: [CGPoint]) -> Outcome {
        let ui = Settings.shared.data.ui
        let outcome: Outcome
        switch InkStroke(points, shortestArrow: ui.shortestArrow) {
        case .ellipse(let frame):
            marks.append(Mark(geometry: .ellipse(frame)))
            outcome = .drew(.ellipse)
        case .arrow(let arrow):
            marks.append(Mark(geometry: .arrow(arrow)))
            outcome = .drew(.arrow)
        case .tap(let point):
            if let index = Self.topmostMark(at: point, in: marks, markStyle: ui.markStyle, hitMargin: ui.hitMargin) {
                outcome = .erased(marks.remove(at: index).kind)
            } else {
                outcome = .missed
            }
        case .nothing:
            outcome = .nothing
        }
        Log.write("[live-ink] \(outcome.description) marks=\(marks.count)")
        showMarks()
        return outcome
    }

    /// Erases every mark, and says how many there were.
    @discardableResult
    func clear() -> Int {
        let count = marks.count
        marks = []
        showMarks()
        Log.write("[live-ink] cleared \(count)")
        return count
    }

    /// The stack or the annotator is coming up under the raised overlays: inking stops, the stroke
    /// under way is dropped, and the chord must be pressed again to ink.
    func standAside() {
        guard isInking else { return }
        Log.write("[live-ink] standing aside: the stack or the annotator is up")
        stopInking()
    }

    /// The marks and the glow drawn again in the current settings.
    func applyTweaks() {
        showMarks()
        if glowing { showGlow(true) }
    }

    /// The index of the topmost mark whose stroke `point` is on, by the editor's measure: within half
    /// the stroke and `hitMargin` of its centre line.
    nonisolated static func topmostMark(at point: CGPoint, in marks: [Mark], markStyle: MarkStyle, hitMargin: CGFloat) -> Int? {
        marks.lastIndex { mark in
            guard let distance = EditorGeometry.strokeDistance(from: point, to: mark, pointScale: 1) else { return false }
            return distance <= markStyle.strokeWidth / 2 + hitMargin
        }
    }

    var stateJSON: [String: Any] {
        [
            "on": isOn,
            "inking": isInking,
            "chord": chord?.isHeld ?? false,
            "overlays": overlays.map { overlay -> [String: Any] in
                ["frame": StateReport.topLeft(overlay.frame, primaryHeight: StateReport.primaryHeight), "visible": overlay.isVisible]
            },
            "marks": marks.map { mark -> [String: Any] in
                let frame = mark.shapeExtent.map { [$0.minX, $0.minY, $0.width, $0.height].map { Int($0.rounded()) } } ?? []
                return ["type": mark.kind.rawValue, "frame": frame]
            },
        ]
    }

    // MARK: Inking

    private func chordChanged(_ change: HeldChord.Change) {
        switch change {
        case .began:
            guard mayInk() else {
                Log.write("[live-ink] not inking: the stack or the annotator is up")
                return
            }
            startInking()
        case .ended:
            guard isInking else { return }
            if overlays.contains(where: \.isTracking) { watchRelease() } else { stopInking() }
        }
    }

    private func startInking() {
        isInking = true
        // Pressed again before the button came up: the stroke now ends without ending the inking.
        releaseWatch?.invalidate()
        releaseWatch = nil
        overlays.forEach { $0.setInking(true) }
        showOverlays()
        // The glow waits, so holding the chord on the way to a key, as in a window manager's
        // Control-Option-arrow, does not flash it. A press shows it at once.
        glowTimer?.invalidate()
        glowTimer = Timer.scheduledTimer(withTimeInterval: Settings.shared.data.ui.liveInkGlowDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showGlow(true) }
        }
        Log.write("[live-ink] inking")
    }

    private func stopInking() {
        isInking = false
        releaseWatch?.invalidate()
        releaseWatch = nil
        glowTimer?.invalidate()
        overlays.forEach { $0.setInking(false) }
        showGlow(false)
        showOverlays()
        Log.write("[live-ink] stopped")
    }

    private func strokeMoved(_ points: [CGPoint]) {
        if !points.isEmpty, !glowing { showGlow(true) }
        let markStyle = Settings.shared.data.ui.markStyle
        overlays.forEach { $0.showPen(points, markStyle: markStyle) }
    }

    private func strokeEnded(_ points: [CGPoint]) {
        take(points)
        if releaseWatch != nil { stopInking() }
    }

    /// The chord was let go during a stroke. The stroke keeps going to its release, and inking ends
    /// with it. A release that never reaches the overlay is read from the button's own state, as the
    /// flight layer's `watchRelease` does, and the stroke ends with the points it has. A stroke whose
    /// overlay was made again under it, when the screens changed, is lost.
    private func watchRelease() {
        releaseWatch?.invalidate()
        releaseWatch = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self.releaseWatch?.invalidate()
                self.releaseWatch = nil
                self.overlays.forEach { $0.endStroke() }
                self.stopInking()
            }
        }
    }

    private func showGlow(_ on: Bool) {
        glowTimer?.invalidate()
        if !on && !glowing { return }
        glowing = on
        let ui = Settings.shared.motionUI
        let color = ui.markStyle.color(.person)
        overlays.forEach { $0.showGlow(on, ui: ui, color: color) }
    }

    // MARK: Overlays

    /// One overlay per screen, made again whenever the screens change.
    private func makeOverlays() {
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map { screen in
            let overlay = LiveInkOverlay(screen: screen)
            overlay.onStrokeMoved = { [weak self] points in self?.strokeMoved(points) }
            overlay.onStroke = { [weak self] points in self?.strokeEnded(points) }
            overlay.setInking(isInking)
            return overlay
        }
        showMarks()
        if glowing { showGlow(true) }
    }

    private func showMarks() {
        let markStyle = Settings.shared.data.ui.markStyle
        overlays.forEach { $0.show(marks, markStyle: markStyle) }
        showOverlays()
    }

    /// The overlays are on screen while there are marks or the chord is held, and off it otherwise,
    /// so an idle live ink puts no full-screen window over every app.
    private func showOverlays() {
        let needed = isInking || !marks.isEmpty
        let fade = Settings.shared.motionUI.liveInkGlowFade
        overlays.forEach { $0.setNeeded(needed, fade: fade) }
    }
}
