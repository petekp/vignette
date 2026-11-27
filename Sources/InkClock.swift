import AppKit
import Combine
import Metal
import QuartzCore

/// A layer the clock draws gel into: live ink's marks (`InkMarkLayer`) and a comment's pin, area and
/// rims in the editor (`PinGel`).
@MainActor
protocol GelLayer: AnyObject {
    /// In a layer tree on screen, with nothing over it hidden or faded out.
    var isVisible: Bool { get }
    /// Something changed since the last drawing: draw at the next tick, whatever the clock's rate.
    var needsGel: Bool { get }
    /// Whether it takes its colour from the screen behind it (`InkBackdrop`), as live ink does.
    var readsScreen: Bool { get }
    /// Whether its material keeps drifting rather than coming to rest (`InkRest`).
    var keepsDrifting: Bool { get }
    /// Whether it eases at `now`, and so must draw every frame.
    func isEasing(at now: CFTimeInterval) -> Bool
    /// Encodes a drawing at `now`, its material at `time`, for the clock to commit and present.
    func encode(at now: CFTimeInterval, time: CFTimeInterval) -> (commands: MTLCommandBuffer, drawable: CAMetalDrawable)?
    func settingsChanged()
    func backdropChanged()
}

/// The clock every gel layer draws from: one display link, running while a layer moves. The light
/// and the film drift on the material's own time, which runs at `inkGelMotion` times the motion
/// scale, so motion 0 holds them still, and slows to still once nothing stirs the ink (`InkRest`).
/// Drifting ink redraws at about 30 frames a second; ink easing onto its shape, every frame.
@MainActor
final class InkClock: NSObject {
    static let shared = InkClock()

    private var layers: [ObjectIdentifier: Weak] = [:]
    private var link: ScreenLink?
    private var last = CACurrentMediaTime()
    private var lastIdle: CFTimeInterval = 0
    private var rest = InkRest(stirredAt: CACurrentMediaTime())
    /// The material's time, in seconds of drift.
    private(set) var time: CFTimeInterval = 0
    private var settingsChanged: AnyCancellable?

    private struct Weak { weak var layer: GelLayer? }

    private override init() {
        super.init()
        // A tweak redraws every gel, and at motion 0 nothing else would.
        settingsChanged = Settings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layers.values.forEach { $0.layer?.settingsChanged() } }
        }
    }

    func add(_ layer: GelLayer) {
        layers[ObjectIdentifier(layer)] = Weak(layer: layer)
        if layer.readsScreen { InkBackdrop.shared.keepFresh() }
        watchPointer()
        stir()
    }

    private func stir() {
        rest.stir(at: CACurrentMediaTime())
        wake()
    }

    /// The gel is lit from the pointer, so a move draws it again, whatever the motion setting: the
    /// light follows the hand rather than animating. The link rests while nothing moves, so the
    /// pointer's moves wake it, in Vignette's windows and over every other app's.
    private var pointerWatch: [Any] = []
    private var lastPointer = CGPoint(x: -1, y: -1)

    private func watchPointer() {
        guard pointerWatch.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.stir() }
        }) { pointerWatch.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.stir() }
            return event
        }) { pointerWatch.append(local) }
    }

    private func stopWatchingPointer() {
        pointerWatch.forEach(NSEvent.removeMonitor)
        pointerWatch = []
    }

    /// Whether any live ink is on the screen.
    var showsInk: Bool { layers.values.contains { $0.layer.map { $0.readsScreen && $0.isVisible } ?? false } }

    func remove(_ layer: GelLayer) {
        layers[ObjectIdentifier(layer)] = nil
    }

    /// The backdrop was read again: every gel chooses its colour again.
    func backdropChanged() {
        layers.values.forEach { $0.layer?.backdropChanged() }
        wake()
    }

    /// What moves ink on the clock's own refresh, by owner: run at the start of each tick, with the
    /// time that refresh shows, before any gel is drawn. A hand that drew from a display link of its
    /// own presented drawings that often did not reach the screen (measured 2026-10-25).
    private var tickers: [ObjectIdentifier: (CFTimeInterval) -> Void] = [:]

    /// Runs `tick` at the start of each refresh for `owner`, or stops with nil. The clock does not rest
    /// while anything is ticking.
    func onTick(_ owner: AnyObject, _ tick: ((CFTimeInterval) -> Void)?) {
        tickers[ObjectIdentifier(owner)] = tick
        if tick != nil { wake() }
    }

    /// Ticks again, after being paused for want of anything moving.
    func wake() {
        if link == nil, !NSScreen.screens.isEmpty { link = ScreenLink(self, #selector(tick(_:))) }
        link?.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        tickers.values.forEach { $0(link.targetTimestamp) }
        let now = CACurrentMediaTime()
        let ui = Settings.shared.data.ui
        layers = layers.filter { $0.value.layer != nil }
        let shown = layers.values.compactMap(\.layer).filter(\.isVisible)
        if shown.contains(where: \.keepsDrifting) { rest.stir(at: now) }
        let rate = Settings.shared.motionScale * ui.inkGelMotion * rest.drift(at: now)
        time += min(now - last, 0.1) * rate
        last = now
        let idle = rate > 0 && now - lastIdle >= 1.0 / 30
        if idle { lastIdle = now }
        let pointer = LiveInkTap.pointer
        let pointerMoved = ui.inkGelPointerLight > 0 && pointer != lastPointer
        lastPointer = pointer
        var drawn: [(commands: MTLCommandBuffer, drawable: CAMetalDrawable)] = []
        var moving = pointerMoved
        for layer in shown {
            let easing = moving || layer.isEasing(at: now)
            moving = moving || easing
            guard easing || idle || layer.needsGel else { continue }
            if let frame = layer.encode(at: now, time: time) { drawn.append(frame) }
        }
        drawn.forEach { $0.commands.commit() }
        // A layer that presents with its transaction shows a drawable only once it is scheduled.
        drawn.forEach { $0.commands.waitUntilScheduled(); $0.drawable.present() }
        // Nothing drifts at motion 0, so the link rests until a layer changes. With no layer showing,
        // it rests and looks again twice a second, since a holder fading back in says nothing here.
        if layers.isEmpty { stopWatchingPointer() }
        if !tickers.isEmpty {
            return
        } else if layers.isEmpty || (!moving && rate <= 0 && !shown.contains(where: \.needsGel)) {
            self.link?.isPaused = true
        } else if shown.isEmpty {
            self.link?.isPaused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if self?.layers.isEmpty == false { self?.wake() }
            }
        }
    }
}
