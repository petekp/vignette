import Foundation

/// Which sessions the session menu offers, in what order, under which repository, and what each
/// row says. Pure: the menus of the editor toolbar and of live ink's note, the destination
/// control, live ink's target button and the sent card all read it.
///
/// The order is the sessions the person sent to in the last `sendWindow`, newest send first, then
/// the rest by when the agent last worked. Five are kept, with the destination among them, and then
/// grouped under their repository. Below them, one submenu per repository lists all of its running
/// sessions. The rows that start a session are found by search, unless no session is running.
enum SessionMenu {
    /// A send older than this no longer ranks a session ahead of the others.
    static let sendWindow: TimeInterval = 4 * 60 * 60

    static let otherFolders = "Other folders"
    static let continueLast = "Continue last session"
    static let newSession = "New session"
    static func lastSession(in project: String) -> String { "Last session in \(project)" }
    static func newSession(in project: String) -> String { "New session in \(project)" }
    static let working = "Working"

    /// What one session's row says.
    struct Row: Equatable, Identifiable {
        let destination: AgentDestination
        var id: String { destination.id }
        /// The herdr tab's label without its repository prefix, else the session's name, with a
        /// suffix when another session in the group has the same title.
        let title: String
        /// Worktree, branch and goal, or the path from home and goal, joined by " · ".
        let subtitle: String
        /// "Working" while the session is busy, else when it was last active ("2 hr ago"), or none.
        let badge: String?
        /// The title, the second line, then the repository.
        let tooltip: String
    }

    /// The rows under one header, in rank order.
    struct Group: Equatable {
        /// The repository's name, with its parent folder when another repository has the same
        /// name; or `otherFolders`.
        let header: String
        /// Identifies the group across menus: the main checkout's path, a bare repository name when
        /// the path is unknown, or `otherFolders`.
        let key: String
        let rows: [Row]
    }

    /// The five rows the menu shows, grouped, and the project submenus below them: one group per
    /// header, in the headers' order with Other folders last, holding every running session of that
    /// project, the top rows included. Empty when the top rows already hold every running session.
    struct Menu: Equatable {
        let top: [Group]
        let projects: [Group]
        /// Every session on offer by project, the running ones first: what search looks through.
        let everyone: [Group]
        /// The rows from top to bottom, which is also live ink's Tab order after the responder.
        var topRows: [Row] { top.flatMap(\.rows) }
    }

    /// The groups of `groups` whose rows match `query`, in the same order, except that a group with a
    /// running session comes before one of rows that start a session, so Return never starts one
    /// while a running session matches. A row matches when every word of the query is found,
    /// ignoring case and accents, in its title, its second line or its group's header. A query with
    /// no words matches every row.
    static func matching(_ query: String, in groups: [Group]) -> [Group] {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        let found = words.isEmpty ? groups : groups.compactMap { group in
            let rows = group.rows.filter { row in
                let text = fold([row.title, row.subtitle, group.header].joined(separator: " "))
                return words.allSatisfy { text.contains($0) }
            }
            return rows.isEmpty ? nil : Group(header: group.header, key: group.key, rows: rows)
        }
        let startsOnly = { (group: Group) in group.rows.allSatisfy(\.destination.startsProcess) }
        return found.filter { !startsOnly($0) } + found.filter(startsOnly)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    // MARK: Order

    /// A project's Continue before its New.
    private static func startOrder(_ start: SessionStart) -> Int {
        if case .resume = start { return 0 }
        return 1
    }

    /// Active sessions in rank order: sent to in the last `sendWindow` first, newest send first,
    /// then by `DestinationChoice.newestFirst`. Sessions that are not running come after every
    /// running one, a project's Continue before its New: sending to one starts a process, so it
    /// never takes a row from a session that can receive now.
    static func ranked(_ listed: [AgentDestination], now: Date) -> [AgentDestination] {
        func recentSend(_ session: AgentDestination) -> Date? {
            session.lastSent.flatMap { now.timeIntervalSince($0) < sendWindow ? $0 : nil }
        }
        return listed.filter { $0.isActive(now: now) }.sorted { a, b in
            if a.startsProcess != b.startsProcess { return !a.startsProcess }
            if a.startsProcess {
                let (x, y) = (a.lastUsed ?? .distantPast, b.lastUsed ?? .distantPast)
                if x != y { return x > y }
                let (f, g) = (a.start?.folder ?? "", b.start?.folder ?? "")
                if f != g { return f < g }
                return a.start.map(Self.startOrder) ?? 0 < b.start.map(Self.startOrder) ?? 0
            }
            switch (recentSend(a), recentSend(b)) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return DestinationChoice.newestFirst(a, b)
            }
        }
    }

