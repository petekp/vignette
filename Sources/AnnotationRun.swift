import Foundation

/// The one owner of an annotation run: from an image opening in the annotator until the annotator
/// closes with nothing after it. A run of a list opens each file in turn. `reduce` takes one event
/// and returns the effects to run, in order; `ThumbnailController` sends the events and runs the
/// effects, and decides nothing about the queue or the run's end.
///
/// The flights are `AnnotatorTransition`'s, held privately here. The run ends or keeps the queue
/// before it hands an event on, so no caller has to empty the queue before a park that can answer
/// in the same turn. When the transition goes idle after a `returnCard`, the next queued file opens
/// in that same batch, so a handover reads as a swap does: `returnCard(A) next(B) prepare(B)`.
struct AnnotationRun: Equatable {
    enum Event: Equatable {
        case annotate([ScreenshotKey])      // a list: the first opens and the rest queue; replaces any queue
        case shown(Opening)          // the flight landed and the annotator became visible
        case parked(Opening)         // the editor finished parking
        case cancel                  // Esc, a click outside, Cmd+W: the run ends
        case sent                    // Send: this image closes without a Copied notice, and the run goes on
        case finish                  // Done or Return: the result is on the clipboard, and the run goes on
        case dismiss(byHand: Bool)   // the panel is going away, and the run with it
        case remove([ScreenshotKey])        // files trashed or deleted
        case newShot(ScreenshotKey)         // a new file arrived
        case renamed(from: ScreenshotKey, to: ScreenshotKey)   // a file was renamed: a queued file and the open one follow it
        case selectionChanged(added: [ScreenshotKey], removed: [ScreenshotKey])   // image files only, in the order picked
        case copyFailed(Opening)     // Done's copy failed before the card came home
        case loaded(Opening)         // the editor has the image at the screen's size
        case takesPresses(Opening)   // the window server gives the editor's window its presses
        case arrived(Opening)        // the flight into the editor settled on the frame
    }

    enum Effect: Equatable {
        case prepare(Opening)
        case show
        case park(Opening)
        case abandon(Opening)
        case returnCard(Opening, copied: Bool)
        case hideAnnotator
        case join(ScreenshotKey)
        case next(ScreenshotKey, place: Int, of: Int)     // the queue opens its next file
        case queued(ScreenshotKey, place: Int, of: Int)   // a selected card joined the queue
        case endRun(restoreFocus: Bool)            // nothing follows: the run is over
        case landed(Opening)                       // the window takes the shadow back from the flight
        case handOverPresses(Opening)              // presses held on the flight go to the editor
        case liftFlight(Opening)                   // the editor is ready and seen: the flight image goes

        /// The image a `prepare` opens.
        var prepares: Opening? {
            if case .prepare(let opening) = self { return opening }
            return nil
        }
    }

    /// What the flight into the editor waits for before it lifts: the editor's image, the window
    /// taking presses, and the flight's arrival. They come in any order, for the current opening.
    private struct Lift: Equatable {
        var loaded = false
        var takesPresses = false
        var arrived = false
        var lifted = false
    }

    private var transition = AnnotatorTransition()
    /// The id the last opening took. Never reset, so no two openings share one.
    private var minted = 0
    private var lift = Lift()
    /// The files still waiting, in the order they were given or picked. Empty whenever the run is idle.
    private(set) var queue: [ScreenshotKey] = []
    /// How many files the run has been given, and how many of them have opened, which is what the
    /// `[annotate] next` line counts: a file gone from the queue does not skip a number.
    private var total = 0
    private var opened = 0
    /// The file the queue opened last, so one that does not open gives its number back.
    private var fromQueue: ScreenshotKey?
    /// The opening whose Done failed to copy before its card came home, so the card takes no Copied notice.
    private var uncopied: Opening?
    /// The run ends by the person's hand, so the focus goes back to their app once the annotator is gone.
    private var restoreFocus = false

    var phase: AnnotatorTransition.Phase { transition.phase }
    /// The image in the annotator or on its way there, if any.
    var opening: Opening? { transition.opening }
    var key: ScreenshotKey? { transition.opening?.key }
    var isActive: Bool { transition.isActive }
    /// The editor's window takes presses now, so a press on its flight goes straight to it.
    var takesPresses: Bool { opening != nil && lift.takesPresses }

