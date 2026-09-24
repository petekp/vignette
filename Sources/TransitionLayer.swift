import AppKit
import SwiftUI

/// A full-screen layer that flies card images between the stack and the annotator. Flights are
/// SwiftUI state, so a flight that is retargeted mid-way turns smoothly instead of restarting. It
/// takes the presses on a flying card or a swallow rect and nothing else: the window server gives a window
/// only the presses on pixels it draws, and passes one on a clear pixel or on a shadow (measured 2026-09-23).
/// That holds only while `ignoresMouseEvents` is never set: set to false, it takes clear pixels too.
@MainActor
final class TransitionLayer {
    /// The ends of the straight path a flight is on, and the shape it follows along it.
    struct Path {
        var from: CGPoint = .zero
        var to: CGPoint = .zero
        var curve = FlightCurve.straight
    }

    /// How a flight is drawn: the corner and the shadow of the thing it stands in for. A flight's
    /// ends are a card in the stack and the annotator window, and the look travels with the frame,
    /// so the shadow a card has when it lands is the one the flight was already casting.
    struct Look: Equatable {
        var corner: CGFloat
        var shadowOpacity: Double
        var shadowRadius: CGFloat
        var shadowY: CGFloat        // down the screen, the way SwiftUI counts it

        static func card(_ ui: UITweaks) -> Look {
            Look(corner: ui.cardCornerRadius, shadowOpacity: ui.cardShadowOpacity,
                 shadowRadius: ui.cardShadowRadius, shadowY: ui.cardShadowY)
        }
        /// The annotator window's frame view carries exactly this shadow; see `AnnotationController`.
        static func annotator(_ ui: UITweaks) -> Look {
            Look(corner: ui.annotationCornerRadius, shadowOpacity: 0.45, shadowRadius: 24, shadowY: 10)
        }
    }

    struct Flight: Identifiable {
        let id: UUID
        var image: NSImage
        /// The drawing's marks over the image, or nil when it has none.
        var marks: MarkLayers?
        var frame: CGRect      // top-left origin, in the layer's own coordinates
        var look: Look
        var opacity: Double = 1
        /// The path this flight is on, and the one it was on before it was aimed again.
        var path = Path()
        var previousPath = Path()
        /// 0 the moment a flight is aimed down a new path, 1 once it has settled there. In between
        /// the bow comes from both paths, so a retarget bends instead of stepping sideways.
        var blend: CGFloat = 1
        var generation = 0
        /// Runs when `end(id:)` or `endAll()` removes this flight before it arrived, so whatever it
        /// was covering can take over. Aiming the flight again replaces it; arriving clears it.
        /// `converge` removes its pieces without running it, which nothing can notice today: only
        /// the annotator's outbound flight sets a handler, and `ThumbnailController.stitched`
        /// refuses to start a stitch while the annotator has anything in flight.
        var dropped: (() -> Void)?
    }

    /// A rect that swallows every press for a while, whatever is under it.
    struct SwallowRect: Identifiable {
        let id = UUID()
        let rect: NSRect       // on screen
        let frame: CGRect      // top-left origin, in the layer's own coordinates
    }

    final class Model: ObservableObject {
        @Published var flights: [Flight] = []
        @Published var swallowRects: [SwallowRect] = []
    }

    /// A press on a flying card, and the drag and release that follow it, with the flight it began
    /// on: nil when it began beside a picture. `FlightPress` decides where it goes.
    var onPress: ((UUID?, FlightPress.Event) -> Void)?

