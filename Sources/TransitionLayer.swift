import AppKit
import SwiftUI

/// A full-screen, mouse-transparent layer that flies card images between the stack and the
/// annotator. Flights are SwiftUI state, so a flight that is retargeted mid-way turns smoothly
/// instead of restarting.
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

    final class Model: ObservableObject {
        @Published var flights: [Flight] = []
    }

    private let panel: NSPanel
    private let model = Model()
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
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.contentView = NSHostingView(rootView: FlightsView(model: model))
    }

    /// Moves `id` to `to`. A new flight starts at `from`; an existing one turns from where it is.
    ///
    /// `covered` runs when the flight first reaches the target: it has travelled the whole path by
    /// then, and from there to the end of the spring it is on the far side of the target, so it
    /// covers the target rect on every side and something put there without a shadow is hidden
    /// behind it. `arrived` runs when the spring has really settled on the target; whatever takes
    /// the flight's place draws at the exact target, so it has to appear then or it steps by what
    /// the spring still had to go.
    func fly(id: UUID, image: NSImage, from: NSRect, to: NSRect, lookFrom: Look, lookTo: Look,
             on screen: NSScreen, covered: @escaping () -> Void = {}, arrived: @escaping () -> Void = {},
             dropped: (() -> Void)? = nil) {
        let ui = Settings.shared.motionUI
        showPanel(on: screen)
        let gen = start(id: id, image: image, from: from, to: to, look: lookFrom, ui: ui, dropped: dropped)
        let travel = max(abs(to.minX - from.minX), abs(to.minY - from.minY),
                         abs(to.width - from.width), abs(to.height - from.height))
        let settleTime = Anim.settle(ui.expandDuration, bounce: 0.15, distance: travel, within: Self.arrivalTolerance)
        let coverTime = min(settleTime, Anim.passesTarget(ui.expandDuration, bounce: 0.15))
        // The starting state has to be committed before the animated change, or it starts at `to`.
        DispatchQueue.main.async { [weak self] in
            guard let self, let i = self.model.flights.firstIndex(where: { $0.id == id }), self.model.flights[i].generation == gen else { return }
            // A spring, so a flight retargeted mid-way (a swap) blends into the new path instead
            // of restarting; SwiftUI springs are additive by default.
            withAnimation(Anim.spring(ui.expandDuration, bounce: 0.15)) {
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
    func converge(pieces: [(id: UUID, image: NSImage, from: NSRect)],
                  result: (id: UUID, image: NSImage, frame: NSRect),
                  look: Look, on screen: NSScreen, completion: @escaping () -> Void) {
        let ui = Settings.shared.motionUI
        showPanel(on: screen)
        let fade = ui.expandDuration * 0.45
        // The finished image waits in the slot, under the pieces, until they are nearly there.
        model.flights.removeAll { $0.id == result.id }
        arrivedFlights.remove(result.id)
        pendingLift.remove(result.id)
        let resting = Flight(id: result.id, image: result.image, frame: local(result.frame), look: look, opacity: 0)
        model.flights.append(resting)
        for piece in pieces {
            fly(id: piece.id, image: piece.image, from: piece.from, to: result.frame,
                lookFrom: look, lookTo: look, on: screen)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + ui.expandDuration * 1.15) { [weak self] in
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

    /// Adds the flight, or aims an existing one down a new path, and returns its generation.
    /// The curve is fixed when the path is, so a flight keeps the motion scale it started with.
    /// Aiming again keeps the old path and resets `blend`, which `fly` then animates back to 1.
    private func start(id: UUID, image: NSImage, from: NSRect, to: NSRect, look: Look, ui: UITweaks,
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
            model.flights[i].previousPath = model.flights[i].path
            model.flights[i].path = path
            model.flights[i].blend = 0
            model.flights[i].dropped = dropped
            return gen
        }
        model.flights.append(Flight(id: id, image: image, frame: local(from), look: look,
                                    path: path, previousPath: path, generation: gen, dropped: dropped))
        return gen
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
        model.flights.removeAll { $0.id == id }
        arrivedFlights.remove(id)
        pendingLift.remove(id)
        if model.flights.isEmpty { panel.orderOut(nil) }
        dropped?()
    }

    func endAll() {
        let dropped = model.flights.filter { !arrivedFlights.contains($0.id) }.compactMap(\.dropped)
        model.flights = []
        arrivedFlights = []
        pendingLift = []
        panel.orderOut(nil)
        for handler in dropped { handler() }
    }

    private func showPanel(on screen: NSScreen) {
        self.screen = screen
        if !panel.isVisible || panel.frame != screen.frame {
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
            ForEach(model.flights) { f in
                Image(nsImage: f.image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: f.frame.width, height: f.frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: f.look.corner, style: .continuous))
                    // The shadow of whichever end the flight is nearest, so nothing pops when the
                    // card or the annotator window takes over. Cast by the clipped image, before
                    // the ring: a card casts its shadow from the same shape, and the two have to
                    // match at the ends or the shadow steps when one takes the other's place.
                    .shadow(color: .black.opacity(f.look.shadowOpacity), radius: f.look.shadowRadius, y: f.look.shadowY)
                    // The card's ring travels with the image, and the annotator window carries it on.
                    .overlay(RoundedRectangle(cornerRadius: f.look.corner, style: .continuous).stroke(.white.opacity(ui.cardBorderOpacity), lineWidth: ui.cardBorderWidth))
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
