import AppKit

/// Where the stack is laid out on its screen, and the room a Dock under the column keeps. Read
/// when the panel is laid out, so the panel, the cards and the strip are placed from one reading
/// of the screen and the Dock.
@MainActor
final class StackAreaReader {
    private(set) var area = StackArea(bounds: .zero)
    /// The tiles from the last read that answered. A read fails while the Dock is restarting — a
    /// crash, some display changes, login before it is up — and for that moment the process is
    /// there but its Accessibility tree is not. Taking a failed read as "the Dock spans the whole
    /// edge" lifts the whole column by the Dock's reserved height, and the area is only read on a
    /// layout pass, so it would stay lifted until something unrelated laid the panel out again. The
    /// last rect is the better guess: a restart puts the same Dock back.
    private var dockTiles: NSRect?
    private var dockRetry: DispatchWorkItem?
    private var dockReadsLeft = StackAreaReader.dockReadAttempts
    /// How often, and how many times, a failed Dock read is tried again. In code: a cadence for a
    /// system read that has failed, not a number a user would tune. Eight at half a second covers a
    /// `killall Dock`, which is back inside two.
    private static let dockReadDelay: TimeInterval = 0.5
    private static let dockReadAttempts = 8

    /// Whether the stack is on screen, so a read that answers late is worth a layout.
    private let isVisible: () -> Bool
    private let relayout: () -> Void

    init(isVisible: @escaping () -> Bool, relayout: @escaping () -> Void) {
        self.isVisible = isVisible
        self.relayout = relayout
    }

    func read(on screen: NSScreen, layout: StackLayout) {
        if let tiles = Dock.tiles() {
            dockTiles = tiles
            dockRetry?.cancel()
            dockRetry = nil
        } else {
            scheduleDockRead()
        }
        area = layout.area(visibleFrame: screen.visibleFrame, screenFrame: screen.frame, dock: dockTiles)
    }

    /// A presentation asks the Dock afresh: one that did not answer last time may answer now.
    func presented() {
        dockReadsLeft = Self.dockReadAttempts
    }

    /// Asks again after a failed read, and lays out once the Dock answers, so a stack opened while
    /// the Dock was restarting is not left in the place that reading gave it. Bounded: an app
    /// untrusted for Accessibility never gets an answer, and its layout — the Dock taken to span the
    /// whole edge — is the right one to settle on.
    private func scheduleDockRead() {
        guard dockRetry == nil, dockReadsLeft > 0 else { return }
        dockReadsLeft -= 1
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.dockRetry = nil
            guard self.isVisible() else { return }
            if Dock.tiles() != nil { self.relayout() } else { self.scheduleDockRead() }
        }
        dockRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dockReadDelay, execute: work)
    }
}
