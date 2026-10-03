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
        case annotate([String])      // a list: the first opens and the rest queue; replaces any queue
        case shown                   // the flight landed and the annotator became visible
        case parked                  // the editor finished parking
        case cancel                  // Esc, a click outside, Cmd+W: the run ends
        case sent                    // Send: this image closes without a Copied notice, and the run goes on
        case finish                  // Done or Return: the result is on the clipboard, and the run goes on
        case dismiss(byHand: Bool)   // the panel is going away, and the run with it
        case remove([String])        // files trashed or deleted
        case newShot(String)         // a new file arrived
        case selectionChanged(added: [String], removed: [String])   // image files only, in the order picked
        case copyFailed(String)      // Done's copy failed before the card came home
    }

    enum Effect: Equatable {
        case prepare(String)
        case show
        case park(String)
        case abandon(String)
        case returnCard(String, copied: Bool)
        case hideAnnotator
        case join(String)
        case next(String, place: Int, of: Int)     // the queue opens its next file
        case queued(String, place: Int, of: Int)   // a selected card joined the queue
        case endRun(restoreFocus: Bool)            // nothing follows: the run is over

        /// The file a `prepare` opens.
        var opening: String? {
            if case .prepare(let key) = self { return key }
            return nil
        }
    }

    private var transition = AnnotatorTransition()
    /// The files still waiting, in the order they were given or picked. Empty whenever the run is idle.
    private(set) var queue: [String] = []
    /// How many files the run has been given, and how many of them have opened, which is what the
    /// `[annotate] next` line counts: a file gone from the queue does not skip a number.
    private var total = 0
    private var opened = 0
    /// The file the queue opened last, so one that does not open gives its number back.
    private var fromQueue: String?
    /// The file whose Done failed to copy before its card came home, so the card takes no Copied notice.
    private var uncopied: String?
    /// The run ends by the person's hand, so the focus goes back to their app once the annotator is gone.
    private var restoreFocus = false

    var phase: AnnotatorTransition.Phase { transition.phase }
    /// The key in the annotator or on its way there, if any.
    var key: String? { transition.key }
    var isActive: Bool { transition.isActive }

    /// `opens` is asked, before anything is returned, whether a file this event opens has a card.
    /// The controller makes the card there when the panel lacks it. A queued file may have gone or
    /// stopped reading since it was queued; one that does not open is passed over, before any
    /// effect runs, so the room and the flights are aimed at the image that really opens next.
    mutating func reduce(_ event: Event, opens: (String) -> Bool) -> [Effect] {
        var effects = step(event)
        while let key = effects.last(where: { $0.opening != nil })?.opening, !opens(key) {
            effects.removeAll { effect in
                switch effect {
                case .prepare(key), .next(key, _, _): return true
                default: return false
                }
            }
            effects += cannotOpen(key)
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
            return forward(.annotate(first))
        case .shown:
            return forward(.shown)
        case .parked:
            return forward(.parked)
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
        case .selectionChanged(let added, let removed):
            return select(added: added, removed: removed)
        case .copyFailed(let key):
            if case .parking(key, then: .finish) = transition.phase { uncopied = key }
            return []
        }
    }

    /// `key` has no card, so its `prepare` never runs: the transition goes back to idle with nothing
    /// shown, and the queue opens its next file or the run ends.
    private mutating func cannotOpen(_ key: String) -> [Effect] {
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
            case .prepare(let key):
                uncopied = nil   // the image it was for has gone home
                effects.append(.prepare(key))
            case .show: effects.append(.show)
            case .park(let key): effects.append(.park(key))
            case .abandon(let key): effects.append(.abandon(key))
            case .returnCard(let key, let copied):
                effects.append(.returnCard(key, copied: copied && uncopied != key))
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
        return [.next(next, place: opened, of: total)] + forward(.annotate(next))
    }

    /// A person's hand is ending this run, so their app gets the focus back when it ends. Nothing
    /// is open to end otherwise, and the flag would outlive the run it was meant for.
    private mutating func endsByHand() {
        if transition.isActive { restoreFocus = true }
    }

    /// While an image is in the annotator, a card selected in the stack is queued next, in the
    /// order picked, and one deselected leaves the queue. The image in the annotator is not "next".
    private mutating func select(added: [String], removed: [String]) -> [Effect] {
        guard transition.isActive else { return [] }
        let before = queue.count
        queue.removeAll { removed.contains($0) }
        total -= before - queue.count
        var effects: [Effect] = []
        for key in added where key != transition.key && !queue.contains(key) {
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
private func short(_ key: String) -> String { (key as NSString).lastPathComponent }

extension AnnotationRun: CustomStringConvertible {
    var description: String { queue.isEmpty ? "\(phase)" : "\(phase) queued=\(queue.count)" }
}

extension AnnotationRun.Event: CustomStringConvertible {
    var description: String {
        switch self {
        case .annotate(let keys): return "annotate(\(keys.map(short).joined(separator: ", ")))"
        case .shown: return "shown"
        case .parked: return "parked"
        case .cancel: return "cancel"
        case .sent: return "sent"
        case .finish: return "finish"
        case .dismiss(let byHand): return byHand ? "dismiss(byHand)" : "dismiss"
        case .remove(let keys): return "remove(\(keys.map(short).joined(separator: ", ")))"
        case .newShot(let key): return "newShot(\(short(key)))"
        case .selectionChanged(let added, let removed):
            return "selectionChanged(+\(added.map(short).joined(separator: ", ")) -\(removed.map(short).joined(separator: ", ")))"
        case .copyFailed(let key): return "copyFailed(\(short(key)))"
        }
    }
}

extension AnnotationRun.Effect: CustomStringConvertible {
    var description: String {
        switch self {
        case .prepare(let k): return "prepare(\(short(k)))"
        case .show: return "show"
        case .park(let k): return "park(\(short(k)))"
        case .abandon(let k): return "abandon(\(short(k)))"
        case .returnCard(let k, let copied): return "returnCard(\(short(k))\(copied ? " copied" : ""))"
        case .hideAnnotator: return "hideAnnotator"
        case .join(let k): return "join(\(short(k)))"
        case .next(let k, let place, let total): return "next(\(short(k)) \(place) of \(total))"
        case .queued(let k, let place, let total): return "queued(\(short(k)) \(place) of \(total))"
        case .endRun(let focus): return focus ? "endRun(restoreFocus)" : "endRun"
        }
    }
}
