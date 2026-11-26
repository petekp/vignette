import Foundation

extension ScreenshotWatcher {
    /// Sorted names that appeared and disappeared since the last scan.
    static func diff(known: Set<String>, current: Set<String>) -> (added: [String], removed: [String]) {
        (current.subtracting(known).sorted(), known.subtracting(current).sorted())
    }

    /// Names that disappeared paired with names that appeared in the same listing, when the file's
    /// identity is the same. A pair counts only when the match is one to one: two removed files with
    /// one identity (a hard link) leave every name in it a removal or an arrival.
    static func renames(removed: Set<String>, added: Set<String>, before: [String: FileIdentity],
                        after: [String: FileIdentity]) -> [(from: String, to: String)] {
        var gone: [FileIdentity: [String]] = [:]
        for name in removed.sorted() { before[name].map { gone[$0, default: []].append(name) } }
        var arrived: [FileIdentity: [String]] = [:]
        for name in added.sorted() { after[name].map { arrived[$0, default: []].append(name) } }
        return gone.compactMap { identity, from in
            guard from.count == 1, let to = arrived[identity], to.count == 1 else { return nil }
            return (from: from[0], to: to[0])
        }
        .sorted { $0.from < $1.from }
    }
}
