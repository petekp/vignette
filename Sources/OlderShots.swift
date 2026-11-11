import Foundation

/// Brings the screenshots older than the recent stack's oldest card into the column, a chunk at a
/// time, as the person nears the top of it. The folder's order is read and each file's header is
/// looked up on a background queue, and the person's filter runs on the main thread, so a chunk
/// never holds up a frame of the scroll. Opening the stack again starts over (`reset`).
@MainActor
final class OlderShots {
    typealias Place = ScreenshotWatcher.Place
    /// The files after a place in the stack's order, as `ScreenshotWatcher.older` answers. Called
    /// on the background queue. Nil while there is no watcher.
    var listing: () -> (@Sendable (Place?, Set<ScreenshotKey>, Int) -> (shots: [(key: ScreenshotKey, place: Place)], more: Bool))? = { nil }
    /// Whether the person may act on a file, as `recentShots` filters: an agent's reply that has not
    /// been published is not shown. Main thread.
    var isShown: (ScreenshotKey) -> Bool = { _ in true }

    /// A chunk is being read.
    private(set) var loading = false
    /// The last chunk reached the oldest file in the folder: nothing more loads until a reset.
    private(set) var reachedOldest = false
    /// How many cards the chunks brought in since the stack opened.
    private(set) var added = 0
    /// The last file a chunk took, which the next one starts after.
    private var after: Place?
    private var generation = 0
    private var waiting: [() -> Void] = []
    private static let queue = DispatchQueue(label: "\(Identity.bundleID).older-shots", qos: .userInitiated)

    /// How many cards the column keeps when a new one joins it: `recentCount` until a chunk has
    /// come in, and every card after, since the oldest of them are the ones the person scrolled to.
    var columnLimit: Int { added > 0 ? .max : Settings.shared.data.recentCount }

    var state: [String: Any] { ["loading": loading, "reachedOldest": reachedOldest, "added": added] }

    /// The stack shows a new column. A chunk still being read for the old one is dropped.
    func reset() {
        generation += 1
        loading = false
        reachedOldest = false
        added = 0
        after = nil
        waiting = []
    }

    /// Runs `run` once the next chunk is in the column, or never if the stack shows a new column first.
    func afterChunk(_ run: @escaping () -> Void) { waiting.append(run) }

    /// Reads the next `limit` files after the oldest of `shown` and hands them to `deliver` with
    /// their headers, on the main thread. Nothing happens while a chunk is being read or once the
    /// oldest file was reached. `deliver` gets an empty list when nothing after `shown` is shown.
    func load(shown: Set<ScreenshotKey>, limit: Int, deliver: @escaping @MainActor @Sendable ([(Screenshot, Thumbnailer.Lookup)]) -> Void) {
        guard !loading, !reachedOldest, limit > 0, let list = listing() else { return }
        loading = true
        let generation = generation, after = after
        // Twice the chunk and a margin, so a few files the filter hides do not cut a chunk short.
        let asked = limit * 2 + 16
        Self.queue.async {
            let found = list(after, shown, asked)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.filter(found, limit: limit, generation: generation, deliver: deliver) }
            }
        }
    }

    private func filter(_ found: (shots: [(key: ScreenshotKey, place: Place)], more: Bool), limit: Int, generation: Int,
                        deliver: @escaping @MainActor @Sendable ([(Screenshot, Thumbnailer.Lookup)]) -> Void) {
        guard generation == self.generation else { return }
        var taken: [ScreenshotKey] = [], last: Place?
        var rest = found.shots[...]
        while taken.count < limit, let next = rest.popFirst() {
            last = next.place
            if isShown(next.key) { taken.append(next.key) }
        }
        let more = found.more || rest.contains { isShown($0.key) }
        self.after = last ?? self.after
        let keys = taken
        Self.queue.async {
            let looked = keys.map { (Screenshot(key: $0), Thumbnailer.lookUp($0.url)) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard generation == self.generation else { return }
                    self.loading = false
                    if !more { self.reachedOldest = true }
                    deliver(looked)
                    let waiting = self.waiting
                    self.waiting = []
                    waiting.forEach { $0() }
                }
            }
        }
    }

    /// The chunk just delivered put `count` cards in the column.
    func took(_ count: Int) { added += count }
}
