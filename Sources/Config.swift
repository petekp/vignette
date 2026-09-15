import AppKit

/// Product behavior that lives in code. Per-machine knobs (folder, counts, hotkey, backdrop) live in
/// ~/.config/shotnote/settings.json; see Settings.swift.
enum Config {
    /// Appended to the original file name when an annotated copy is saved next to it.
    static let annotatedSuffix = "-annotated"

    /// Everything you can do to screenshots. Each action is a hover button on a card, an entry in the
    /// selection bar, a keyboard shortcut inside the recent stack, and a `shotnote://<id>` URL, according
    /// to its `placement` and `key`. Actions always receive a list, oldest first.
    static let actions: [ShotAction] = [
        ShotAction(id: "copy", symbol: "doc.on.doc", label: "Copy", key: .init("c", [.command]),
                   placement: .everywhere) { shots, app in app.copyToClipboard(shots) },
        ShotAction(id: "annotate", symbol: "pencil.tip.crop.circle", label: "Annotate", key: .init("\r", []),
                   placement: .card, isDefault: true) { shots, app in if let last = shots.last { app.annotate(last) } },
        ShotAction(id: "paths", symbol: "text.quote", label: "Copy Paths", key: .init("c", [.command, .option]),
                   placement: .bar) { shots, app in app.copyPaths(shots) },
        ShotAction(id: "copy-annotated", symbol: "pencil.line", label: "Copy Annotated", key: .init("c", [.command, .shift]),
                   placement: .bar) { shots, app in app.copyAnnotated(shots) },
        ShotAction(id: "stitch", symbol: "rectangle.stack", label: "Stitch", key: .init("s", [.command]),
                   placement: .bar, minimumCount: 2) { shots, app in app.stitch(shots) },
        ShotAction(id: "trash", symbol: "trash", label: "Delete", key: .init("\u{7f}", [.command]),
                   placement: .everywhere) { shots, app in app.moveToTrash(shots) },
    ]

    static func action(id: String) -> ShotAction? { actions.first { $0.id == id } }
}

struct ShotAction {
    enum Placement { case card, bar, everywhere }
    struct Key: Equatable {
        let character: String
        let modifiers: NSEvent.ModifierFlags
        init(_ character: String, _ modifiers: NSEvent.ModifierFlags) { self.character = character; self.modifiers = modifiers }
    }

    let id: String
    let symbol: String      // SF Symbol name
    let label: String
    var key: Key? = nil     // shortcut while the recent stack has focus
    var placement: Placement = .everywhere
    var isDefault = false   // runs when a card is clicked outside selection mode
    var minimumCount = 1
    let run: ([Screenshot], Actions) -> Void

    var showsOnCard: Bool { placement != .bar }
    var showsInBar: Bool { placement != .card }
}

/// What an action can do. Implemented by AppDelegate.
protocol Actions: AnyObject {
    func copyToClipboard(_ shots: [Screenshot])
    func copyPaths(_ shots: [Screenshot])
    func annotate(_ shot: Screenshot)
    /// Exports each screenshot's draft (or uses the file as is when it has none) and copies the set.
    func copyAnnotated(_ shots: [Screenshot])
    func stitch(_ shots: [Screenshot])
    func moveToTrash(_ shots: [Screenshot])
}
