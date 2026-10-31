import Foundation

/// How the recent stack forms over a column already on screen: every card showing one of the
/// recent screenshots stays, and only the others enter.
struct StackEntrance: Equatable {
    /// For each recent screenshot, newest first: the card on screen that shows it, or nil for one that enters.
    let kept: [UUID?]

    init(onScreen: [(key: ScreenshotKey, id: UUID)], recent: [ScreenshotKey]) {
        kept = recent.map { key in onScreen.first { $0.key == key }?.id }
    }

    /// For each recent screenshot, its place in the slide-in's stagger, counting the entering cards
    /// from 0, newest first; nil for a card that stays.
    var ranks: [Int?] {
        var next = 0
        return kept.map { id in
            guard id == nil else { return nil }
            defer { next += 1 }
            return next
        }
    }
}