    /// The menu for `listed`. The first `count` ranked running sessions are kept, and `destination`
    /// takes the last of them when it is not among them (it is nil when live ink's note is on the
    /// responder, and then nothing is forced in). With none running, the rows that start a session
    /// are ranked in their place, since starting one is all the menu can do then. `projects` files
    /// every running session by project once any is left out of the top rows. A session's row does
    /// not depend on which part it is in.
    static func menu(_ listed: [AgentDestination], destination: AgentDestination?, count: Int = 5, now: Date = Date()) -> Menu {
        let active = ranked(listed, now: now)
        let running = active.filter { !$0.startsProcess }
        var top = Array((running.isEmpty ? active : running).prefix(count))
        if let destination, !top.contains(where: { $0.id == destination.id }) {
            top = Array(top.prefix(count - 1)) + [active.first { $0.id == destination.id } ?? destination]
        }
        let shown = Set(top.map(\.id))
        let everyone = including(destination, in: active)
        let receiving = everyone.filter { !$0.startsProcess }
        let filer = Filer(everyone)
        let rows = filer.rows(now: now)
        let topGroups = groups(top, filer, rows)
        let first = topGroups.map(\.key)
        let projects = receiving.contains { !shown.contains($0.id) } ? groups(receiving, filer, rows, headersFirst: first) : []
        return Menu(top: topGroups, projects: projects, everyone: groups(everyone, filer, rows, headersFirst: first))
    }

    /// `destination`'s row among `listed`, as the destination control and live ink's target button
    /// show it. A session that is not running is titled by its project, which its menu row leaves to
    /// the header above it; the tooltip keeps the menu row's words.
    static func row(of destination: AgentDestination, among listed: [AgentDestination], now: Date = Date()) -> Row {
        let everyone = including(destination, in: ranked(listed, now: now))
        let row = Filer(everyone).rows(now: now)[destination.id]!
        let title: String
        switch destination.start {
        case .resume: title = lastSession(in: destination.project)
        case .new: title = newSession(in: destination.project)
        case nil: return row
        }
        return Row(destination: row.destination, title: title, subtitle: row.subtitle, badge: row.badge, tooltip: row.tooltip)
    }

    /// The sessions every row is worded over: the active ones, and `destination` when it is not among them.
    private static func including(_ destination: AgentDestination?, in active: [AgentDestination]) -> [AgentDestination] {
        guard let destination, !active.contains(where: { $0.id == destination.id }) else { return active }
        return active + [destination]
    }

    /// What the sent card calls `row`'s session: the row's title, or the project of a session Send
    /// starts, which the row titles by what sending to it does.
    static func cardTitle(of row: Row) -> String {
        row.destination.startsProcess ? row.destination.project : row.title
    }

    // MARK: Groups

    private static func groups(_ sessions: [AgentDestination], _ filer: Filer, _ rows: [String: Row],
                               headersFirst: [String] = []) -> [Group] {
        var order: [String] = headersFirst
        var headers: [String: String] = [:]
        var members: [String: [Row]] = [:]
        for session in sessions {
            let filing = filer.filing(session)
            guard let row = rows[session.id] else { continue }
            if members[filing.key] == nil {
                if !order.contains(filing.key) { order.append(filing.key) }
                headers[filing.key] = filing.header
            }
            members[filing.key, default: []].append(row)
        }
        let filled = order.filter { members[$0] != nil }
        let keys = filled.filter { $0 != otherFolders } + filled.filter { $0 == otherFolders }
        return keys.map { Group(header: headers[$0] ?? $0, key: $0, rows: members[$0] ?? []) }
    }

    /// How every session on offer is filed and worded, decided over all of them so that a session
    /// reads the same whichever menu it is in.
    private struct Filer {
        let sessions: [AgentDestination]
        private let roots: [String]
        private let headers: [String: String]
        private let filings: [String: (key: String, header: String)]

        init(_ sessions: [AgentDestination]) {
            self.sessions = sessions
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
            filings = Dictionary(sessions.map { ($0.id, Self.filing(of: $0, roots: rootsFound, headers: headers)) }) { first, _ in first }
        }

        /// The group key and header for a session on offer.
        func filing(_ session: AgentDestination) -> (key: String, header: String) {
            filings[session.id]!
        }

        private static func filing(of session: AgentDestination, roots: [String], headers: [String: String]) -> (key: String, header: String) {
            guard case .repository(let name, let root, _, _) = session.place else { return (SessionMenu.otherFolders, SessionMenu.otherFolders) }
            if let root { return (root, headers[root] ?? name) }
            // Known by name only: it joins the one checkout of that name, when there is exactly one.
            let same = roots.filter { ($0 as NSString).lastPathComponent == name }
            if same.count == 1 { return (same[0], headers[same[0]] ?? name) }
            return ("name:\(name)", name)
        }

        /// Every session's row. Sessions with equal titles in one group get a suffix.
        func rows(now: Date) -> [String: Row] {
            var byGroup: [String: [AgentDestination]] = [:]
            for session in sessions { byGroup[filing(session).key + "\n" + Self.titleParts(of: session).title.lowercased(), default: []].append(session) }
            var suffixes: [String: String] = [:]
            for members in byGroup.values where members.count > 1 {
                for (id, suffix) in Self.suffixes(for: members) { suffixes[id] = suffix }
            }
            var rows: [String: Row] = [:]
            for session in sessions {
                rows[session.id] = Self.row(for: session, titleSuffix: suffixes[session.id], now: now, header: filing(session).header)
            }
            return rows
        }

