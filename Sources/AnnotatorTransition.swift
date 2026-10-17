import Foundation

/// One image opening in the annotator. `AnnotationRun` mints the id for every image it sends there
/// and never reuses one, so the same file closed and opened again is another opening. An opening is
/// its id: a rename gives the same opening another key, and an answer still in flight names the old
/// one, so two values with one id are the same opening.
struct Opening: Hashable {
    let id: Int
    let key: ScreenshotKey

    static func == (a: Opening, b: Opening) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    func renamed(from old: ScreenshotKey, to new: ScreenshotKey) -> Opening {
        key == old ? Opening(id: id, key: new) : self
    }
}

/// The one owner of "what is in the annotator, where it came from, and what is in flight".
/// `reduce` takes the current state and one event and returns the next state and the effects the
/// controllers must run, in order. Nothing else decides a transition, so every interruption
/// sequence is a table lookup here and a unit test, not reasoning across three files.
///
/// Serialization rule: a `prepare` is never emitted while a park is in flight. A request that
/// arrives during a park only changes what happens once `parked` comes back.
///
/// Each image the annotator opens is an `Opening`, minted by `AnnotationRun`. An answer that names
/// an opening other than the current one is about an image that has gone, and changes nothing.
struct AnnotatorTransition: Equatable {
    /// What to do once the editor has parked the current drawing.
    enum Next: Equatable {
        case annotate(Opening)  // the old card returns and this one flies out (a swap)
        case close              // Esc or Send: the card returns, to its slot or the corner, with no Copied notice
        case finish             // the result is on the clipboard: the card returns, to its slot or the corner, marked copied
        case dismiss            // the panel is leaving with it
        case remove             // the file is gone
    }

    enum Phase: Equatable {
        case idle
        case flyingOut(Opening)            // prepare sent; the card is travelling to the annotator frame
        case annotating(Opening)           // the annotator is visible with this image
        case parking(Opening, then: Next)  // the editor is parking this image's drawing
    }

    enum Event: Equatable {
        case annotate(Opening)
        case shown(Opening)      // the flight landed and the annotator became visible
        case parked(Opening)     // the editor finished parking
        case close               // Esc, click outside, Cmd+W, or Send: nothing was copied
        case finish              // Done or Return: the result is on the clipboard
        case newShot(ScreenshotKey)     // a new file arrived
        case dismiss             // the panel is going away
        case remove(ScreenshotKey)      // a file was trashed or deleted
        case renamed(from: ScreenshotKey, to: ScreenshotKey)   // a file was renamed: the opening keeps its id and takes the new key
    }

    enum Effect: Equatable {
        case prepare(Opening)    // load this image in the hidden annotator and fly its card out
        case show                // reveal the annotator in place of the landed card
        case park(Opening)       // ask the editor to park; answer with `.parked`
        case abandon(Opening)    // the editor holds this image and nobody saw it: close it at once, no fit on the way out
        case returnCard(Opening, copied: Bool)  // fly the card back; `copied` when its result is on the clipboard
        case hideAnnotator       // the annotator is done; nothing returns
        case join(ScreenshotKey)        // a new shot joins the panel while the annotator stays open
    }

    private(set) var phase: Phase = .idle

    /// The image in the annotator or on its way there, if any.
    var opening: Opening? {
        switch phase {
        case .idle: return nil
        case .flyingOut(let o), .annotating(let o), .parking(let o, _): return o
        }
    }

    var isActive: Bool { phase != .idle }