    private let panel: NSPanel
    private let model = Model()
    private let hosting: NSHostingView<FlightsView>
    /// The flight the press now down began on, and whether one is down: the panel stays up until
    /// its release, since the window server sends the drag and the release to the window that took the press.
    private var pressedFlight: UUID?
    private var pressDown = false
    /// Watches the button while a press is down, for a release that never arrives; see `watchRelease`.
    private var releaseWatch: Timer?
    private var screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
    /// Flights whose spring has settled on the target, and flights waiting to be lifted when it does.
    private var arrivedFlights: Set<UUID> = []
    private var pendingLift: Set<UUID> = []
    /// How close a flight has to be to its target before something else may take its place:
    /// one pixel on a Retina display.
    private static let arrivalTolerance: CGFloat = 0.5
    /// Counts every flight this layer has started, so no two ever share a generation.
    private var nextGeneration = 0

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        hosting = NSHostingView(rootView: FlightsView(model: model))
        let catcher = PressCatcher()
        hosting.autoresizingMask = [.width, .height]
        catcher.addSubview(hosting)
        panel.contentView = catcher
        catcher.onEvent = { [weak self] event in self?.pressed(event) }
    }

    private func pressed(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // A swallow rect takes the press before any flight over it.
            let onScreen = panel.convertPoint(toScreen: event.locationInWindow)
            pressedFlight = model.swallowRects.contains { $0.rect.contains(onScreen) } ? nil : flight(at: event.locationInWindow)
            pressDown = true
            watchRelease()
            report(.pressed(clickCount: event.clickCount), at: event.locationInWindow, modifiers: event.modifierFlags, time: event.timestamp)
        case .leftMouseDragged:
            report(.dragged, at: event.locationInWindow, modifiers: event.modifierFlags, time: event.timestamp)
        case .leftMouseUp:
            released(at: event.locationInWindow, modifiers: event.modifierFlags, time: event.timestamp)
        default:
            break
        }
    }

    private func released(at point: NSPoint, modifiers: NSEvent.ModifierFlags, time: TimeInterval) {
        guard pressDown else { return }
        let flightID = pressedFlight
        let picture = flightID.flatMap { fraction(of: point, on: $0) }
        pressedFlight = nil
        pressDown = false
        releaseWatch?.invalidate()
        releaseWatch = nil
        orderOutIfIdle()
        onPress?(flightID, FlightPress.Event(phase: .released, picture: picture, screen: panel.convertPoint(toScreen: point),
                                             modifiers: modifiers.rawValue, time: time))
    }

    /// `point` is in the panel's window coordinates.
    private func report(_ phase: FlightPress.Phase, at point: NSPoint, modifiers: NSEvent.ModifierFlags, time: TimeInterval) {
        var picture = pressedFlight.flatMap { fraction(of: point, on: $0) }
        // A press on the ring's outer half, past the picture's edge, lands on the edge.
        if case .pressed = phase, let place = picture {
            picture = CGPoint(x: min(max(place.x, 0), 1), y: min(max(place.y, 0), 1))
        }
        onPress?(pressedFlight, FlightPress.Event(phase: phase, picture: picture, screen: panel.convertPoint(toScreen: point),
                                                  modifiers: modifiers.rawValue, time: time))
    }

    /// Ends a press whose release never comes, by the button's own state. In driven presses on
    /// cards flying home the release reached no window at all 4 times in 29 (2026-09-23), which
    /// would leave the editor mid-stroke and this panel up. The button has to read up on two ticks
    /// running, so a release still queued behind the first tick is not overtaken.
    private func watchRelease() {
        releaseWatch?.invalidate()
        var upTicks = 0
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                upTicks = NSEvent.pressedMouseButtons & 1 == 0 ? upTicks + 1 : 0
                guard upTicks >= 2 else { return }
                Log.write("[flight] release missed")
                self.released(at: self.panel.convertPoint(fromScreen: NSEvent.mouseLocation), modifiers: NSEvent.modifierFlags,
                              time: ProcessInfo.processInfo.systemUptime)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseWatch = timer
    }

    /// The topmost flight whose picture is under `point`, in the panel's window coordinates.
    private func flight(at point: NSPoint) -> UUID? {
        let spots = Self.spots(in: hosting)
        for flight in model.flights.reversed() {
            guard let spot = spots.first(where: { $0.id == flight.id }) else { continue }
            // The card's ring strokes half its width outside the picture.
            if spot.bounds.insetBy(dx: -1, dy: -1).contains(spot.convert(point, from: nil)) { return flight.id }
        }
        return nil
    }

    /// Where `point` (window coordinates) is on flight `id`'s picture, as a fraction of it from its
    /// top-left corner, or nil once the flight has gone.
    private func fraction(of point: NSPoint, on id: UUID) -> CGPoint? {
        guard let spot = Self.spots(in: hosting).first(where: { $0.id == id }) else { return nil }
        return FlightSpotView.fraction(of: spot.convert(point, from: nil), in: spot.bounds.size, picture: spot.picture)
    }

    private static func spots(in view: NSView) -> [FlightSpotView] {
        view.subviews.flatMap { ($0 as? FlightSpotView).map { [$0] } ?? spots(in: $0) }
    }

    /// Moves `id` to `to`. A new flight starts at `from`; an existing one turns from where it is.
    ///
    /// `covered` runs when the flight first reaches the target: it has travelled the whole path by
    /// then, and from there to the end of the spring it is on the far side of the target, so it
    /// covers the target rect on every side and something put there without a shadow is hidden
    /// behind it. `arrived` runs when the spring has really settled on the target; whatever takes
    /// the flight's place draws at the exact target, so it has to appear then or it steps by what
    /// the spring still had to go.
    func fly(id: UUID, image: NSImage, marks: MarkLayers? = nil, from: NSRect, to: NSRect, lookFrom: Look, lookTo: Look,
             on screen: NSScreen, covered: @escaping () -> Void = {}, arrived: @escaping () -> Void = {},
             dropped: (() -> Void)? = nil) {
        let ui = Settings.shared.motionUI
        showPanel(on: screen)
        let gen = start(id: id, image: image, marks: marks, from: from, to: to, look: lookFrom, ui: ui, dropped: dropped)
        let travel = max(abs(to.minX - from.minX), abs(to.minY - from.minY),
                         abs(to.width - from.width), abs(to.height - from.height))
        let settleTime = Anim.settle(ui.expandDuration, bounce: Anim.flightBounce, distance: travel, within: Self.arrivalTolerance)
        let coverTime = min(settleTime, Anim.passesTarget(ui.expandDuration, bounce: Anim.flightBounce))
        // The starting state has to be committed before the animated change, or it starts at `to`.
        DispatchQueue.main.async { [weak self] in
            guard let self, let i = self.model.flights.firstIndex(where: { $0.id == id }), self.model.flights[i].generation == gen else { return }
            // A spring, so a flight retargeted mid-way (a swap) blends into the new path instead
            // of restarting; SwiftUI springs are additive by default.
            withAnimation(Anim.spring(ui.expandDuration, bounce: Anim.flightBounce)) {
                self.model.flights[i].frame = self.local(to)
                self.model.flights[i].look = lookTo
                self.model.flights[i].opacity = 1
                self.model.flights[i].blend = 1
            }
            // Scheduled before the arrival, so a duration of 0 runs the two in this order.
            DispatchQueue.main.asyncAfter(deadline: .now() + coverTime) { [weak self] in
                guard let self, self.isCurrent(id, gen) else { return }
                covered()
            }
            // The spring's tail runs on past its nominal duration. By here
            // it is inside `arrivalTolerance`, so putting it exactly on the target is a sub-pixel
            // move, and whatever takes its place lands on the same pixels.
            DispatchQueue.main.asyncAfter(deadline: .now() + settleTime) { [weak self] in
                guard let self, self.isCurrent(id, gen), let i = self.model.flights.firstIndex(where: { $0.id == id }) else { return }
                withTransaction(Transaction(animation: nil)) {
                    self.model.flights[i].frame = self.local(to)
                    self.model.flights[i].look = lookTo
                    self.model.flights[i].blend = 1
                }
                self.arrivedFlights.insert(id)
                self.model.flights[i].dropped = nil
                arrived()
                if self.pendingLift.remove(id) != nil { self.end(id: id) }
            }
        }
    }

    private func isCurrent(_ id: UUID, _ gen: Int) -> Bool {
        model.flights.first(where: { $0.id == id })?.generation == gen
    }

    /// Several card images fly into one frame and become `result`: the pieces converge, and the
    /// finished image fades in under them as they arrive and fade. `completion` runs once the
    /// result is the only thing drawn, so the caller can put the real card in that slot; the
    /// result's own flight lifts after that, unless something has aimed it elsewhere meanwhile.
    func converge(pieces: [(id: UUID, image: NSImage, marks: MarkLayers?, from: NSRect)],
                  result: (id: UUID, image: NSImage, frame: NSRect),
                  look: Look, on screen: NSScreen, completion: @escaping () -> Void) {
        let ui = Settings.shared.motionUI
        showPanel(on: screen)
        let fade = ui.expandDuration * 0.45
        // The finished image waits in the slot, under the pieces, until they are nearly there.
        remove { $0.id == result.id }
        arrivedFlights.remove(result.id)
        pendingLift.remove(result.id)
        let resting = Flight(id: result.id, image: result.image, frame: local(result.frame), look: look, opacity: 0)
        model.flights.append(resting)
        // Every piece answers exactly once: `arrived` when its spring settles, `dropped` when its
        // flight is ended before that (the stack dismissed mid-converge). The last answer finishes
        // the converge, so the result is uncovered when the pieces really are on it.
        var answered = 0
        let land: () -> Void = {
            answered += 1
            guard answered == pieces.count else { return }
            // A turn later: a dropped flight answers from inside `end`, which the dismissal that is
            // taking the stack down is part way through, and `completion` reaches back into it.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for piece in pieces { self.end(id: piece.id) }
                // The card behind it draws the shadow from here on. Not when the flight has been aimed
                // somewhere else since (a new capture flying the stitched card into the annotator):
                // that one is still in the air and needs its own shadow.
                if let i = self.model.flights.firstIndex(where: { $0.id == result.id }),
                   self.model.flights[i].generation == resting.generation { self.dropShadow(id: result.id) }
                completion()
                // The card view draws on SwiftUI's next commit; lift the finished image after it.
                DispatchQueue.main.async {
                    guard let i = self.model.flights.firstIndex(where: { $0.id == result.id }),
                          self.model.flights[i].generation == resting.generation else { return }
                    self.end(id: result.id)
                }
            }
        }
        for piece in pieces {
            fly(id: piece.id, image: piece.image, marks: piece.marks, from: piece.from, to: result.frame,
                lookFrom: look, lookTo: look, on: screen, arrived: land, dropped: land)
        }
        let flying = Set(pieces.map(\.id))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(Anim.spring(fade).delay(max(0, ui.expandDuration - fade))) {
                for i in self.model.flights.indices {
                    if self.model.flights[i].id == result.id { self.model.flights[i].opacity = 1 }
                    else if flying.contains(self.model.flights[i].id) { self.model.flights[i].opacity = 0 }
                }
            }
        }
    }

    /// Adds the flight, or aims an existing one down a new path, and returns its generation.
    /// The curve is fixed when the path is, so a flight keeps the motion scale it started with.
    /// Aiming again keeps the old path and resets `blend`, which `fly` then animates back to 1.
    private func start(id: UUID, image: NSImage, marks: MarkLayers?, from: NSRect, to: NSRect, look: Look, ui: UITweaks,
                       dropped: (() -> Void)? = nil) -> Int {
        let path = Path(from: center(local(from)), to: center(local(to)), curve: FlightCurve(ui: ui))
        // It is going somewhere else now, so it has not arrived and any lift waits for the new end.
        arrivedFlights.remove(id)
        pendingLift.remove(id)
        // Never repeats, so a timer left over from a flight that has been removed cannot match the
        // one that takes the same id next and snap it to the old target.
        nextGeneration += 1
        let gen = nextGeneration
        if let i = model.flights.firstIndex(where: { $0.id == id }) {
            model.flights[i].generation = gen
            model.flights[i].image = image
            if let old = model.flights[i].marks, old !== marks { old.clear() }
            model.flights[i].marks = marks
            model.flights[i].previousPath = model.flights[i].path
            model.flights[i].path = path
            model.flights[i].blend = 0
            model.flights[i].dropped = dropped
            return gen
        }
        model.flights.append(Flight(id: id, image: image, marks: marks, frame: local(from), look: look,
                                    path: path, previousPath: path, generation: gen, dropped: dropped))
        return gen
    }

    /// The marks the flight `id` shows, while it is in the air.
    func marks(of id: UUID) -> MarkLayers? {
        model.flights.first { $0.id == id }?.marks
    }

    /// Every flight's marks shown again in a new text style and arrowhead.
    func restyle(_ style: TextStyle, arrowhead: ArrowheadStyle) {
        for flight in model.flights { flight.marks?.restyle(style, arrowhead: arrowhead) }
    }

    func setImage(id: UUID, _ image: NSImage) {
        guard let i = model.flights.firstIndex(where: { $0.id == id }) else { return }
        model.flights[i].image = image
    }

    /// The thing the flight stands in for is on screen now and draws the shadow itself. Called in
    /// the same run loop turn as that card or window appearing, so the shadow is never drawn twice
    /// (which darkens the edge for as long as the flight image stays) and never missing.
    func dropShadow(id: UUID) {
        guard let i = model.flights.firstIndex(where: { $0.id == id }) else { return }
        model.flights[i].look.shadowOpacity = 0
    }

    /// Removes the flight once it has finished arriving, so what takes its place is at the same
    /// frame. Until then the flight covers it, and both show the same picture.
    func lift(id: UUID) {
        guard model.flights.contains(where: { $0.id == id }) else { return }
        if arrivedFlights.contains(id) { end(id: id) } else { pendingLift.insert(id) }
    }

    /// Removes the flight. Call once whatever it was flying toward is drawn.
    func end(id: UUID) {
        let dropped = model.flights.first { $0.id == id && !arrivedFlights.contains($0.id) }?.dropped
        remove { $0.id == id }
        arrivedFlights.remove(id)
        pendingLift.remove(id)
        orderOutIfIdle()
        dropped?()
    }

    /// Takes every flight and every swallow rect down.
    func endAll() {
        let dropped = model.flights.filter { !arrivedFlights.contains($0.id) }.compactMap(\.dropped)
        remove { _ in true }
        model.swallowRects = []
        arrivedFlights = []
        pendingLift = []
        orderOutIfIdle()
        for handler in dropped { handler() }
    }

    /// Takes flights off the layer, and lets their marks go with every text still being drawn for them.
    private func remove(where leaves: (Flight) -> Bool) {
        for flight in model.flights where leaves(flight) { flight.marks?.clear() }
        model.flights.removeAll(where: leaves)
    }

    /// Swallows every press on `rect` (on screen) for `seconds`, drag and release included. Drawn
    /// with the column's hair of alpha, which is what makes the window server give this panel the
    /// presses there, above the stack.
    func swallowPresses(in rect: NSRect, for seconds: TimeInterval, on screen: NSScreen) {
        showPanel(on: screen)
        let swallow = SwallowRect(rect: rect, frame: local(rect))
        model.swallowRects.append(swallow)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            self.model.swallowRects.removeAll { $0.id == swallow.id }
            self.orderOutIfIdle()
        }
    }

    /// Down once nothing is drawn on it and no press on it is down: the window server sends a
    /// press's drag and release to the window that took the press.
    private func orderOutIfIdle() {
        if model.flights.isEmpty, model.swallowRects.isEmpty, !pressDown { panel.orderOut(nil) }
    }

    private func showPanel(on screen: NSScreen) {
        self.screen = screen
        // An empty layer is still up while a press on it is down, and a stack presented meanwhile
        // is ordered above it; the first flight or swallow rect on it puts it back on top.
        if !panel.isVisible || panel.frame != screen.frame || model.flights.isEmpty {
            panel.setFrame(screen.frame, display: false)
            panel.orderFrontRegardless()
        }
    }

    private func local(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
}

