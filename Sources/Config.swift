import AppKit

/// Product behavior that lives in code. Per-machine knobs (folder, counts, hotkey, backdrop) live in
/// ~/.config/shotnote/settings.json; see Settings.swift.
enum Config {
    /// Appended to the original file name when an annotated copy is saved next to it.
    static let annotatedSuffix = "-annotated"
    /// Longest side of a card preview, in pixels. The page renders park previews at this size; it
    /// crosses in the `load` payload, so this is the only place it is written.
    static let previewMaxPixel = 1600
    /// Longest side, in pixels, of the annotations the page renders for the zoom stand-in. One at
    /// a time, for the image in the annotator only, so this is what it costs to hold.
    static let overlayMaxPixel = 2048

    /// Everything you can do to screenshots. Each action is a hover button on a card, an entry in the
    /// selection strip, a keyboard shortcut inside the recent stack, and a `shotnote://<id>` URL, according
    /// to its `placement` and `key`. Actions always receive a list: the cards in the order they were
    /// selected when the stack runs them, and the files in the order a URL names them.
    static let actions: [ShotAction] = [
        ShotAction(id: "copy", symbol: "doc.on.doc", label: "Copy", key: .init("c", [.command]),
                   placement: .everywhere) { shots, app in app.copyToClipboard(shots) },
        ShotAction(id: "annotate", symbol: "pencil.line", label: "Draw", key: .init("\r", []),
                   placement: .strip, isDefault: true) { shots, app in app.annotate(shots) },
        ShotAction(id: "paths", label: "Copy Paths", key: .init("c", [.command, .option]),
                   placement: .shortcut) { shots, app in app.copyPaths(shots) },
        ShotAction(id: "copy-annotated", label: "Copy Drawing", key: .init("c", [.command, .shift]),
                   placement: .shortcut) { shots, app in app.copyAnnotated(shots) },
        ShotAction(id: "stitch", symbol: "rectangle.stack", label: "Stitch", key: .init("s", [.command]),
                   placement: .strip, minimumCount: 2) { shots, app in app.stitch(shots) },
        ShotAction(id: "trash", symbol: "trash", label: "Delete", key: .init("\u{7f}", [.command]),
                   placement: .everywhere) { shots, app in app.moveToTrash(shots) },
    ]

    static func action(id: String) -> ShotAction? { actions.first { $0.id == id } }

    /// The selection strip, top to bottom.
    static var stripActions: [ShotAction] { actions.filter(\.showsInStrip) }
}

struct ShotAction: Sendable {
    enum Placement { case strip, everywhere, shortcut }   // shortcut: keyboard and URL only; everywhere: the card's corners too
    struct Key: Equatable, Sendable {
        let character: String
        let modifiers: NSEvent.ModifierFlags
        init(_ character: String, _ modifiers: NSEvent.ModifierFlags) { self.character = character; self.modifiers = modifiers }

        /// The shortcut as a user reads it: ⌘C, ⌥⌘C, ↩, ⌘⌫. The one renderer; the selection
        /// strip's rows and their tooltips both read it, so a row and its tooltip cannot differ.
        var glyphs: String {
            var s = ""
            if modifiers.contains(.control) { s += "⌃" }
            if modifiers.contains(.option) { s += "⌥" }
            if modifiers.contains(.shift) { s += "⇧" }
            if modifiers.contains(.command) { s += "⌘" }
            switch character {
            case "\r": return s + "↩"
            case "\u{7f}": return s + "⌫"
            default: return s + character.uppercased()
            }
        }
    }

    let id: String
    /// SF Symbol name. None for a `.shortcut` action: it is drawn on no card and in no strip.
    var symbol: String? = nil
    let label: String
    var key: Key? = nil     // shortcut while the recent stack has focus
    var placement: Placement = .everywhere
    var isDefault = false   // runs when a card is clicked outside selection mode
    var minimumCount = 1
    let run: @MainActor @Sendable ([Screenshot], Actions) -> Void

    var showsInStrip: Bool { placement == .strip || placement == .everywhere }
}

/// What an action can do. Implemented by AppDelegate.
@MainActor
protocol Actions: AnyObject {
    func copyToClipboard(_ shots: [Screenshot])
    func copyPaths(_ shots: [Screenshot])
    /// Opens the first of `shots` and queues the rest, since the annotator holds one image:
    /// finishing one opens the next until the list is done.
    func annotate(_ shots: [Screenshot])
    /// Exports each screenshot's draft (or uses the file as is when it has none) and copies the set.
    func copyAnnotated(_ shots: [Screenshot])
    func stitch(_ shots: [Screenshot])
    func moveToTrash(_ shots: [Screenshot])
}
