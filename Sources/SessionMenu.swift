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

    /// What one session's row says.
    struct Row: Equatable, Identifiable {
        let destination: AgentDestination
        var id: String { destination.id }
        /// The herdr tab's label without its repository prefix, else the session's name, with a
        /// suffix when another session in the group has the same title, unless it is the one row the
        /// suffix leaves plain.
        let title: String
        /// Clone, worktree, branch and goal, or the path from home and goal, joined by " · ". The row
        /// does not draw them; its tooltip shows them and search looks through them.
        let details: String
        /// What the row says at its right edge: working, or when the session was last active, or none.
        let activity: Activity?
        /// The title, the details, then the repository, one to a line.
        let tooltip: String
    }

    /// The rows under one header, in rank order.
    struct Group: Equatable {
        /// The repository's name, or with another repository of that name, its remote's owner and
        /// name or its path from home (`Filer`); or `otherFolders`.
        let header: String
        /// Identifies the group across menus (`Filer.Filing.key`).
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
        /// Each session's place in the order the menu shows it, from 0, by id: the top rows as they
        /// stand, then the rest of `everyone`. What search orders its groups by.
        let rank: [String: Int]
        /// The rows from top to bottom, which is also live ink's Tab order after the responder.
        var topRows: [Row] { top.flatMap(\.rows) }
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
    /// not depend on which part it is in. `targetNotFirst` is Send's: `destination` is where the
    /// bar already sends, so the first row, which Return picks, is the likeliest other session. When
    /// `destination` would be first it trades places with the second, and the first row's group
    /// leads even when it is Other folders.
    static func menu(_ listed: [AgentDestination], destination: AgentDestination?, count: Int = 5,
                     targetNotFirst: Bool = false, now: Date = Date()) -> Menu {
        let active = ranked(listed, now: now)
        let running = active.filter { !$0.startsProcess }
        var top = Array((running.isEmpty ? active : running).prefix(count))
        if let destination, !top.contains(where: { $0.id == destination.id }) {
            top = Array(top.prefix(count - 1)) + [active.first { $0.id == destination.id } ?? destination]
        }
        let targetIsFirst = targetNotFirst && top.count > 1 && top[0].id == destination?.id
        if targetIsFirst { top.swapAt(0, 1) }
        let shown = Set(top.map(\.id))
        let everyone = including(destination, in: active)
        let receiving = everyone.filter { !$0.startsProcess }
        let filer = Filer(everyone)
        let rows = filer.rows(now: now)
        let topGroups = groups(top, filer, rows, leadFirst: targetNotFirst)
        let first = topGroups.map(\.key)
        let projects = receiving.contains { !shown.contains($0.id) } ? groups(receiving, filer, rows, headersFirst: first) : []
        let shownOrder = top + everyone.filter { !shown.contains($0.id) }
        return Menu(top: topGroups, projects: projects, everyone: groups(everyone, filer, rows, headersFirst: first),
                    rank: Dictionary(shownOrder.enumerated().map { ($1.id, $0) }) { first, _ in first })
    }

    /// `destination`'s row among `listed`, as the destination control and live ink's target button
    /// show it. `listed` is what their menu is built from (`DestinationChoice.Answer.sessions`), the
    /// rows that start a session included, since the main clone and the suffix that tells start rows
    /// apart are decided over all of them. A session that is not running is titled by its project,
    /// which its menu row leaves to the header above it; the tooltip keeps the menu row's words.
    /// When another such session would read the same, the menu row's suffix follows.
    static func row(of destination: AgentDestination, among listed: [AgentDestination], now: Date = Date()) -> Row {
        let everyone = including(destination, in: ranked(listed, now: now))
        let filer = Filer(everyone)
        let row = filer.rows(now: now)[destination.id]!
        guard let title = startTitle(of: destination) else { return row }
        let shared = everyone.contains { $0.id != destination.id && startTitle(of: $0)?.lowercased() == title.lowercased() }
        let suffix = shared ? filer.titleSuffixes()[destination.id] : nil
        return Row(destination: row.destination, title: suffix.map { "\(title) (\($0))" } ?? title, details: row.details,
                   activity: row.activity, tooltip: row.tooltip)
    }

    private static func startTitle(of session: AgentDestination) -> String? {
        switch session.start {
        case .resume: return lastSession(in: session.project)
        case .new: return newSession(in: session.project)
        case nil: return nil
        }
    }

    /// The sessions every row is worded over: the active ones, and `destination` when it is not among
    /// them, after the running ones and, unless it starts a session too, before the rows that start one.
    private static func including(_ destination: AgentDestination?, in active: [AgentDestination]) -> [AgentDestination] {
        guard let destination, !active.contains(where: { $0.id == destination.id }) else { return active }
        var everyone = active
        let firstStart = destination.startsProcess ? nil : active.firstIndex(where: \.startsProcess)
        everyone.insert(destination, at: firstStart ?? active.endIndex)
        return everyone
    }

    /// Running session `id` as live ink's note lists `candidates`, and the title a card sent to it
    /// shows, as the note's target words it. Nil when the note does not list it.
    static func noteSession(_ id: String, among candidates: DestinationChoice.Candidates) -> (destination: AgentDestination, title: String)? {
        let note = DestinationChoice.choose(candidates, for: .liveNote(.remembered(nil)))
        guard let session = note.list.first(where: { $0.id == id }) else { return nil }
        return (session, cardTitle(of: row(of: session, among: note.sessions)))
    }

    /// What the sent card calls `row`'s session: the row's title, or the project of a session Send
    /// starts, which the row titles by what sending to it does.
    static func cardTitle(of row: Row) -> String {
        row.destination.startsProcess ? row.destination.project : row.title
    }

    // MARK: Groups

    private static func groups(_ sessions: [AgentDestination], _ filer: Filer, _ rows: [String: Row],
                               headersFirst: [String] = [], leadFirst: Bool = false) -> [Group] {
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
        let lead = leadFirst ? Array(filled.prefix(1)) : []
        let rest = filled.dropFirst(lead.count)
        let keys = lead + rest.filter { $0 != otherFolders } + rest.filter { $0 == otherFolders }
        return keys.map { Group(header: headers[$0] ?? $0, key: $0, rows: members[$0] ?? []) }
    }
}
