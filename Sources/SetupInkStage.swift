import AppKit
import SwiftUI

/// Where a page's live ink is drawn: a view over the page, in its points, y down, holding the real
/// pen layers and the marks layer live ink draws with. It takes no presses.
final class SetupInkStage: NSView {
    let marks: LiveMarksLayer
    /// Runs each display refresh while `isRunning`, with the time that refresh will show, on the ink's
    /// own clock, so the hand moves just before the ink is drawn.
    var onFrame: ((CFTimeInterval) -> Void)?
    var isRunning = false { didSet { if isRunning != oldValue { runClock() } } }
    private let scale: CGFloat

    init() {
        scale = NSScreen.main?.backingScaleFactor ?? 2
        marks = LiveMarksLayer(scale: scale)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(marks)
        marks.host = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// A new pen, above the marks.
    func pen() -> InkMarkLayer {
        let pen = InkMarkLayer(scale: scale)
        layer?.addSublayer(pen)
        return pen
    }

    /// This view's frame, in global top-left points.
    var globalFrame: CGRect? {
        guard let window else { return nil }
        return StateReport.flipped(window.convertToScreen(convert(bounds, to: nil)))
    }

    /// This view's top-left corner, in global top-left points.
    var globalOrigin: CGPoint? { globalFrame?.origin }

    /// The marks drawn over a page are the agent's light on a dark window.
    var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        runClock()
    }

    private func runClock() {
        let runs = isRunning && window != nil
        InkClock.shared.onTick(self, runs ? { [weak self] in self?.onFrame?($0) } : nil)
    }
}

/// A stroke a hand writes on a stage with the real pen, drawn each refresh as far as the hand has got.
@MainActor
struct StageWriting {
    let pen: InkMarkLayer
    let hand: HandStroke
    let began: CFTimeInterval
    var writer: InkHand.Pen

    /// Draws the stroke as far as the hand has got at `now`, and says whether the hand has finished.
    mutating func draw(at now: CFTimeInterval, markStyle: MarkStyle) -> Bool {
        let elapsed = now - began
        let points = hand.events(by: elapsed)
        guard points.count > 1 else { return false }
        var stroke = writer.stroke(through: points)
        // The pen takes whole events; its end goes on to where the hand is at this refresh.
        if let tip = hand.position(at: elapsed), let end = stroke.points.last, let width = stroke.widths.last,
           hypot(tip.x - end.x, tip.y - end.y) > 0.25 {
            stroke.points.append(tip)
            stroke.widths.append(width)
        }
        pen.showPen(stroke, settled: writer.settled.points.count, longest: .greatestFiniteMagnitude, markStyle: markStyle, byClock: true)
        return elapsed >= hand.duration
    }
}

/// The stage, laid over a page.
struct SetupInkCanvas: NSViewRepresentable {
    let stage: SetupInkStage

    func makeNSView(context: Context) -> SetupInkStage { stage }
    func updateNSView(_ nsView: SetupInkStage, context: Context) {}
}

/// The parts of a page the ink is drawn round, by name, for the stage laid over it.
struct SetupInkAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Names this view's bounds for the ink stage over the page, beside the names inside it.
    func inkAnchor(_ name: String) -> some View {
        transformAnchorPreference(key: SetupInkAnchors.self, value: .bounds) { $0[name] = $1 }
    }

    /// Lays `stage` over this page.
    func inkStage(_ stage: SetupInkStage) -> some View {
        overlay { SetupInkCanvas(stage: stage).allowsHitTesting(false) }
    }

    /// Lays `stage` over this page, and hands `place` the page's named parts, in the stage's points,
    /// whenever they move.
    func inkStage(_ stage: SetupInkStage, place: @escaping ([String: CGRect]) -> Void) -> some View {
        overlayPreferenceValue(SetupInkAnchors.self) { anchors in
            GeometryReader { geometry in
                let rects = anchors.mapValues { geometry[$0] }
                SetupInkCanvas(stage: stage)
                    .allowsHitTesting(false)
                    .onAppear { place(rects) }
                    .onChange(of: rects) { place(rects) }
            }
        }
    }
}
