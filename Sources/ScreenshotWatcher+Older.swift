import Foundation

extension ScreenshotWatcher {
    /// Where a file falls in the stack's order: newest first, ties falling to the name, as `recent`
    /// orders them. It keeps the date the index held, so a place still sorts after its file is gone.
    struct Place: Comparable, Sendable {
        let date: Date
        let name: String

        /// `a < b` when `a` comes first in the stack's order, which is the newer of the two.
        static func < (a: Place, b: Place) -> Bool { a.date != b.date ? a.date > b.date : a.name > b.name }
    }

    /// The files after `place` in the stack's order, at most `limit` of them, and whether more
    /// follow. With no `place`, the files after the oldest of `shown` that the index holds, or every
    /// file when it holds none of them. A name in `shown` is never answered.
    static func older(from files: [String: Date], after place: Place?, shown: Set<String>,
                      limit: Int) -> (places: [Place], more: Bool) {
        let start = place ?? files.lazy.filter { shown.contains($0.key) }.map { Place(date: $0.value, name: $0.key) }.max()
        var places = files.lazy.map { Place(date: $0.value, name: $0.key) }
            .filter { place in !shown.contains(place.name) && start.map { $0 < place } ?? true }
            .sorted()
        let more = places.count > limit
        if more { places.removeLast(places.count - limit) }
        return (places, more)
    }

    /// `older(from:after:shown:limit:)` on the index, as keys. It sorts the whole index, so it is
    /// for a background queue: the main thread never lists the folder.
    func older(after place: Place?, shown: Set<ScreenshotKey>, limit: Int) -> (shots: [(key: ScreenshotKey, place: Place)], more: Bool) {
        let names = Set(shown.filter { $0 == ScreenshotKey(folder: folder, name: $0.name) }.map(\.name))
        let found = Self.older(from: candidates(), after: place, shown: names, limit: limit)
        return (found.places.map { (ScreenshotKey(folder: folder, name: $0.name), $0) }, found.more)
    }
}
