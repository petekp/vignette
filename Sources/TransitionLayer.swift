import AppKit
import SwiftUI

/// A full-screen, mouse-transparent layer that flies card images between the stack and the
/// annotator. Flights are SwiftUI state, so a flight that is retargeted mid-way turns smoothly
/// instead of restarting.
@MainActor
final class TransitionLayer {
    struct Flight: Identifiable {
        let id: UUID
        var image: NSImage
        var frame: CGRect      // top-left origin, in the layer's own coordinates
        var corner: CGFloat
        var opacity: Double = 1
        /// The ends of the straight path this flight is on, which `curve` bows and swells.
        var pathFrom: CGPoint = .zero
        var pathTo: CGPoint = .zero
        var curve = FlightCurve.straight
        var generation = 0
    }

    final class Model: ObservableObject {
        @Published var flights: [Flight] = []
    }

    private let panel: NSPanel
    private let model = Model()
    private var screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]

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

    var isFlying: Bool { !model.flights.isEmpty }

    /// Moves `id` to `to`. A new flight starts at `from`; an existing one turns from where it is.
    func fly(id: UUID, image: NSImage, from: NSRect, to: NSRect, cornerFrom: CGFloat, cornerTo: CGFloat, on screen: NSScreen, completion: @escaping () -> Void) {
        let ui = Settings.shared.motionUI
        showPanel(on: screen)
        let gen = start(id: id, image: image, from: from, to: to, corner: cornerFrom, ui: ui)
        // The starting state has to be committed before the animated change, or it starts at `to`.
        DispatchQueue.main.async { [weak self] in
            guard let self, let i = self.model.flights.firstIndex(where: { $0.id == id }), self.model.flights[i].generation == gen else { return }
            // A spring, so a flight retargeted mid-way (a swap) blends into the new path instead
            // of restarting; SwiftUI springs are additive by default.
            withAnimation(Anim.spring(ui.expandDuration, bounce: 0.15)) {
                self.model.flights[i].frame = self.local(to)
                self.model.flights[i].corner = cornerTo
                self.model.flights[i].opacity = 1
            }
            // The spring settles a little after its nominal duration; wait for that before the
            // annotator window replaces the image, or the last of the motion shows as a snap.
            DispatchQueue.main.asyncAfter(deadline: .now() + ui.expandDuration * 1.15) { [weak self] in
                guard let self, let i = self.model.flights.firstIndex(where: { $0.id == id }), self.model.flights[i].generation == gen else { return }
                completion()
            }
        }
    }

    /// Several card images fly into one frame and become `result`: the pieces converge, and the
    /// finished image fades in under them as they arrive and fade. `completion` runs once the
    /// result is the only thing drawn, so the caller can put the real card in that slot; the
    /// result's own flight lifts after that, unless something has aimed it elsewhere meanwhile.
    func converge(pieces: [(id: UUID, image: NSImage, from: NSRect)],
                  result: (id: UUID, image: NSImage, frame: NSRect),
                  corner: CGFloat, on screen: NSScreen, completion: @escaping () -> Void) {
        let ui = Settings.shared.motionUI
        showPanel(on: screen)
        let fade = ui.expandDuration * 0.45
        // The finished image waits in the slot, under the pieces, until they are nearly there.
        model.flights.removeAll { $0.id == result.id }
        let resting = Flight(id: result.id, image: result.image, frame: local(result.frame), corner: corner, opacity: 0)
        model.flights.append(resting)
        for piece in pieces {
            fly(id: piece.id, image: piece.image, from: piece.from, to: result.frame,
                cornerFrom: corner, cornerTo: corner, on: screen) {}
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
    private func start(id: UUID, image: NSImage, from: NSRect, to: NSRect, corner: CGFloat, ui: UITweaks) -> Int {
        let path = (from: center(local(from)), to: center(local(to)))
        let curve = FlightCurve(ui: ui)
        if let i = model.flights.firstIndex(where: { $0.id == id }) {
            model.flights[i].generation += 1
            model.flights[i].image = image
            model.flights[i].pathFrom = path.from
            model.flights[i].pathTo = path.to
            model.flights[i].curve = curve
            return model.flights[i].generation
        }
        model.flights.append(Flight(id: id, image: image, frame: local(from), corner: corner,
                                    pathFrom: path.from, pathTo: path.to, curve: curve))
        return 0
    }

    func setImage(id: UUID, _ image: NSImage) {
        guard let i = model.flights.firstIndex(where: { $0.id == id }) else { return }
        model.flights[i].image = image
    }

    /// Removes the flight. Call once whatever it was flying toward is drawn.
    func end(id: UUID) {
        model.flights.removeAll { $0.id == id }
        if model.flights.isEmpty { panel.orderOut(nil) }
    }

    func endAll() {
        model.flights = []
        panel.orderOut(nil)
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
                    .clipShape(RoundedRectangle(cornerRadius: f.corner, style: .continuous))
                    // The card's ring travels with the image, and the annotator window carries it on.
                    .overlay(RoundedRectangle(cornerRadius: f.corner, style: .continuous).stroke(.white.opacity(ui.cardBorderOpacity), lineWidth: ui.cardBorderWidth))
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                    .modifier(Bow(center: CGPoint(x: f.frame.midX, y: f.frame.midY), from: f.pathFrom, to: f.pathTo, curve: f.curve))
                    .opacity(f.opacity)
                    .position(x: f.frame.midX, y: f.frame.midY)
            }
        }
        .ignoresSafeArea()
    }
}

/// Bows the straight path the flight's frame is taking, and swells the card around its middle.
/// Its animatable data is that frame's centre, so it moves in step with the frame's own animation
/// and blends the same way when a flight is retargeted in mid-air.
private struct Bow: GeometryEffect {
    var center: CGPoint
    var from: CGPoint
    var to: CGPoint
    var curve: FlightCurve

    var animatableData: CGPoint.AnimatableData {
        get { CGPoint.AnimatableData(center.x, center.y) }
        set { center = CGPoint(x: newValue.first, y: newValue.second) }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let placed = curve.placement(at: center, from: from, to: to)
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        return ProjectionTransform(CGAffineTransform.identity
            .translatedBy(x: placed.offset.width, y: placed.offset.height)
            .translatedBy(x: mid.x, y: mid.y)
            .scaledBy(x: placed.scale, y: placed.scale)
            .translatedBy(x: -mid.x, y: -mid.y))
    }
}
