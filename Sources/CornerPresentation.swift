import Foundation

/// How the person ended an annotation run, as `AnnotationRun` reports it. Nil when no hand did: the
/// panel went, or the file did.
enum RunEnding: Equatable {
    /// Esc, Cmd+W or the bar's close: back out of the editor.
    case back
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
        /// A card came home from the editor and is in its slot.
        case cardLanded(UUID)
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

    var isStack: Bool { if case .stack = mode { return true }; return false }
    /// Keys pressed reach the stack.
    var isKeyed: Bool { isStack && !editorOpen }
    /// Lone thumbnails leave on their own after a while; the stack stays until it is dismissed.
    var leavesOnItsOwn: Bool { mode == .thumbnails }

    mutating func reduce(_ event: Event) -> [Effect] {
        switch event {
        case .thumbnailsShown:
            mode = .thumbnails
            return [.releaseKeys]
        case .shortcut(let request, let pressedAt):
            if isStack { return dismiss(DismissReason(request)) }
            return [.holdKeys(pressedAt: pressedAt, orderIn: mode == .hidden)] + (editorOpen ? [.closeEditor] : []) + [.listRecent]
        case .listed(let found, let pressedAt):
            guard found else { return [.letGoOfHeldKeys(orderOut: mode == .hidden)] }
            mode = .stack(recent: true)
            return [.watchOutsideClicks(true), .backdrop(true), .takeKeys(.current, pressedAt: pressedAt)]
        case .selected:
            guard mode == .thumbnails, !editorOpen else { return [] }
            mode = .stack(recent: false)
            return [.watchOutsideClicks(true), .backdrop(true), .takeKeys(.hovered, pressedAt: nil)]
        case .editorOpened:
            editorOpen = true
            return [.releaseKeys]
        case .editorClosed(let ending):
            editorOpen = false
            return ending == nil ? [] : [.restoreFocus(reason: "annotator closed")]
        case .cardLanded(let id):
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
        return [.watchOutsideClicks(false), .releaseKeys, .backdrop(false), .slideOut(reason)]
    }
}

/// What asked for the recent stack: the shortcut, the menu's Show Recent Screenshots, or `vignette://recent`.
enum StackRequest: String { case shortcut, menu, url }

/// What closed the corner, for the `[stack] dismissed` line.
enum DismissReason: String {
    case esc, shortcut, menu, url, timeout, removed
    case clickOutside = "click-outside", quickDone = "quick-done"
    init(_ request: StackRequest) { self = DismissReason(rawValue: request.rawValue)! }
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
