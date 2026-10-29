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
        case card(UUID)
    }

    enum Event: Equatable {
        /// A column of cards came up. While the shortcut lists, it is the stack's; otherwise it is
        /// lone thumbnails, which nobody asked for.
        case cardsShown
        /// The shortcut, the menu's Show Recent Screenshots or `recent`.
        case shortcut(StackRequest)
        /// The recent screenshots were listed for the shortcut; `found` when there was any.
        case listed(found: Bool)
        /// A selection began in the corner.
        case selected
        /// The editor took the keys.
        case editorOpened
        /// The annotation run is over.
        case editorClosed(RunEnding?)
        /// A card came home from the editor and is in its slot; `others` when other cards share the column.
        case cardLanded(UUID, others: Bool)
        /// The column is going.
        case dismiss(DismissReason)
        /// The column has slid off the screen.
        case slidOut
    }

    enum Effect: Equatable {
        // The window side, which `CornerKeys` runs.
        /// The panel takes the keys before the cards are listed.
        case holdKeys
        case takeKeys(KeyFocus)
        case releaseKeys
        case restoreFocus(reason: String)
        // The cards' side, which `ThumbnailController` runs.
        /// The editor gives way to the stack.
        case closeEditor
        /// List the recent screenshots and present them as the stack; answer `listed`.
        case listRecent
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
        case .cardsShown:
            guard !listing else { return [] }
            mode = .thumbnails
            return [.releaseKeys]
        case .shortcut(let request):
            stackOnLanding = false
            // A stack made from the corner's own cards brings in the older ones first.
            if isStack, mode != .stack(recent: false) || editorOpen { return dismiss(DismissReason(request)) }
            listing = true
            return [.holdKeys] + (editorOpen ? [.closeEditor] : []) + [.listRecent]
        case .listed(let found):
            listing = false
            // An editor still closing, while a zoom springs back to the fit, keeps the keys until
            // its card lands in the stack.
            let takeKeys: [Effect] = editorOpen ? [] : [.takeKeys(.current)]
            if isStack {
                if found { mode = .stack(recent: true) }
                return takeKeys
            }
            guard found else { return [.releaseKeys] }
            mode = .stack(recent: true)
            return takeKeys
        case .selected:
            guard mode == .thumbnails, !editorOpen else { return [] }
            mode = .stack(recent: false)
            return [.takeKeys(.current)]
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
                return [.takeKeys(.card(id))]
            }
            return isKeyed ? [.takeKeys(.card(id))] : []
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
        return [.releaseKeys, .slideOut(reason)]
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
        case .cardsShown: return "cardsShown"
        case .shortcut(let request): return "shortcut(\(request.rawValue))"
        case .listed(let found): return found ? "listed" : "listed(nothing)"
        case .selected: return "selected"
        case .editorOpened: return "editorOpened"
        case .editorClosed(let ending): return "editorClosed(\(ending.map { "\($0)" } ?? "no hand"))"
        case .cardLanded: return "cardLanded"
        case .dismiss(let reason): return "dismiss(\(reason.rawValue))"
        case .slidOut: return "slidOut"
        }
    }
}

extension CornerPresentation.Effect: CustomStringConvertible {
    var description: String {
        switch self {
        case .holdKeys: return "holdKeys"
        case .takeKeys(let focus):
            switch focus {
            case .current: return "takeKeys"
            case .card: return "takeKeys(card)"
            }
        case .releaseKeys: return "releaseKeys"
        case .restoreFocus: return "restoreFocus"
        case .closeEditor: return "closeEditor"
        case .listRecent: return "listRecent"
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
