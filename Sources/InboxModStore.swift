import Foundation

/// What the inbox mod knows about a Claude Code session: the goal it wrote for it and whether it
/// has an open question for the person. The mod keeps this in a file of its own under
/// `~/.claude/plugins/store`, which is private to the mod and may change, so this is the one place
/// that reads it, and a file that is missing, unreadable or different means no goal and no badge.
enum InboxModStore {
    struct Entry: Equatable, Sendable {
        var goal: String?
        /// The mod has an open question for the person in this session.
        var needsYou: Bool
    }

    /// The store file's name up to its hash: `inbox_inline-<hash>.json`.
    static let filePrefix = "inbox_inline-"

    /// Each session's entry by session id, from the newest store file in `folder`. Empty when there is none.
    static func entries(in folder: URL?) -> [String: Entry] {
        guard let folder, let file = storeFile(in: folder) else {
            complain("no store file under \(folder?.path ?? "a test launch's home")")
            return [:]
        }
        let version = Version(file)
        if let cached = cached(version) { return cached }
        guard let data = try? Data(contentsOf: file),
              let store = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            complain("cannot read \(file.lastPathComponent)")
            return [:]
        }
        let found = entries(in: store)
        remember(found, as: version)
        return found
    }

    /// A store file as it was last read: the store is 1.2 MB and every editor opening asks for it,
    /// so it is parsed again only when its path, modification date or size changes.
    private struct Version: Equatable {
        let path: String
        let modified: Date
        let size: Int

        init(_ file: URL) {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            path = file.path
            modified = values?.contentModificationDate ?? .distantPast
            size = values?.fileSize ?? -1
        }
    }

    private nonisolated(unsafe) static var parsed: (version: Version, entries: [String: Entry])?

    private static func cached(_ version: Version) -> [String: Entry]? {
        lock.lock(); defer { lock.unlock() }
        return parsed?.version == version ? parsed?.entries : nil
    }

    private static func remember(_ entries: [String: Entry], as version: Version) {
        lock.lock(); defer { lock.unlock() }
        parsed = (version, entries)
    }

    /// The entries in a parsed store: its `s:<session id>` keys.
    static func entries(in store: [String: Any]) -> [String: Entry] {
        var found: [String: Entry] = [:]
        for (key, value) in store where key.hasPrefix("s:") {
            guard let ledger = (value as? [String: Any])?["ledger"] as? [String: Any] else { continue }
            let goal = ((ledger["card"] as? [String: Any])?["goal"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let asks = (ledger["items"] as? [[String: Any]] ?? []).contains { !(($0["ask"] as? String) ?? "").isEmpty }
            guard goal?.isEmpty == false || asks else { continue }
            found[String(key.dropFirst(2))] = Entry(goal: goal?.isEmpty == false ? goal : nil, needsYou: asks)
        }
        return found
    }

    private static func storeFile(in folder: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix(filePrefix) && $0.pathExtension == "json" }
            .max { modified($0) < modified($1) }
    }

    private static func modified(_ file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Where the store is for this launch: under Claude Code's folder as the rest of the app finds
    /// it, so a test launch (`VIGNETTE_SETTINGS`) never reads the person's own.
    static func folder(home: String = NSHomeDirectory(), environment: [String: String] = ProcessInfo.processInfo.environment,
                       personHome: String = AgentPlugin.personHome.path) -> URL? {
        AgentPlugin.roots(home: URL(fileURLWithPath: home), environment: environment, personHome: URL(fileURLWithPath: personHome))
            .first { AgentPlugin.client(of: $0, environment: environment) == .claude }?
            .appendingPathComponent("plugins/store")
    }

    /// Reads the store for this launch.
    static func read() -> [String: Entry] { entries(in: folder()) }

    private nonisolated(unsafe) static var complained = false
    private static let lock = NSLock()

    /// Logs the first failure only: the listing runs at every opening.
    private static func complain(_ why: String) {
        lock.lock(); defer { lock.unlock() }
        guard !complained else { return }
        complained = true
        Log.write("[sessions] inbox mod store not read: \(why)")
    }
}
