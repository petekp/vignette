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
        let ui = Settings.shared.data.ui
        self.screen = screen
        if !panel.isVisible || panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: false)
            panel.orderFrontRegardless()
        }
        let gen: Int
        if let i = model.flights.firstIndex(where: { $0.id == id }) {
            gen = model.flights[i].generation + 1
            model.flights[i].generation = gen
            model.flights[i].image = image
        } else {
            gen = 0
            model.flights.append(Flight(id: id, image: image, frame: local(from), corner: cornerFrom))
        }
        // The starting state has to be committed before the animated change, or it starts at `to`.
        DispatchQueue.main.async { [weak self] in
            guard let self, let i = self.model.flights.firstIndex(where: { $0.id == id }), self.model.flights[i].generation == gen else { return }
            withAnimation(Anim.swiftUI("easeInOut", duration: ui.expandDuration)) {
                self.model.flights[i].frame = self.local(to)
                self.model.flights[i].corner = cornerTo
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + ui.expandDuration) { [weak self] in
                guard let self, let i = self.model.flights.firstIndex(where: { $0.id == id }), self.model.flights[i].generation == gen else { return }
                completion()
            }
        }
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

    private func local(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

private struct FlightsView: View {
    @ObservedObject var model: TransitionLayer.Model
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.flights) { f in
                Image(nsImage: f.image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: f.frame.width, height: f.frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: f.corner, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                    .position(x: f.frame.midX, y: f.frame.midY)
            }
        }
        .ignoresSafeArea()
    }
}