private struct FlightsView: View {
    @ObservedObject var model: TransitionLayer.Model
    var body: some View {
        let ui = Settings.shared.data.ui
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.swallowRects) { swallow in
                Color.black.opacity(0.01)
                    .frame(width: swallow.frame.width, height: swallow.frame.height)
                    .position(x: swallow.frame.midX, y: swallow.frame.midY)
            }
            ForEach(model.flights) { f in
                Image(nsImage: f.image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: f.frame.width, height: f.frame.height)
                    .background(Color(nsColor: Config.matte))
                    .clipShape(RoundedRectangle(cornerRadius: f.look.corner, style: .continuous))
                    // The shadow of whichever end the flight is nearest, so nothing pops when the
                    // card or the annotator window takes over. Cast by the clipped image, before
                    // the ring: a card casts its shadow from the same shape, and the two have to
                    // match at the ends or the shadow steps when one takes the other's place.
                    .shadow(color: .black.opacity(f.look.shadowOpacity), radius: f.look.shadowRadius, y: f.look.shadowY)
                    .marks(f.marks, picture: f.image.size, corner: f.look.corner)
                    // The card's ring travels with the image, and the annotator window carries it on.
                    .overlay(RoundedRectangle(cornerRadius: f.look.corner, style: .continuous).stroke(.white.opacity(ui.cardBorderOpacity), lineWidth: ui.cardBorderWidth))
                    // Before the bow, so the spot is where the picture is on screen, swell and all.
                    .overlay(FlightSpot(id: f.id, picture: f.image.size))
                    .modifier(Bow(center: CGPoint(x: f.frame.midX, y: f.frame.midY), path: f.path, previous: f.previousPath, blend: f.blend))
                    .opacity(f.opacity)
                    .position(x: f.frame.midX, y: f.frame.midY)
            }
        }
        .ignoresSafeArea()
    }
}