    /// `opens` is asked, before anything is returned, whether a file this event opens has a card.
    /// The controller makes the card there when the panel lacks it. A queued file may have gone or
    /// stopped reading since it was queued; one that does not open is passed over, before any
    /// effect runs, so the room and the flights are aimed at the image that really opens next.
    mutating func reduce(_ event: Event, opens: (ScreenshotKey) -> Bool) -> [Effect] {
        var effects = step(event)
        while let opening = effects.last(where: { $0.prepares != nil })?.prepares, !opens(opening.key) {
            effects.removeAll { effect in
                switch effect {
                case .prepare(opening), .next(opening.key, _, _): return true
                default: return false
                }
            }
            effects += cannotOpen(opening.key)
        }
        return effects
    }

    private mutating func step(_ event: Event) -> [Effect] {
        switch event {
        case .annotate(let keys):
            guard let first = keys.first else { return [] }
            queue = Array(keys.dropFirst())
            total = keys.count
            opened = 1
            fromQueue = nil
            return forward(.annotate(mint(first)))
        case .shown(let opening):
            return forward(.shown(opening))
        case .parked(let opening):
            return forward(.parked(opening))
        case .cancel:
            endsByHand()
            endQueue()
            return forward(.close)
        case .sent:
            endsByHand()
            return forward(.close)
        case .finish:
            endsByHand()
            return forward(.finish)
        case .dismiss(let byHand):
            if byHand { endsByHand() }
            endQueue()
            return forward(.dismiss)
        case .remove(let keys):
            queue.removeAll { keys.contains($0) }
            // The file in the annotator going ends the run: nothing takes its place.
            if let key, keys.contains(key) { endQueue() }
            return keys.flatMap { forward(.remove($0)) }
        case .newShot(let key):
            return forward(.newShot(key))
        case .renamed(let old, let new):
            queue = queue.map { $0 == old ? new : $0 }
            if fromQueue == old { fromQueue = new }
            uncopied = uncopied?.renamed(from: old, to: new)
            return forward(.renamed(from: old, to: new))
        case .selectionChanged(let added, let removed):
            return select(added: added, removed: removed)
        case .copyFailed(let opening):
            if case .parking(opening, then: .finish) = transition.phase { uncopied = opening }
            return []
        case .loaded(let opening):
            guard opening == self.opening else { return [] }
            lift.loaded = true
            return liftIfReady()
        case .takesPresses(let opening):
            guard let current = self.opening, opening == current else { return [] }
            lift.takesPresses = true
            return [.handOverPresses(current)] + liftIfReady()
        case .arrived(let opening):
            guard let current = self.opening, opening == current else { return [] }
            lift.arrived = true
            return [.landed(current)] + liftIfReady()
        }
    }

    private mutating func mint(_ key: ScreenshotKey) -> Opening {
        minted += 1
        return Opening(id: minted, key: key)
    }

    /// The flight into the editor lifts once, when the last of its three conditions comes in.
    private mutating func liftIfReady() -> [Effect] {
        guard let opening, lift.loaded, lift.takesPresses, lift.arrived, !lift.lifted else { return [] }
        lift.lifted = true
        return [.liftFlight(opening)]
    }

    /// `key` has no card, so its `prepare` never runs: the transition goes back to idle with nothing
    /// shown, and the queue opens its next file or the run ends.
    private mutating func cannotOpen(_ key: ScreenshotKey) -> [Effect] {
        transition = AnnotatorTransition()
        if fromQueue == key { opened -= 1 }
        fromQueue = nil
        return continueOrEnd()
    }

    /// Hands `event` to the transition and adds what the run decides when the transition goes idle.
    private mutating func forward(_ event: AnnotatorTransition.Event) -> [Effect] {
        let wasActive = transition.isActive
        var effects: [Effect] = []
        for effect in transition.reduce(event) {
            switch effect {
            case .prepare(let opening):
                uncopied = nil   // the image it was for has gone home
                lift = Lift()
                effects.append(.prepare(opening))
            case .show: effects.append(.show)
            case .park(let opening): effects.append(.park(opening))
            case .abandon(let opening): effects.append(.abandon(opening))
            case .returnCard(let opening, let copied):
                effects.append(.returnCard(opening, copied: copied && uncopied != opening))
                uncopied = nil
            case .hideAnnotator:
                endQueue()   // the panel or the file went, and the run with it
                effects.append(.hideAnnotator)
            case .join(let key): effects.append(.join(key))
            }
        }
        if wasActive, !transition.isActive { effects += continueOrEnd() }
        return effects
    }