    mutating func reduce(_ event: Event) -> [Effect] {
        if case .renamed(let old, let new) = event {
            switch phase {
            case .idle: break
            case .flyingOut(let o): phase = .flyingOut(o.renamed(from: old, to: new))
            case .annotating(let o): phase = .annotating(o.renamed(from: old, to: new))
            case .parking(let o, let next):
                if case .annotate(let o2) = next {
                    phase = .parking(o.renamed(from: old, to: new), then: .annotate(o2.renamed(from: old, to: new)))
                } else {
                    phase = .parking(o.renamed(from: old, to: new), then: next)
                }
            }
            return []
        }
        switch phase {
        case .idle:
            guard case .annotate(let o) = event else { return [] }
            phase = .flyingOut(o)
            return [.prepare(o)]

        case .flyingOut(let o):
            // The window has not come up, so nobody has seen this image and no zoom has moved it.
            // A request to close it or to open another one turns the flight around in this turn:
            // `abandon` stores the drawing at once, with no fit-out to wait for.
            switch event {
            case .shown(let shown):
                guard shown == o else { return [] }
                phase = .annotating(o)
                return [.show]
            case .close:
                phase = .idle
                return [.abandon(o), .returnCard(o, copied: false)]
            case .annotate(let o2):
                if o2.key == o.key { return [] }
                phase = .flyingOut(o2)
                return [.abandon(o), .returnCard(o, copied: false), .prepare(o2)]
            case .finish:
                // The editor holds the keys from `prepare`, so Return can finish before the window
                // is up; the drawing is parked as usual and the card comes back marked copied.
                phase = .parking(o, then: .finish)
                return [.park(o)]
            case .dismiss:
                // The panel takes the image with it (see `ThumbnailController.dismiss`), which
                // aims this flight offscreen before the event arrives. The park keeps the card in
                // the layer until it is out of sight.
                phase = .parking(o, then: .dismiss)
                return [.park(o)]
            case .remove(let r):
                guard r == o.key else { return [] }
                phase = .parking(o, then: .remove)
                return [.park(o)]
            case .newShot(let n):
                return [.join(n)]
            case .parked, .renamed:
                return []
            }

        case .annotating(let o):
            switch event {
            case .shown:
                return []
            case .annotate(let o2):
                if o2.key == o.key { return [] }
                phase = .parking(o, then: .annotate(o2))
                return [.park(o)]
            case .close:
                phase = .parking(o, then: .close)
                return [.park(o)]
            case .finish:
                phase = .parking(o, then: .finish)
                return [.park(o)]
            case .dismiss:
                phase = .parking(o, then: .dismiss)
                return [.park(o)]
            case .remove(let r):
                guard r == o.key else { return [] }
                phase = .parking(o, then: .remove)
                return [.park(o)]
            case .newShot(let n):
                return [.join(n)]
            case .parked, .renamed:
                return []
            }

        case .parking(let o, let next):
            switch event {
            case .parked(let parked):
                guard parked == o else { return [] }
                switch next {
                case .annotate(let o2):
                    phase = .flyingOut(o2)
                    return [.returnCard(o, copied: false), .prepare(o2)]
                case .close:
                    // A lone thumbnail left the panel when the annotator opened; returnCard flies it
                    // back to the corner, so the editor never leaves without a flight.
                    phase = .idle
                    return [.returnCard(o, copied: false)]
                case .finish:
                    phase = .idle
                    return [.returnCard(o, copied: true)]
                case .dismiss, .remove:
                    phase = .idle
                    return [.hideAnnotator]
                }
            case .annotate(let o2):
                // A later request wins, unless the panel is already leaving or the card is gone.
                // Re-requesting the image that is finishing changes nothing: it is coming back anyway.
                switch next {
                case .annotate, .close: phase = .parking(o, then: o2.key == o.key ? .close : .annotate(o2))
                case .finish: if o2.key != o.key { phase = .parking(o, then: .annotate(o2)) }
                case .dismiss, .remove: break
                }
                return []
            case .dismiss:
                phase = .parking(o, then: .dismiss)
                return []
            case .remove(let r):
                switch next {
                case .annotate(let o2) where r == o2.key: phase = .parking(o, then: .close)
                case .close where r == o.key, .finish where r == o.key: phase = .parking(o, then: .remove)
                default: break
                }
                return []
            case .newShot(let n):
                return [.join(n)]
            case .close, .finish, .shown, .renamed:
                return []
            }
        }
    }
}

// Short log forms: keys print as file names, so a `[transition]` line stays readable.
private func short(_ key: ScreenshotKey) -> String { key.name }

extension Opening: CustomStringConvertible {
    var description: String { "\(short(key))#\(id)" }
}

extension AnnotatorTransition.Phase: CustomStringConvertible {
    var description: String {
        switch self {
        case .idle: return "idle"
        case .flyingOut(let o): return "flyingOut(\(o))"
        case .annotating(let o): return "annotating(\(o))"
        case .parking(let o, let next): return "parking(\(o) then \(next))"
        }
    }
}

extension AnnotatorTransition.Next: CustomStringConvertible {
    var description: String {
        switch self {
        case .annotate(let o): return "annotate(\(o))"
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
        case .annotate(let o): return "annotate(\(o))"
        case .shown(let o): return "shown(\(o))"
        case .parked(let o): return "parked(\(o))"
        case .close: return "close"
        case .finish: return "finish"
        case .newShot(let k): return "newShot(\(short(k)))"
        case .dismiss: return "dismiss"
        case .remove(let k): return "remove(\(short(k)))"
        case .renamed(let from, let to): return "renamed(\(short(from)) to \(short(to)))"
        }
    }
}

extension AnnotatorTransition.Effect: CustomStringConvertible {
    var description: String {
        switch self {
        case .prepare(let o): return "prepare(\(o))"
        case .show: return "show"
        case .park(let o): return "park(\(o))"
        case .abandon(let o): return "abandon(\(o))"
        case .returnCard(let o, let copied): return "returnCard(\(o)\(copied ? " copied" : ""))"
        case .hideAnnotator: return "hideAnnotator"
        case .join(let k): return "join(\(short(k)))"
        }
    }
}
