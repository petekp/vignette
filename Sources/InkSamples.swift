import AppKit
import Combine
import QuartzCore

/// Live ink's marks drawn over whatever is on the screen, to tweak the ink against: the person's loop,
/// arrow and box above, as a hand drew them, and an agent's three marks in light below. They redraw
/// with every tweak. A window dragged under them shows how they read on it, and Replay reads the
/// screen behind them again and draws them on. The tweak panel shows them, and hides them with itself.
@MainActor
final class InkSamples: ObservableObject {
    @Published private(set) var isShown = false
    /// The window they are placed beside.
    weak var beside: NSWindow?

    private var window: NSPanel?
    private var ink: [(layer: InkMarkLayer, mark: Mark, raw: [CGPoint]?)] = []
    private var light: [(layer: LightMarkLayer, mark: Mark)] = []
    private var settingsChanged: AnyCancellable?

    /// One sample's room, in points: three across, the person's row over the agent's.
    private static let cell = CGSize(width: 230, height: 190)
    private static let inset: CGFloat = 36

    func toggle() { isShown ? hide() : show() }

    func show() {
        let window = window ?? make()
        place(window)
        window.orderFrontRegardless()
        isShown = true
        draw()
        replay()
        settingsChanged = Settings.shared.objectWillChange.sink { [weak self] _ in
            // The settings change after their will-change notice.
            DispatchQueue.main.async { self?.draw() }
        }
    }

    func hide() {
        settingsChanged = nil
        window?.orderOut(nil)
        isShown = false
    }

    /// Reads the screen behind the samples again, then draws them on as live ink does.
    func replay() {
        guard isShown else { return }
        InkBackdrop.shared.refresh { [weak self] in self?.draw() }
        let motion = Settings.shared.motionUI
        let markStyle = Settings.shared.data.ui.markStyle
        var delay: CFTimeInterval = 0
        for sample in ink {
            if let raw = sample.raw, let hand = InkHand(raw: raw, mark: sample.mark, feel: Settings.shared.data.ui.inkHandFeel) {
                sample.layer.show(sample.mark, hand: hand, markStyle: markStyle)
                sample.layer.ease(from: hand.drawn(for: sample.mark), duration: motion.inkSettle)
            } else {
                sample.layer.drawOn(after: delay, duration: motion.liveInkDrawOn)
                delay += motion.liveInkDrawOn * 0.6
            }
        }
        for sample in light {
            sample.layer.drawOn(after: delay, duration: motion.liveInkDrawOn, settle: LiveMarksLayer.lightSettle * Settings.shared.motionScale)
            delay += motion.liveInkDrawOn * 0.6
        }
    }

    private func make() -> NSPanel {
        let size = CGSize(width: Self.cell.width * 3, height: Self.cell.height * 2)
        let window = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = Canvas(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        window.contentView = view
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let (person, agent) = Self.marks()
        ink = person.map { mark, raw in
            let layer = InkMarkLayer(scale: scale)
            view.layer?.addSublayer(layer)
            return (layer, mark, raw)
        }
        light = agent.map { mark in
            let layer = LightMarkLayer(scale: scale)
            view.layer?.addSublayer(layer.root)
            return (layer, mark)
        }
        self.window = window
        return window
    }

    /// Beside the panel on the side with more room, level with it, and inside the screen. They are over
    /// every app's window, so one dragged under them shows how they read on it, and under the panel,
    /// unless the screen has no room beside it: then over it, since they let presses through.
    private func place(_ window: NSWindow) {
        guard let screen = beside?.screen ?? NSScreen.main else { return }
        let room = screen.visibleFrame
        let size = window.frame.size
        let panel = beside?.frame ?? CGRect(x: room.minX, y: room.midY, width: 0, height: 0)
        let right = room.maxX - panel.maxX, left = panel.minX - room.minX
        let fits = max(right, left) >= size.width + 24
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + (fits ? -1 : 1))
        var x = right >= left ? panel.maxX + 24 : panel.minX - 24 - size.width
        var y = panel.midY - size.height / 2
        x = min(max(x, room.minX), room.maxX - size.width)
        y = min(max(y, room.minY), room.maxY - size.height)
        window.setFrameOrigin(CGPoint(x: x, y: y))
    }

