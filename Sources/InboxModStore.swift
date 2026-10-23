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
        guard let data = try? Data(contentsOf: file),
              let store = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            complain("cannot read \(file.lastPathComponent)")
            return [:]
        }
        return entries(in: store)
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

    /// Where the store is for this launch. A test launch (`VIGNETTE_SETTINGS`) reads only a scratch
    /// home (`CFFIXED_USER_HOME`), never the person's own.
    static func folder(home: String = NSHomeDirectory(), environment: [String: String] = ProcessInfo.processInfo.environment,
                       personHome: String = AgentPlugin.personHome.path) -> URL? {
        let isTest = environment["VIGNETTE_SETTINGS"].map { !$0.isEmpty } ?? false
        if isTest && home == personHome { return nil }
        let claude = isTest ? URL(fileURLWithPath: home).appendingPathComponent(".claude")
            : AgentPlugin.root(of: .claude, home: URL(fileURLWithPath: home), environment: environment)
        return claude.appendingPathComponent("plugins/store")
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