/// Bows the straight path the flight's frame is taking, and swells the card around its middle.
/// Its animatable data is that frame's centre and the blend between the flight's paths, so both
/// the position along the path and a change of path move with the frame's own animation: a flight
/// aimed somewhere else in mid-air bends across to the new bow instead of stepping sideways.
private struct Bow: GeometryEffect {
    var center: CGPoint
    var path: TransitionLayer.Path
    var previous: TransitionLayer.Path
    var blend: CGFloat

    var animatableData: AnimatablePair<CGPoint.AnimatableData, CGFloat> {
        get { AnimatablePair(CGPoint.AnimatableData(center.x, center.y), blend) }
        set {
            center = CGPoint(x: newValue.first.first, y: newValue.first.second)
            blend = newValue.second
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let placed = FlightCurve.blend(previous.curve.placement(at: center, from: previous.from, to: previous.to),
                                       path.curve.placement(at: center, from: path.from, to: path.to),
                                       blend)
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        return ProjectionTransform(CGAffineTransform.identity
            .translatedBy(x: placed.offset.width, y: placed.offset.height)
            .translatedBy(x: mid.x, y: mid.y)
            .scaledBy(x: placed.scale, y: placed.scale)
            .translatedBy(x: -mid.x, y: -mid.y))
    }
}

/// The panel's content. The window server gives the panel only the presses on a flight's pixels,
/// so it takes every press it gets, with the drag and the release that follow, and none reaches
/// the flights' SwiftUI views.
private final class PressCatcher: NSView {
    var onEvent: ((NSEvent) -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onEvent?(event) }
    override func mouseDragged(with event: NSEvent) { onEvent?(event) }
    override func mouseUp(with event: NSEvent) { onEvent?(event) }
}

/// Marks where a flight's picture is. SwiftUI lays this view out with the flight, the bow's offset
/// and swell included, so AppKit's own conversion finds a press's place on the picture.
private struct FlightSpot: NSViewRepresentable {
    let id: UUID
    let picture: CGSize

    func makeNSView(context: Context) -> FlightSpotView { FlightSpotView(id: id, picture: picture) }
    func updateNSView(_ view: FlightSpotView, context: Context) {
        view.picture = picture
    }
}

final class FlightSpotView: NSView {
    let id: UUID
    /// The picture's shape: the flight fills its frame with it, cropping any excess.
    var picture: CGSize

    init(id: UUID, picture: CGSize) {
        self.id = id
        self.picture = picture
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    /// `point` from the top-left of a frame of `size` that a picture of shape `picture` fills,
    /// cropping any excess, as a fraction of the picture from its top-left corner.
    nonisolated static func fraction(of point: CGPoint, in size: CGSize, picture: CGSize) -> CGPoint? {
        guard picture.width > 0, picture.height > 0, size.width > 0, size.height > 0 else { return nil }
        let scale = max(size.width / picture.width, size.height / picture.height)
        let filled = CGSize(width: picture.width * scale, height: picture.height * scale)
        return CGPoint(x: (point.x - (size.width - filled.width) / 2) / filled.width,
                       y: (point.y - (size.height - filled.height) / 2) / filled.height)
    }
}
