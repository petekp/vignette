import AppKit

/// Product behavior that lives in code. Per-machine knobs (folder, counts, hotkey, backdrop) live in
/// ~/.config/vignette/settings.json; see Settings.swift.
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
    /// selection strip, a keyboard shortcut inside the recent stack, and a `vignette://<id>` URL, according
    /// to its `placement` and `key`. Actions always receive a list: the cards in the order they were
    /// selected when the stack runs them, and the files in the order a URL names them.
    static let actions: [ShotAction] = [
        ShotAction(id: "copy", symbol: "doc.on.doc", label: "Copy", key: .init("c", [.command]),
                   placement: .everywhere, kinds: [.image, .recording]) { shots, app in app.copyToClipboard(shots) },
        ShotAction(id: "annotate", symbol: "pencil.line", hintSymbol: "scribble.variable", label: "Draw",
                   key: .init("\r", []), placement: .strip, isDefault: true) { shots, app in app.annotate(shots) },
        ShotAction(id: "open", symbol: "arrow.up.forward.app", label: "Open", key: .init("\r", []),
                   placement: .strip, isDefault: true, kinds: [.recording]) { shots, app in app.open(shots) },
        ShotAction(id: "paths", label: "Copy Paths", key: .init("c", [.command, .option]),
                   placement: .shortcut, kinds: [.image, .recording]) { shots, app in app.copyPaths(shots) },
        ShotAction(id: "copy-annotated", label: "Copy Drawing", key: .init("c", [.command, .shift]),
                   placement: .shortcut) { shots, app in app.copyAnnotated(shots) },
        ShotAction(id: "stitch", symbol: "rectangle.stack", label: "Stitch", key: .init("s", [.command]),
                   placement: .strip, minimumCount: 2) { shots, app in app.stitch(shots) },
        ShotAction(id: "trash", symbol: "trash", label: "Delete", key: .init("\u{7f}", [.command]),
                   placement: .everywhere, kinds: [.image, .recording]) { shots, app in app.moveToTrash(shots) },
    ]

    static func action(id: String) -> ShotAction? { actions.first { $0.id == id } }

    /// The selection strip, top to bottom.
    static var stripActions: [ShotAction] { actions.filter(\.showsInStrip) }

    /// The strip's rows. Actions that share a shortcut share a row, and the row shows whichever of
    /// them applies to the selection: Draw and Open are both Return, and a row that offered both
    /// would always hold one that cannot run.
    static var stripRows: [[ShotAction]] {
        var rows: [[ShotAction]] = []
        for action in stripActions {
            if let i = rows.firstIndex(where: { $0[0].key != nil && $0[0].key == action.key }) { rows[i].append(action) }
            else { rows.append([action]) }
        }
        return rows
    }

    /// What a row shows for `shots`: the first of its actions that applies, else the first, drawn
    /// disabled with its reason.
    static func stripAction(in row: [ShotAction], for shots: [Screenshot]) -> ShotAction {
        row.first { $0.applies(to: shots) } ?? row[0]
    }

    /// What a click on a card does, and what the hint over it says: Draw on a screenshot, Open on a
    /// recording. nil for a selection no default action takes, such as screenshots and recordings together.
    static func defaultAction(for shots: [Screenshot]) -> ShotAction? {
        actions.first { $0.isDefault && $0.applies(to: shots) }
    }

    /// Which action a key runs on `shots`. `.unavailable` is a key that belongs to an action
    /// but to none that applies here, which the stack answers the way a disabled menu item's
    /// shortcut is answered; `.none` is a key no action has.
    enum KeyMatch { case run(ShotAction), unavailable, none }

    static func action(for matches: (ShotAction.Key) -> Bool, on shots: [Screenshot]) -> KeyMatch {
        let keyed = actions.filter { $0.key.map(matches) ?? false }
        guard !keyed.isEmpty else { return .none }
        return keyed.first { $0.applies(to: shots) }.map(KeyMatch.run) ?? .unavailable
    }
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
    /// The glyph in the hint that follows the pointer over a card, when it differs from `symbol`.
    var hintSymbol: String? = nil
    let label: String
    var key: Key? = nil     // shortcut while the recent stack has focus
    var placement: Placement = .everywhere
    var isDefault = false   // runs when a card is clicked outside selection mode
    var minimumCount = 1
    /// The kinds of file it can act on. Images only unless it says otherwise, so an action added
    /// later is never offered on a recording it was not written for.
    var kinds: Set<Screenshot.Kind> = [.image]
    let run: @MainActor @Sendable ([Screenshot], Actions) -> Void

    var showsInStrip: Bool { placement == .strip || placement == .everywhere }

    /// Whether it can run on every one of `shots`. An action that cannot take the whole selection
    /// is disabled rather than run on the part it can.
    func applies(to shots: [Screenshot]) -> Bool { unavailableReason(for: shots) == nil }

    /// Why it cannot run on `shots`, in the words a disabled row's tooltip shows; nil when it can.
    func unavailableReason(for shots: [Screenshot]) -> String? {
        if !shots.allSatisfy({ kinds.contains($0.kind) }) {
            return kinds.contains(.image) ? "Screenshots only" : "Recordings only"
        }
        if shots.count < minimumCount { return "Select \(minimumCount) or more" }
        return nil
    }
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
    /// Hands each recording to the app macOS opens it with, QuickTime Player unless the user chose another.
    func open(_ shots: [Screenshot])
}
