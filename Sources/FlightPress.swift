import CoreGraphics
import Foundation

/// What becomes of a press on a card in flight. The flight layer takes every press on a flying
/// card, so none reaches the app behind it, and this decides where it goes from there. A press on
/// the card flying into the editor is held until the editor's window can take events, then handed
/// to the editor with every drag since, in order, and the rest of the press follows it there. A
/// press on any other flight is swallowed up to its release. Pure, so the order is tested without
/// a window server.
struct FlightPress {
    enum Phase: Equatable {
        case pressed(clickCount: Int)
        case dragged
        case released
    }

    struct Event: Equatable {
        var phase: Phase
        /// The point of the flying picture under the pointer, as a fraction of the picture from its
        /// top-left corner, or nil when no flight was under it.
        var picture: CGPoint?
        /// The pointer on screen, in global points with y up.
        var screen: CGPoint
        /// `NSEvent.ModifierFlags`' raw value.
        var modifiers: UInt
        var time: TimeInterval
    }

    private enum State: Equatable {
        case idle
        case holding(key: String, events: [Event])
        case handing(key: String)
        case swallowing
    }

    private var state = State.idle

    /// The image a press is held for or handed to, if any.
    var key: String? {
        switch state {
        case .holding(let key, _), .handing(let key): return key
        case .idle, .swallowing: return nil
        }
    }

    /// A press on a flight. `key` is the image that flight carries into the editor, nil for any
    /// other flight or for a press beside the picture; `ready` says the editor's window for that
    /// image can take events already. Returns what the editor takes now.
    mutating func press(_ event: Event, into key: String?, ready: Bool) -> [Event] {
        guard let key, event.picture != nil else { state = .swallowing; return [] }
        if ready { state = .handing(key: key); return [event] }
        state = .holding(key: key, events: [event])
        return []
    }

    /// A drag, or the release of the press. Returns what the editor takes now. Once handed over,
    /// the rest of the press goes by where the pointer is on screen: the editor's window is where
    /// its picture is, and the flight still settling over it is a few points off at most.
    mutating func move(_ event: Event) -> [Event] {
        switch state {
        case .idle:
            return []
        case .holding(let key, var events):
            events.append(event)
            state = .holding(key: key, events: events)
            return []
        case .handing:
            if event.phase == .released { state = .idle }
            var placed = event
            placed.picture = nil
            return [placed]
        case .swallowing:
            if event.phase == .released { state = .idle }
            return []
        }
    }

    /// The editor's window for `key` can take events: everything held goes to it, in order, and a
    /// press still down follows it there.
    mutating func ready(_ key: String) -> [Event] {
        guard case .holding(key, let events) = state else { return [] }
        state = events.last?.phase == .released ? .idle : .handing(key: key)
        return events
    }

    /// The image `key` is no longer on its way into the editor, or no longer in it: what is held
    /// goes nowhere, and the rest of a press still down is swallowed.
    mutating func ended(_ key: String) {
        switch state {
        case .holding(key, let events):
            state = events.last?.phase == .released ? .idle : .swallowing
        case .handing(key):
            state = .swallowing
        default:
            break
        }
    }
}
