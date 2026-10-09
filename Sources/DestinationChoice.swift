import Foundation

/// Which agent session Send starts on before the person picks one, and the order its menu lists the
/// sessions in. Every rule for that pick is here, so a new one changes this file and its tests.
enum DestinationChoice {
    /// One answer from the listing, and the pick made from it.
    struct Answer: Equatable {
        /// The sessions in Send's order, each marked with why it is the session you came from.
        let list: [AgentDestination]
        /// Every client has answered, and no fresher list is awaited.
        let complete: Bool
        /// Whether this answer is enough to pick: a session is marked as the one you came from, or
        /// the whole list is in, since the session used last is a comparison across every client.
        let decided: Bool
        /// The session Send starts on when `decided`. Nil when there is none to send to.
        let pick: AgentDestination?
    }

    /// The pick from the sessions found so far. `found` is in Send's order; `complete` says every
    /// client has answered and `fresh` that every answer is fresh rather than kept. `cameFrom` is the
    /// agent's own app that was in front before Vignette, such as the Codex app, and the thread it
    /// shows.
    static func choose(_ found: [AgentDestination], complete: Bool, fresh: Bool,
                       cameFrom: (client: AgentClient, shown: String?)?) -> Answer {
        var list = found
        var complete = complete
        if let cameFrom {
            list = marked(cameFrom.client, shown: cameFrom.shown, in: found, fresh: fresh)
            // Nothing marked from a kept list means the shown thread may be newer than it, so the
            // pick waits for the fresh one rather than settling on the thread used last.
            if !fresh && !list.contains(where: { $0.focus == .app }) { complete = false }
        }
        let decided = complete || list.contains { $0.focus != nil }
        return Answer(list: list, complete: complete, decided: decided, pick: decided ? pick(in: list) : nil)
    }

    /// Where Send goes when nobody has chosen: the session you came from, which is where a paste
    /// would have gone. The session an agent's app showed first, then herdr's focused pane, then the
    /// one session beside it, then the session used last. `list` is in Send's order, the session used
    /// last first.
    private static func pick(in list: [AgentDestination]) -> AgentDestination? {
        list.first { $0.focus == .app } ?? list.first { $0.focus == .pane } ?? list.first { $0.focus == .tab }
            ?? list.first
    }

    /// The sessions as they stand when you came from `client`'s own app, such as the Codex app.
    /// herdr keeps a focused pane while its terminal is behind, so its focus says nothing then and is
    /// cleared. The app's session is `shown`, the id of the thread it shows, or else that client's
    /// session used last. When a list that is not `fresh` lacks `shown`, nothing is marked: the
    /// thread may have started since the list was kept, and the fresh list will say. `list` is in
    /// Send's order.
    private static func marked(_ client: AgentClient, shown: String?, in list: [AgentDestination], fresh: Bool) -> [AgentDestination] {
        var marked = list.map { destination -> AgentDestination in
            var cleared = destination
            cleared.focus = nil
            return cleared
        }
        let ofClient = marked.indices.filter { marked[$0].client == client }
        let match = shown.flatMap { id in ofClient.first { marked[$0].id == id } }
        guard match != nil || shown == nil || fresh else { return marked }
        if let index = match ?? ofClient.first { marked[index].focus = .app }
        return marked
    }

    /// Send's menu: the sessions used last among the active ones, at most `count`, with `target`
    /// always among them so its check is seen. `list` is in Send's order.
    static func menu(_ list: [AgentDestination], target: AgentDestination, count: Int = 5, now: Date = Date()) -> [AgentDestination] {
        let active = Array(list.filter { $0.isActive(now: now) }.prefix(count))
        guard !active.contains(where: { $0.id == target.id }) else { return active }
        return Array(active.prefix(count - 1)) + [target]
    }

    /// Send's order: the session used last first. A session with no time comes after every one
    /// with a time, and a tie goes by name.
    static func newestFirst(_ a: AgentDestination, _ b: AgentDestination) -> Bool {
        switch (a.lastUsed, b.lastUsed) {
        case let (x?, y?) where x != y: return x > y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.name < b.name
        }
    }
}
