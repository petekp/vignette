import Foundation

/// What each session's row says: its title and the suffix that tells equal titles apart, its
/// details, its tooltip and the words at its right.
extension SessionMenu.Filer {
    /// The suffix of each session whose title another in its group has.
    func titleSuffixes() -> [String: String] {
        var byGroup: [String: [AgentDestination]] = [:]
        for session in sessions { byGroup[filing(session).key + "\n" + Self.titleParts(of: session).title.lowercased(), default: []].append(session) }
        var suffixes: [String: String] = [:]
        for members in byGroup.values where members.count > 1 {
            for (id, suffix) in self.suffixes(for: members) { suffixes[id] = suffix }
        }
        return suffixes
    }

    /// What tells apart sessions with one title: the first of the herdr tab, the worktree, the
    /// subfolder, the place (both of those, or a folder's path) and the branch that no two share,
    /// each after the clone's path in a clone other than the main one. The tab counts only when every
    /// one has one. One may lack any other and keeps the plain title, as the main checkout's top
    /// folder does. Else "#1", "#2" by when they started.
    func suffixes(for members: [AgentDestination]) -> [String: String] {
        func inRepository(_ session: AgentDestination) -> (worktree: String?, subfolder: String?) {
            guard case .repository(_, _, _, let worktree, let subfolder) = session.place else { return (nil, nil) }
            let clone = filing(session).clone
            func inClone(_ part: String?) -> String? { part == nil ? clone : Self.distinct([clone, part]).joined(separator: " · ") }
            return (inClone(worktree), inClone(subfolder))
        }
        func place(_ session: AgentDestination) -> String? {
            switch session.place {
            case .repository(_, _, _, let worktree, let subfolder):
                return Self.distinct([filing(session).clone, worktree, subfolder]).joined(separator: " · ")
            case .folder(let path): return path
            case .none: return nil
            }
        }
        let attributes: [(lackable: Bool, value: (AgentDestination) -> String?)] = [
            (false, { $0.hostLabel }), (true, { inRepository($0).worktree }), (true, { inRepository($0).subfolder }),
            (true, place), (true, { $0.branch }),
        ]
        for (lackable, attribute) in attributes {
            let values = members.map { attribute($0)?.trimmingCharacters(in: .whitespaces) }.map { $0?.isEmpty == false ? $0 : nil }
            let lacking = values.filter { $0 == nil }.count
            guard lacking <= (lackable ? 1 : 0), Set(values.compactMap { $0?.lowercased() }).count == members.count - lacking else { continue }
            return Dictionary(uniqueKeysWithValues: zip(members.map(\.id), values).compactMap { id, value in value.map { (id, $0) } })
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
        if case .repository(let name, _, _, _, _) = session.place,
           label.lowercased().hasPrefix(name.lowercased() + ":") {
            label = String(label.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
        }
        return label.isEmpty ? nil : label
    }

    static func row(for session: AgentDestination, titleSuffix: String?, now: Date, filing: Filing) -> SessionMenu.Row {
        let (tab, baseTitle) = titleParts(of: session)
        let title = titleSuffix.map { "\(baseTitle) (\($0))" } ?? baseTitle
        let named = session.hasOwnName && session.name.lowercased() != baseTitle.lowercased() ? session.name : nil
        let purpose = session.goal ?? named
        let lastActive = session.lastUsed.map { age(since: $0, now: now) }
        var parts: [String?]
        // The time at the row's right, which the tooltip keeps beside the details.
        var tooltipAge: String?
        if let start = session.start {
            // Where it would run, then which session it continues.
            parts = placeParts(session, clone: filing.clone, withSubfolder: true)
            if case .resume = start {
                parts.append(session.hasOwnName ? session.name : nil)
                tooltipAge = lastActive
            }
        } else if tab == nil && purpose == nil {
            // No herdr tab and nothing from the inbox mod: the session's name leads, and its place follows.
            parts = placeParts(session, clone: filing.clone, withSubfolder: true)
            tooltipAge = lastActive
        } else {
            parts = placeParts(session, clone: filing.clone, withSubfolder: false)
            parts.append(purpose)
        }
        let details = distinct(parts).joined(separator: " · ")
        let tooltip = [title, distinct(parts + [tooltipAge]).joined(separator: " · "), filing.header].filter { !$0.isEmpty }.joined(separator: "\n")
        return SessionMenu.Row(destination: session, title: title, details: details, activity: activity(for: session, lastActive: lastActive), tooltip: tooltip)
    }

    /// Working while the session is busy, else when it was last active. A New session row has
    /// none: its time would be the project's last session's, not its own.
    static func activity(for session: AgentDestination, lastActive: String?) -> SessionMenu.Activity? {
        if session.turn == .busy { return .working }
        if case .new? = session.start { return nil }
        return lastActive.map(SessionMenu.Activity.lastActive)
    }

    /// Clone, worktree and branch, or the path from home, with the subfolder when no herdr tab or
    /// goal says more.
    private static func placeParts(_ session: AgentDestination, clone: String?, withSubfolder: Bool) -> [String?] {
        switch session.place {
        case .repository(_, _, _, let worktree, let subfolder):
            return [clone, worktree] + (withSubfolder ? [subfolder] : []) + [session.branch]
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