    /// The transition is idle: the queue opens its next file, or the run is over.
    private mutating func continueOrEnd() -> [Effect] {
        guard let next = queue.first else {
            endQueue()
            fromQueue = nil
            let focus = restoreFocus
            restoreFocus = false
            return [.endRun(restoreFocus: focus)]
        }
        queue.removeFirst()
        opened += 1
        fromQueue = next
        return [.next(next, place: opened, of: total)] + forward(.annotate(mint(next)))
    }

    /// A person's hand is ending this run, so their app gets the focus back when it ends. Nothing
    /// is open to end otherwise, and the flag would outlive the run it was meant for.
    private mutating func endsByHand() {
        if transition.isActive { restoreFocus = true }
    }

    /// While an image is in the annotator, a card selected in the stack is queued next, in the
    /// order picked, and one deselected leaves the queue. The image in the annotator is not "next".
    private mutating func select(added: [ScreenshotKey], removed: [ScreenshotKey]) -> [Effect] {
        guard transition.isActive else { return [] }
        let before = queue.count
        queue.removeAll { removed.contains($0) }
        total -= before - queue.count
        var effects: [Effect] = []
        for key in added where key != self.key && !queue.contains(key) {
            queue.append(key)
            total += 1
            effects.append(.queued(key, place: opened + queue.count, of: total))
        }
        return effects
    }

    private mutating func endQueue() {
        queue = []
        total = 0
        opened = 0
    }
}

/// Holds an event that arrives while another is being handled and runs it right after, in order.
/// A park or a flight can answer inside the effects of the event that asked for it; held, its
/// answer never runs nested inside that event.
final class EventHold<Event> {
    private var held: [Event] = []
    private var handling = false

    func send(_ event: Event, to handle: (Event) -> Void) {
        held.append(event)
        guard !handling else { return }
        handling = true
        while !held.isEmpty { handle(held.removeFirst()) }
        handling = false
    }
}

// Short log forms: keys print as file names, so a `[transition]` line stays readable.
private func short(_ key: ScreenshotKey) -> String { key.name }

extension AnnotationRun: CustomStringConvertible {
    var description: String { queue.isEmpty ? "\(phase)" : "\(phase) queued=\(queue.count)" }
}

extension AnnotationRun.Event: CustomStringConvertible {
    var description: String {
        switch self {
        case .annotate(let keys): return "annotate(\(keys.map(short).joined(separator: ", ")))"
        case .shown(let o): return "shown(\(o))"
        case .parked(let o): return "parked(\(o))"
        case .cancel: return "cancel"
        case .sent: return "sent"
        case .finish: return "finish"
        case .dismiss(let byHand): return byHand ? "dismiss(byHand)" : "dismiss"
        case .remove(let keys): return "remove(\(keys.map(short).joined(separator: ", ")))"
        case .newShot(let key): return "newShot(\(short(key)))"
        case .renamed(let from, let to): return "renamed(\(short(from)) to \(short(to)))"
        case .selectionChanged(let added, let removed):
            return "selectionChanged(+\(added.map(short).joined(separator: ", ")) -\(removed.map(short).joined(separator: ", ")))"
        case .copyFailed(let o): return "copyFailed(\(o))"
        case .loaded(let o): return "loaded(\(o))"
        case .takesPresses(let o): return "takesPresses(\(o))"
        case .arrived(let o): return "arrived(\(o))"
        }
    }
}

extension AnnotationRun.Effect: CustomStringConvertible {
    var description: String {
        switch self {
        case .prepare(let o): return "prepare(\(o))"
        case .show: return "show"
        case .park(let o): return "park(\(o))"
        case .abandon(let o): return "abandon(\(o))"
        case .returnCard(let o, let copied): return "returnCard(\(o)\(copied ? " copied" : ""))"
        case .hideAnnotator: return "hideAnnotator"
        case .join(let k): return "join(\(short(k)))"
        case .next(let k, let place, let total): return "next(\(short(k)) \(place) of \(total))"
        case .queued(let k, let place, let total): return "queued(\(short(k)) \(place) of \(total))"
        case .endRun(let focus): return focus ? "endRun(restoreFocus)" : "endRun"
        case .landed(let o): return "landed(\(o))"
        case .handOverPresses(let o): return "handOverPresses(\(o))"
        case .liftFlight(let o): return "liftFlight(\(o))"
        }
    }
}
