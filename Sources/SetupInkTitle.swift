import AppKit

/// The live ink page's title, "Live Ink" in cursive: the centre lines a hand writes it along, in three
/// strokes, "Live", the i's dot, then "Ink". The page writes them in the real ink, through the pen
/// the person's own strokes are drawn with.
enum SetupInkTitle {
    /// In points, y down, from the start of the baseline, in the order the pen goes.
    static let strokes: [[CGPoint]] = [
        [(34, -46), (44, -64), (55, -80), (62, -88), (57, -92), (48, -86), (40, -70), (33, -50), (26, -30), (18, -13), (10, -3),
         (1, 2), (-7, 0), (-7, -6), (2, -9), (15, -6), (27, 0), (38, -5), (45, -16), (49, -26), (47, -14), (48, -3), (55, 0),
         (62, -8), (66, -26), (69, -10), (73, 0), (79, -10), (84, -26), (88, -21), (95, -19), (102, -21), (107, -27), (102, -31),
         (96, -25), (95, -11), (101, -1), (111, 0), (121, -6)],
        [(49, -43), (52, -44), (54, -41), (52, -38), (49, -39), (48, -41), (50, -43)],
        [(147, -36), (154, -60), (166, -78), (178, -84), (175, -72), (169, -46), (162, -18), (155, -3), (145, 2), (138, -4),
         (145, -10), (160, -9), (172, -7), (178, -14), (180, -26), (180, -12), (180, 0), (183, -13), (190, -24), (198, -26),
         (201, -17), (201, -5), (205, 0), (212, -5), (218, -24), (224, -56), (230, -80), (225, -88), (218, -76), (215, -46),
         (213, -16), (213, 0), (217, -12), (224, -22), (232, -26), (236, -20), (230, -13), (221, -11), (229, -6), (236, -1),
         (246, -3)],
    ].map { $0.map { CGPoint(x: $0.0, y: $0.1) } }

    /// Room round the lines for the ink's width and glow, in points.
    private static let margin: CGFloat = 18

    private static let extent = InkStroke.bounds(of: strokes.flatMap { ArrowBody.Curve(through: $0).samples })

    /// The room the title takes on the page.
    static var size: CGSize { CGSize(width: extent.width + 2 * margin, height: extent.height + 2 * margin) }

    /// Stroke `index` in a room whose top-left is `origin`.
    static func stroke(_ index: Int, in origin: CGPoint) -> [CGPoint] {
        let shift = CGPoint(x: origin.x + margin - extent.minX, y: origin.y + margin - extent.minY)
        return strokes[index].map { CGPoint(x: $0.x + shift.x, y: $0.y + shift.y) }
    }

    /// The hand starting stroke `index` on `stage` at `now`, in a room whose top-left is `origin`.
    @MainActor
    static func write(_ index: Int, on stage: SetupInkStage, in origin: CGPoint, at now: CFTimeInterval) -> StageWriting {
        StageWriting(pen: stage.pen(), hand: HandStroke(through: stroke(index, in: origin), duration: SetupInkDemo.writing[index]),
                     began: now, writer: InkHand.Pen(feel: Settings.shared.data.ui.inkHandFeel))
    }

    /// The title written whole on `stage`, in a room whose top-left is `origin`: a pen for each stroke.
    @MainActor
    static func written(on stage: SetupInkStage, in origin: CGPoint) -> [InkMarkLayer] {
        let ui = Settings.shared.data.ui
        return SetupInkDemo.writing.enumerated().map { index, duration in
            let hand = HandStroke(through: stroke(index, in: origin), duration: duration)
            let pen = stage.pen()
            pen.showPen(InkHand.stroke(hand.points, tapersEnd: true, feel: ui.inkHandFeel), settled: 0, longest: .greatestFiniteMagnitude,
                        markStyle: ui.markStyle)
            return pen
        }
    }
}

/// The title on a stage of its own, at `scale` of setup's size, as the Live Ink tab shows it. The
/// hand writes it the first time it appears in a launch; after that, and with motion off, it shows
/// written.
@MainActor
final class InkTitleWriter: ObservableObject {
    let stage = SetupInkStage()
    private static var writtenThisLaunch = false
    private var pens: [InkMarkLayer] = []
    private var writing: [StageWriting] = []
    private var began: CFTimeInterval = 0
    /// How many strokes the hand has started.
    private var started = 0

    init(scale: CGFloat) {
        stage.layer?.sublayerTransform = CATransform3DMakeScale(scale, scale, 1)
    }

    private var isWriting: Bool { started < SetupInkTitle.strokes.count || !writing.isEmpty }

    func appear() {
        guard pens.isEmpty else { return }
        guard !Self.writtenThisLaunch, Settings.shared.motionScale > 0 else {
            pens = SetupInkTitle.written(on: stage, in: .zero)
            return
        }
        Self.writtenThisLaunch = true
        // Before the first stroke, which would otherwise wait for the gel's first drawing.
        InkMarkLayer.warmUp(scale: stage.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        began = CACurrentMediaTime()
        started = 0
        stage.onFrame = { [weak self] in self?.refreshed(showing: $0) }
        stage.isRunning = true
    }

    /// The tab went. A title cut short is shown written the next time it appears.
    func disappear() {
        stage.isRunning = false
        guard isWriting else { return }
        started = SetupInkTitle.strokes.count
        writing = []
        pens.forEach { $0.removeFromSuperlayer() }
        pens = []
    }

    private func refreshed(showing now: CFTimeInterval) {
        while started < SetupInkTitle.strokes.count, SetupInkDemo.writingStarts[started] <= now - began {
            let stroke = SetupInkTitle.write(started, on: stage, in: .zero, at: now)
            pens.append(stroke.pen)
            writing.append(stroke)
            started += 1
        }
        let markStyle = Settings.shared.data.ui.markStyle
        for index in writing.indices.reversed() where writing[index].draw(at: now, markStyle: markStyle) {
            writing.remove(at: index)
        }
        if !isWriting { stage.isRunning = false }
    }
}
