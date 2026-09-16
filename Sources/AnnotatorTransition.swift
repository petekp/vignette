import Foundation

/// The one owner of "what is in the annotator, where it came from, and what is in flight".
/// `reduce` takes the current state and one event and returns the next state and the effects the
/// controllers must run, in order. Nothing else decides a transition, so every interruption
/// sequence is a table lookup here and a unit test, not reasoning across three files.
///
/// Serialization rule: a `prepare` is never emitted while a park is in flight. A request that
/// arrives during a park only changes what happens once `parked` comes back.
struct AnnotatorTransition: Equatable {
    /// Where the annotated card came from: a lone fresh thumbnail, or the recent stack.
    enum Origin: Equatable { case thumbnail, stack }

    /// What to do once the page has parked the current draft.
    enum Next: Equatable {
        case annotate(String)   // the old card returns and this key flies out (a swap)
        case close              // the session was abandoned: the card returns to its stack slot, or the annotator just hides
        case finish             // the result is on the clipboard: the card returns, to its slot or the corner, marked copied
        case dismiss            // the panel is leaving with it
        case remove             // the file is gone
    }

    enum Phase: Equatable {
        case idle
        case flyingOut(String)            // prepare sent; the card is travelling to the annotator frame
        case annotating(String)           // the annotator is visible with this key
        case parking(String, then: Next)  // the page is parking this key's draft
    }

    enum Event: Equatable {
        case annotate(String, from: Origin)
        case shown               // the flight landed and the annotator became visible
        case parked              // the page finished parking
        case close               // Esc, click outside, or Cmd+W: nothing to show for it
        case finish              // Done or Return: the result is on the clipboard
        case newShot(String)     // a new file arrived
        case dismiss             // the panel is going away
        case remove(String)      // a file was trashed or deleted
    }

    enum Effect: Equatable {
        case prepare(String)     // load this key in the hidden annotator and fly its card out
        case show                // reveal the annotator in place of the landed card
        case park(String)        // ask the page to park; answer with `.parked`
        case returnCard(String)  // fly the card back to its slot
        case hideAnnotator       // the annotator is done; nothing returns
        case markCopied(String)  // the returned card shows the copied mark when it lands
        case join(String)        // a new shot joins the panel while the annotator stays open
    }

    private(set) var phase: Phase = .idle
    private(set) var origin: Origin = .stack

    /// The key in the annotator or on its way there, if any.
    var key: String? {
        switch phase {
        case .idle: return nil
        case .flyingOut(let k), .annotating(let k), .parking(let k, _): return k
        }
    }

    var isActive: Bool { phase != .idle }

    mutating func reduce(_ event: Event) -> [Effect] {
        switch phase {
        case .idle:
            guard case .annotate(let k, let from) = event else { return [] }
            phase = .flyingOut(k); origin = from
            return [.prepare(k)]

        case .flyingOut(let k), .annotating(let k):
            switch event {
            case .shown:
                guard case .flyingOut = phase else { return [] }
                phase = .annotating(k)
                return [.show]
            case .annotate(let k2, _):
                if k2 == k { return [] }
                phase = .parking(k, then: .annotate(k2))
                return [.park(k)]
            case .close:
                phase = .parking(k, then: .close)
                return [.park(k)]
            case .finish:
                phase = .parking(k, then: .finish)
                return [.park(k)]
            case .dismiss:
                phase = .parking(k, then: .dismiss)
                return [.park(k)]
            case .remove(let r):
                guard r == k else { return [] }
                phase = .parking(k, then: .remove)
                return [.park(k)]
            case .newShot(let n):
                return [.join(n)]
            case .parked:
                return []
            }

        case .parking(let k, let next):
            switch event {
            case .parked:
                switch next {
                case .annotate(let k2):
                    phase = .flyingOut(k2)
                    return [.returnCard(k), .prepare(k2)]
                case .close:
                    phase = .idle
                    return origin == .stack ? [.returnCard(k)] : [.hideAnnotator]
                case .finish:
                    // A lone thumbnail left the panel when the annotator opened; returnCard brings it back to the corner.
                    phase = .idle
                    return [.returnCard(k), .markCopied(k)]
                case .dismiss, .remove:
                    phase = .idle
                    return [.hideAnnotator]
                }
            case .annotate(let k2, _):
                // A later request wins, unless the panel is already leaving or the card is gone.
                // Re-requesting the key that is finishing changes nothing: it is coming back anyway.
                switch next {
                case .annotate, .close: phase = .parking(k, then: k2 == k ? .close : .annotate(k2))
                case .finish: if k2 != k { phase = .parking(k, then: .annotate(k2)) }
                case .dismiss, .remove: break
                }
                return []
            case .dismiss:
                phase = .parking(k, then: .dismiss)
                return []
            case .remove(let r):
                switch next {
                case .annotate(let k2) where r == k2: phase = .parking(k, then: .close)
                case .close where r == k, .finish where r == k: phase = .parking(k, then: .remove)
                default: break
                }
                return []
            case .newShot(let n):
                return [.join(n)]
            case .close, .finish, .shown:
                return []
            }
        }
    }
}

// Short log forms: keys print as file names, so a `[transition]` line stays readable.
private func short(_ key: String) -> String { (key as NSString).lastPathComponent }

extension AnnotatorTransition.Phase: CustomStringConvertible {
    var description: String {
        switch self {
        case .idle: return "idle"
        case .flyingOut(let k): return "flyingOut(\(short(k)))"
        case .annotating(let k): return "annotating(\(short(k)))"
        case .parking(let k, let next): return "parking(\(short(k)) then \(next))"
        }
    }
}

extension AnnotatorTransition.Next: CustomStringConvertible {
    var description: String {
        switch self {
        case .annotate(let k): return "annotate(\(short(k)))"
        case .close: return "close"
        case .finish: return "finish"
        case .dismiss: return "dismiss"
        case .remove: return "remove"
        }
    }
}

extension AnnotatorTransition.Event: CustomStringConvertible {
    var description: String {
        switch self {
        case .annotate(let k, let from): return "annotate(\(short(k)) from \(from))"
        case .shown: return "shown"
        case .parked: return "parked"
        case .close: return "close"
        case .finish: return "finish"
        case .newShot(let k): return "newShot(\(short(k)))"
        case .dismiss: return "dismiss"
        case .remove(let k): return "remove(\(short(k)))"
        }
    }
}

extension AnnotatorTransition.Effect: CustomStringConvertible {
    var description: String {
        switch self {
        case .prepare(let k): return "prepare(\(short(k)))"
        case .show: return "show"
        case .park(let k): return "park(\(short(k)))"
        case .returnCard(let k): return "returnCard(\(short(k)))"
        case .hideAnnotator: return "hideAnnotator"
        case .markCopied(let k): return "markCopied(\(short(k)))"
        case .join(let k): return "join(\(short(k)))"
        }
    }
}