    /// Draws every sample as the tweaks say now, each agent mark for the brightness behind it.
    private func draw() {
        guard isShown, let window else { return }
        let ui = Settings.shared.data.ui
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for sample in ink {
            let hand = sample.raw.flatMap { InkHand(raw: $0, mark: sample.mark, feel: ui.inkHandFeel) }
            sample.layer.show(sample.mark, hand: hand, markStyle: ui.markStyle)
        }
        // The window's top-left in global top-left points, the backdrop's coordinates.
        let origin = CGPoint(x: window.frame.minX, y: StateReport.primaryHeight - window.frame.maxY)
        for sample in light {
            let extent = (sample.mark.shapeExtent ?? .zero).offsetBy(dx: origin.x, dy: origin.y)
            let dark = InkBackdrop.shared.brightness(in: extent).map { $0 <= LivePacket.Luminance.dark } ?? false
            sample.layer.show(sample.mark, markStyle: ui.markStyle, dark: dark)
        }
        CATransaction.commit()
    }

    /// The person's marks, each with the pointer's points a hand would have sent for it, or none for
    /// one drawn evenly, and the agent's, in the window's top-left points.
    private static func marks() -> (person: [(Mark, [CGPoint]?)], agent: [Mark]) {
        func room(_ column: Int, _ row: Int) -> CGRect {
            CGRect(x: CGFloat(column) * cell.width, y: CGFloat(row) * cell.height, width: cell.width, height: cell.height)
                .insetBy(dx: inset, dy: inset)
        }
        let loop = room(0, 0)
        let arrow = room(1, 0)
        let arrowLine = (CGPoint(x: arrow.minX, y: arrow.maxY), CGPoint(x: arrow.midX + 10, y: arrow.minY - 6), CGPoint(x: arrow.maxX, y: arrow.minY + 20))
        let person: [(Mark, [CGPoint]?)] = [
            (Mark(geometry: .ellipse(loop)), handLoop(in: loop)),
            (Mark(geometry: .arrow(Mark.Arrow(start: arrowLine.0, end: arrowLine.2,
                                              via: [bezier(arrowLine, 1.0 / 3), bezier(arrowLine, 2.0 / 3)]))), handArrow(arrowLine)),
            (Mark(geometry: .rectangle(room(2, 0))), nil),
        ]
        let agentArrow = room(1, 1)
        let agent = [
            Mark(geometry: .ellipse(room(0, 1)), agent: true),
            Mark(geometry: .arrow(Mark.Arrow(start: CGPoint(x: agentArrow.minX, y: agentArrow.maxY),
                                             end: CGPoint(x: agentArrow.maxX, y: agentArrow.minY), bend: 24)), agent: true),
            Mark(geometry: .rectangle(room(2, 1)), agent: true),
        ]
        return (person, agent)
    }

    /// How fast a hand moves at `t`, 0 to 1 of the way: slow to start, quick through the middle, slowing
    /// at the end.
    private static func speed(_ t: CGFloat) -> CGFloat { 0.3 + 1.4 * pow(sin(.pi * min(max(t, 0), 1)), 1.5) }

    /// A loop round `frame` from its upper left and a little past, its points one pointer event apart,
    /// so they spread out where the hand is quick.
    private static func handLoop(in frame: CGRect) -> [CGPoint] {
        let first: CGFloat = -0.75 * .pi, turn: CGFloat = 2 * .pi + 0.4
        let step = turn / 70
        var points: [CGPoint] = []
        var angle: CGFloat = 0
        while angle <= turn {
            let at = first + angle
            let wobble = 1 + 0.035 * sin(3 * at)
            points.append(CGPoint(x: frame.midX + frame.width / 2 * wobble * cos(at), y: frame.midY + frame.height / 2 * wobble * sin(at)))
            angle += step * speed(angle / turn)
        }
        return points
    }

    /// An arrow's body along `line`, a quadratic curve, its points one pointer event apart.
    private static func handArrow(_ line: (CGPoint, CGPoint, CGPoint)) -> [CGPoint] {
        var points: [CGPoint] = []
        var t: CGFloat = 0
        while t <= 1 {
            points.append(bezier(line, t))
            t += speed(t) / 40
        }
        points.append(line.2)
        return points
    }

    private static func bezier(_ line: (CGPoint, CGPoint, CGPoint), _ t: CGFloat) -> CGPoint {
        let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t
        return CGPoint(x: a * line.0.x + b * line.1.x + c * line.2.x, y: a * line.0.y + b * line.1.y + c * line.2.y)
    }

    /// Flipped, so its layer runs y down like the marks.
    private final class Canvas: NSView {
        override var isFlipped: Bool { true }
    }
}
