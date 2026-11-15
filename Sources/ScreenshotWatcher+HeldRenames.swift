extension ScreenshotWatcher {
    /// Renames a scan paired, held until a delivery that covers that scan takes them. A delivery
    /// that finds the directory changed under it delivers nothing, and the next one takes them.
    struct HeldRenames {
        private var held: [(scan: Int, from: String, to: String)] = []

        /// Holds the pairs from scan `scan`, except those whose old name has an arrival not yet
        /// delivered: the app never heard of that name, so it leaves as a removal and the new name
        /// arrives. Answers the pairs it held.
        @discardableResult
        mutating func hold(_ pairs: [(from: String, to: String)], scan: Int,
                           undelivered: Set<String>) -> [(from: String, to: String)] {
            let kept = pairs.filter { !undelivered.contains($0.from) }
            held += kept.map { (scan: scan, from: $0.from, to: $0.to) }
            return kept
        }

        /// The renames held for scans up to `scan`, and the names in `left` that did not leave by
        /// one of those renames.
        mutating func deliver(through scan: Int, left: [String]) -> (renames: [(from: String, to: String)], removed: [String]) {
            let renames = held.filter { $0.scan <= scan }.map { (from: $0.from, to: $0.to) }
            held.removeAll { $0.scan <= scan }
            let renamedFrom = Set(renames.map(\.from))
            return (renames, left.filter { !renamedFrom.contains($0) })
        }
    }

    /// The candidates in `present` that `current` no longer lists, sorted. A folder of a few
    /// thousand screenshots makes this milliseconds of string hashing, so a scan works it out on
    /// the watcher's queue for its delivery.
    static func left(_ present: Set<String>, for current: Set<String>) -> [String] {
        present.subtracting(current).filter(isCandidate).sorted()
    }
}
