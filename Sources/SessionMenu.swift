import Foundation

/// Which sessions the session menu offers, in what order, and under which repository. The order
/// is the sessions the person sent to in the last `sendWindow`, newest send first, then the rest by
/// when the agent last worked. Five are kept, with the destination among them, and then grouped.
/// Pure: the menus of the editor toolbar and of live ink's note both read it.
enum SessionMenu {
    /// A send older than this no longer ranks a session ahead of the others.
    static let sendWindow: TimeInterval = 4 * 60 * 60

    /// The sessions under one header, in rank order.
    struct Group: Equatable {
        /// The repository's name, with its parent folder when another repository has the same name;
        /// or `otherFolders`.
        let header: String
        /// Identifies the group across menus: the main checkout's path, a bare repository name when
        /// the path is unknown, or `otherFolders`.
        let key: String
        let rows: [AgentDestination]
        var isOtherFolders: Bool { key == SessionMenu.otherFolders }
    }

    static let otherFolders = "Other folders"

    /// The five rows the menu shows and the sessions that go in its submenu, each grouped.
    struct Menu: Equatable {
        let top: [Group]
        let more: [Group]
    }

    /// Active sessions in rank order: sent to in the last `sendWindow` first, newest send first,
    /// then by `DestinationChoice.newestFirst`. `sends` is each session's newest hand-over time.
    static func ranked(_ listed: [AgentDestination], sends: [String: Date], now: Date) -> [AgentDestination] {
        func recentSend(_ session: AgentDestination) -> Date? {
            sends[session.id].flatMap { now.timeIntervalSince($0) < sendWindow ? $0 : nil }
        }
        return listed.filter { $0.isActive(now: now) }.sorted { a, b in
            switch (recentSend(a), recentSend(b)) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return DestinationChoice.newestFirst(a, b)
            }
        }
    }

    /// The menu for `listed`. The first `count` ranked sessions are kept, and `destination` takes the
    /// last of them when it is not among them (it is nil when live ink's note is on the responder,
    /// and then nothing is forced in). The sessions past those go to `more`. Each part is grouped
    /// the same way, and a session's group does not depend on which part it is in.
    static func menu(_ listed: [AgentDestination], sends: [String: Date], destination: AgentDestination?,
                     count: Int = 5, now: Date = Date()) -> Menu {
        let active = ranked(listed, sends: sends, now: now)
        var top = Array(active.prefix(count))
        if let destination, !top.contains(where: { $0.id == destination.id }) {
            top = Array(top.prefix(count - 1)) + [active.first { $0.id == destination.id } ?? destination]
        }
        let shown = Set(top.map(\.id))
        let more = active.filter { !shown.contains($0.id) }
        var everyone = active
        if let forced = top.last, !active.contains(where: { $0.id == forced.id }) { everyone.append(forced) }
        let identities = Identities(everyone)
        return Menu(top: groups(top, identities), more: groups(more, identities))
    }

    // MARK: Groups

    /// How every session on offer is filed, decided over all of them so that a session files the
    /// same way whichever menu it is in.
    private struct Identities {
        private let roots: [String]
        private let headers: [String: String]

        init(_ sessions: [AgentDestination]) {
            var named: [String: Set<String>] = [:]
            var rootsFound: [String] = []
            for session in sessions {
                guard case .repository(let name, let root?, _, _) = session.place else { continue }
                named[name, default: []].insert(root)
                if !rootsFound.contains(root) { rootsFound.append(root) }
            }
            roots = rootsFound
            var headers: [String: String] = [:]
            for (name, paths) in named {
                for path in paths {
                    let parent = (path as NSString).deletingLastPathComponent
                    headers[path] = paths.count > 1 ? "\((parent as NSString).lastPathComponent)/\(name)" : name
                }
            }
            self.headers = headers
        }

        /// The group key and header for a session.
        func filing(_ session: AgentDestination) -> (key: String, header: String) {
            guard case .repository(let name, let root, _, _) = session.place else { return (SessionMenu.otherFolders, SessionMenu.otherFolders) }
            if let root { return (root, headers[root] ?? name) }
            // Known by name only: it joins the one checkout of that name, when there is exactly one.
            let same = roots.filter { ($0 as NSString).lastPathComponent == name }
            if same.count == 1 { return (same[0], headers[same[0]] ?? name) }
            return ("name:\(name)", name)
        }
    }

    /// Groups in the order of their first row, with Other folders last.
    private static func groups(_ rows: [AgentDestination], _ identities: Identities) -> [Group] {
        var order: [String] = []
        var headers: [String: String] = [:]
        var members: [String: [AgentDestination]] = [:]
        for row in rows {
            let filing = identities.filing(row)
            if members[filing.key] == nil { order.append(filing.key); headers[filing.key] = filing.header }
            members[filing.key, default: []].append(row)
        }
        let repositories = order.filter { $0 != otherFolders }
        let keys = repositories + order.filter { $0 == otherFolders }
        return keys.map { Group(header: headers[$0] ?? $0, key: $0, rows: members[$0] ?? []) }
    }
}
