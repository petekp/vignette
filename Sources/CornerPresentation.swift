import Foundation

/// How the person ended an annotation run, as `AnnotationRun` reports it. Nil when no hand did: the
/// panel went, or the file did.
enum RunEnding: Equatable {
    /// Esc, Cmd+W or the bar's close: back out of the editor.
    case back
    /// A click outside the editor, which the app clicked in takes.
    case clickedAway
    /// The shortcut, which opens the stack as the editor closes.
    case shortcut
    /// Done, or quick Done: the result is on the clipboard.
    case finished
    /// Send: the drawing went to an agent session.
    case sent
}

/// Whether the corner shows lone thumbnails or the recent stack, who has the keys, and where they go
/// when something there closes. The one place that decides it: `CornerKeys` runs what this answers,
/// and nothing else takes the keys, shows the backdrop, watches for a click outside, or hands the
/// focus back.
///
/// The rule: the backdrop goes with the keys. The stack has both; lone thumbnails have neither, so a
/// card that arrives on its own never takes a key from the app the person is typing in.
struct CornerPresentation: Equatable {
    enum Mode: Equatable {
        case hidden
        /// Lone thumbnails: cards that came up on their own.
        case thumbnails
        /// The recent stack. `recent` when it holds the recent screenshots, false for one the corner
        /// became with its own cards.
        case stack(recent: Bool)
    }

    /// The card the stack's keys act on first.
    enum KeyFocus: Equatable {
        /// The card focused already, else the hovered one, else the newest.
        case current
        case hovered
        case card(UUID)
    }

    enum Event: Equatable {
        /// Lone thumbnails came up where nothing was.
        case thumbnailsShown
        /// The shortcut, the menu's Show Recent Screenshots or `recent`, pressed at `pressedAt`.
        case shortcut(StackRequest, pressedAt: CFTimeInterval?)
        /// The recent screenshots were listed for the shortcut; `found` when there was any.
        case listed(found: Bool, pressedAt: CFTimeInterval?)
        /// A selection began in the corner.
        case selected
        /// The editor took the keys.
        case editorOpened
        /// The annotation run is over.
        case editorClosed(RunEnding?)
        /// A card came home from the editor and is in its slot; `others` when other cards share the column.
        case cardLanded(UUID, others: Bool)
        /// Esc reached the stack; `selecting` while cards are selected.
        case esc(selecting: Bool)
        /// A click landed outside this app's windows.
        case clickedOutside
        /// The column is going.
        case dismiss(DismissReason)
        /// The column has slid off the screen.
        case slidOut
    }

    enum Effect: Equatable {
        // The window side, which `CornerKeys` runs.
        /// The panel takes the keys before the cards are listed; `orderIn` when nothing was on screen.
        case holdKeys(pressedAt: CFTimeInterval?, orderIn: Bool)
        case takeKeys(KeyFocus, pressedAt: CFTimeInterval?)
        case releaseKeys
        /// The shortcut found nothing: the keys go back, and the panel with them when it held nothing.
        case letGoOfHeldKeys(orderOut: Bool)
        case backdrop(Bool)
        case watchOutsideClicks(Bool)
        case restoreFocus(reason: String)
        // The cards' side, which `ThumbnailController` runs.
        /// The editor gives way to the stack.
        case closeEditor
        /// List the recent screenshots and present them as the stack; answer `listed`.
        case listRecent
        case clearSelection
        case slideOut(DismissReason)
    }

    private(set) var mode: Mode = .hidden
    /// The editor has the keys, from its opening until the run is over.
    private(set) var editorOpen = false
    /// The shortcut is listing the recent screenshots: a card coming home stays for the stack.
    private(set) var listing = false
    /// Esc closed the editor over lone thumbnails: the card coming home makes them the stack.
    private var stackOnLanding = false

    var isStack: Bool { if case .stack = mode { return true }; return false }
    /// Keys pressed reach the stack.
    var isKeyed: Bool { isStack && !editorOpen }
    /// Lone thumbnails leave on their own after a while, unless the stack is opening over them; the
    /// stack stays until it is dismissed.
    var leavesOnItsOwn: Bool { mode == .thumbnails && !listing }

    mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case .thumbnailsShown:
            mode = .thumbnails
            return [.releaseKeys]
        case .shortcut(let request, let pressedAt):
            stackOnLanding = false
            // A stack made from the corner's own cards brings in the older ones first.
            if isStack, mode != .stack(recent: false) || editorOpen { return dismiss(DismissReason(request)) }
            listing = true
            return [.holdKeys(pressedAt: pressedAt, orderIn: mode == .hidden)] + (editorOpen ? [.closeEditor] : []) + [.listRecent]
        case .listed(let found, let pressedAt):
            listing = false
            // An editor still closing, while a zoom springs back to the fit, keeps the keys until
            // its card lands in the stack.
            let takeKeys: [Effect] = editorOpen ? [] : [.takeKeys(.current, pressedAt: pressedAt)]
            if isStack {
                if found { mode = .stack(recent: true) }
                return takeKeys
            }
            guard found else { return [.letGoOfHeldKeys(orderOut: mode == .hidden)] }
            mode = .stack(recent: true)
            return [.watchOutsideClicks(true), .backdrop(true)] + takeKeys
        case .selected:
            guard mode == .thumbnails, !editorOpen else { return [] }
            mode = .stack(recent: false)
            return [.watchOutsideClicks(true), .backdrop(true), .takeKeys(.hovered, pressedAt: nil)]
        case .editorOpened:
            editorOpen = true
            stackOnLanding = false
            return [.releaseKeys]
        case .editorClosed(let ending):
            editorOpen = false
            stackOnLanding = ending == .back && mode == .thumbnails
            // The shortcut's stack takes the keys from the editor; any other hand hands them back,
            // and the stack, or the corner Esc made the stack, takes them again when the card lands.
            guard let ending, ending != .shortcut else { return [] }
            return [.restoreFocus(reason: "annotator closed")]
        case .cardLanded(let id, let others):
            if stackOnLanding, mode == .thumbnails, !editorOpen, others {
                stackOnLanding = false
                mode = .stack(recent: false)
                return [.watchOutsideClicks(true), .backdrop(true), .takeKeys(.card(id), pressedAt: nil)]
            }
            return isKeyed ? [.takeKeys(.card(id), pressedAt: nil)] : []
        case .esc(let selecting):
            guard isKeyed else { return [] }
            return selecting ? [.clearSelection] : dismiss(.esc)
        case .clickedOutside:
            return isStack ? dismiss(.clickOutside) : []
        case .dismiss(let reason):
            return dismiss(reason)
        case .slidOut:
            return mode == .hidden ? [.restoreFocus(reason: "stack dismissed")] : []
        }
    }

    private mutating func dismiss(_ reason: DismissReason) -> [Effect] {
        guard mode != .hidden else { return [] }
        mode = .hidden
        stackOnLanding = false
        return [.watchOutsideClicks(false), .releaseKeys, .backdrop(false), .slideOut(reason)]
    }
}

/// What asked for the recent stack: the shortcut, the menu's Show Recent Screenshots, or `vignette://recent`.
enum StackRequest: String { case shortcut, menu, url }

/// What closed the corner, for the `[stack] dismissed` line.
enum DismissReason: String {
    case esc, shortcut, menu, url, timeout, removed
    case clickOutside = "click-outside", quickDone = "quick-done"
    init(_ request: StackRequest) {
        switch request {
        case .shortcut: self = .shortcut
        case .menu: self = .menu
        case .url: self = .url
        }
    }
}

extension CornerPresentation.Event: CustomStringConvertible {
    var description: String {
        switch self {
        case .thumbnailsShown: return "thumbnailsShown"
        case .shortcut(let request, _): return "shortcut(\(request.rawValue))"
        case .listed(let found, _): return found ? "listed" : "listed(nothing)"
        case .selected: return "selected"
        case .editorOpened: return "editorOpened"
        case .editorClosed(let ending): return "editorClosed(\(ending.map { "\($0)" } ?? "no hand"))"
        case .cardLanded: return "cardLanded"
        case .esc(let selecting): return selecting ? "esc(selecting)" : "esc"
        case .clickedOutside: return "clickedOutside"
        case .dismiss(let reason): return "dismiss(\(reason.rawValue))"
        case .slidOut: return "slidOut"
        }
    }
}

extension CornerPresentation.Effect: CustomStringConvertible {
    var description: String {
        switch self {
        case .holdKeys(_, let orderIn): return orderIn ? "holdKeys(orderIn)" : "holdKeys"
        case .takeKeys(let focus, _):
            switch focus {
            case .current: return "takeKeys"
            case .hovered: return "takeKeys(hovered)"
            case .card: return "takeKeys(card)"
            }
        case .releaseKeys: return "releaseKeys"
        case .letGoOfHeldKeys(let orderOut): return orderOut ? "letGoOfHeldKeys(orderOut)" : "letGoOfHeldKeys"
        case .backdrop(let on): return on ? "backdrop" : "noBackdrop"
        case .watchOutsideClicks(let on): return on ? "watchOutsideClicks" : "stopWatchingOutsideClicks"
        case .restoreFocus: return "restoreFocus"
        case .closeEditor: return "closeEditor"
        case .listRecent: return "listRecent"
        case .clearSelection: return "clearSelection"
        case .slideOut(let reason): return "slideOut(\(reason.rawValue))"
        }
    }
}

extension CornerPresentation.Mode: CustomStringConvertible {
    var description: String {
        switch self {
        case .hidden: return "hidden"
        case .thumbnails: return "thumbnails"
        case .stack(let recent): return recent ? "stack" : "stack(ownCards)"
        }
    }
}