        /// What tells apart sessions with one title: the first of the herdr tab, the worktree and the
        /// branch that every one of them has and no two share; else "#1", "#2" by when they started.
        static func suffixes(for members: [AgentDestination]) -> [String: String] {
            let attributes: [(AgentDestination) -> String?] = [
                { $0.hostLabel }, { if case .repository(_, _, let worktree, _) = $0.place { return worktree } else { return nil } }, { $0.branch },
            ]
            for attribute in attributes {
                let values = members.map { attribute($0)?.trimmingCharacters(in: .whitespaces) }
                guard values.allSatisfy({ $0?.isEmpty == false }),
                      Set(values.compactMap { $0?.lowercased() }).count == members.count else { continue }
                return Dictionary(uniqueKeysWithValues: zip(members.map(\.id), values.compactMap { $0 }))
            }
            let ordered = members.sorted { a, b in
                switch (a.started, b.started) {
                case let (x?, y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.id < b.id
                }
            }
            return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, "#\($0 + 1)") })
        }

        // MARK: Words

        /// The herdr tab's label without a leading "<repository>:" and the title it makes, which is
        /// that label, else the session's name. A session that is not running is titled by what
        /// sending to it does.
        static func titleParts(of session: AgentDestination) -> (tab: String?, title: String) {
            switch session.start {
            case .resume: return (nil, SessionMenu.continueLast)
            case .new: return (nil, SessionMenu.newSession)
            case nil: break
            }
            let tab = shortTab(of: session)
            return (tab, tab ?? session.name)
        }

        static func shortTab(of session: AgentDestination) -> String? {
            guard var label = session.hostLabel?.trimmingCharacters(in: .whitespaces), !label.isEmpty else { return nil }
            if case .repository(let name, _, _, _) = session.place,
               label.lowercased().hasPrefix(name.lowercased() + ":") {
                label = String(label.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
            }
            return label.isEmpty ? nil : label
        }

        static func row(for session: AgentDestination, titleSuffix: String?, now: Date, header: String) -> Row {
            let (tab, baseTitle) = titleParts(of: session)
            let title = titleSuffix.map { "\(baseTitle) (\($0))" } ?? baseTitle
            let named = session.hasOwnName && session.name.lowercased() != baseTitle.lowercased() ? session.name : nil
            let purpose = session.goal ?? named
            let lastActive = session.lastUsed.map { age(since: $0, now: now) }
            var parts: [String?]
            // The time the badge shows, which the tooltip keeps on the second line.
            var tooltipAge: String?
            if let start = session.start {
                // Where it would run, then which session it continues.
                parts = placeParts(session, withSubfolder: true)
                if case .resume = start {
                    parts.append(session.hasOwnName ? session.name : nil)
                    tooltipAge = lastActive
                }
            } else if tab == nil && purpose == nil {
                // No herdr tab and nothing from the inbox mod: the session's name leads, and its place follows.
                parts = placeParts(session, withSubfolder: true)
                tooltipAge = lastActive
            } else {
                parts = placeParts(session, withSubfolder: false)
                parts.append(purpose)
            }
            let line = distinct(parts).joined(separator: " · ")
            let tooltip = [title, distinct(parts + [tooltipAge]).joined(separator: " · "), header].filter { !$0.isEmpty }.joined(separator: "\n")
            return Row(destination: session, title: title, subtitle: line, badge: badge(for: session, lastActive: lastActive), tooltip: tooltip)
        }

        /// "Working" while the session is busy, else when it was last active. A New session row has
        /// none: its time would be the project's last session's, not its own.
        static func badge(for session: AgentDestination, lastActive: String?) -> String? {
            if session.turn == .busy { return SessionMenu.working }
            if case .new? = session.start { return nil }
            return lastActive
        }

        /// Worktree and branch, or the path from home, with the subfolder when no herdr tab or goal
        /// says more.
        private static func placeParts(_ session: AgentDestination, withSubfolder: Bool) -> [String?] {
            switch session.place {
            case .repository(_, _, let worktree, let subfolder):
                return [worktree] + (withSubfolder ? [subfolder] : []) + [session.branch]
            case .folder(let path): return [path]
            case .none: return []
            }
        }

        /// Parts without the empty ones and without one that repeats an earlier one.
        private static func distinct(_ parts: [String?]) -> [String] {
            var seen: [String] = []
            for part in parts.compactMap({ $0?.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
                if !seen.contains(where: { $0.lowercased() == part.lowercased() }) { seen.append(part) }
            }
            return seen
        }

        static func age(since date: Date, now: Date) -> String {
            let minutes = Int(now.timeIntervalSince(date) / 60)
            if minutes < 1 { return "now" }
            if minutes < 60 { return "\(minutes) min ago" }
            if minutes < 24 * 60 { return "\(minutes / 60) hr ago" }
            let days = minutes / (24 * 60)
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }
}
