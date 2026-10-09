import Foundation

/// Which agent session Send, or a live ink note, starts on before the person picks one, and the
/// order Send's menu lists the sessions in. Every rule for that pick is here, so a new one changes
/// this file and its tests. It takes facts and answers the pick. Send's facts are the sessions listed
/// so far, herdr's focus and the agent's app that was in front, and it marks the session you came
/// from. A note's fact is its own pick, and it reads neither herdr's focus nor an agent's app.
enum DestinationChoice {
    /// Who is asking, and the facts only that asker uses.
    enum Asker {
        /// Send, on the annotator's toolbar. `cameFrom` is the agent's own app that was in front
        /// before Vignette, such as the Codex app, and the thread it shows.
        case send(cameFrom: (client: AgentClient, shown: String?)?)
        /// The live ink note. It reads neither herdr's focus nor an agent's app.
        case liveNote(LiveNotePick)
    }

    /// The live ink note's own pick, a fact the note keeps. Nil is no session: the responder.
    enum LiveNotePick: Equatable {
        /// Nobody has picked on this note yet: the target the note before it was sent to.
        case remembered(AgentDestination?)
        /// The person picked on this note.
        case byHand(AgentDestination?)
    }

    /// One answer from the listing, and the pick made from it.
    struct Answer: Equatable {
        /// The sessions in Send's order. For Send, each is marked with why it is the session you
        /// came from; a live ink note's carry no mark.
        let list: [AgentDestination]
        /// Every client has answered, and no fresher list is awaited.
        let complete: Bool
        /// Whether this answer is enough to pick: a session is marked as the one you came from, or
        /// the whole list is in, since the session used last is a comparison across every client. A
        /// live ink note's answer is always decided: the note starts on each answer's pick at once.
        let decided: Bool
        /// The session the asker starts on when `decided`. Nil is no session: Send has none to
        /// send to, and a live ink note starts on the responder.
        let pick: AgentDestination?
    }

    /// What a listing has found so far: the candidate destinations and the facts that came with them.
    struct Candidates {
        /// In Send's order (`newestFirst`). A `focus` on them is ignored: only `choose` marks.
        let destinations: [AgentDestination]
        /// Every client has answered, from a kept list or a fresh one.
        let complete: Bool
        /// Every answer is fresh.
        let fresh: Bool
        /// herdr's focus, read with `markedByHerdr`'s answer. Nil before it, without herdr, or when
        /// that client listed no destination (`readsHerdr`).
        var herdr: HerdrFocus? = nil
    }

    /// The one client whose sessions herdr's focus marks. A focused Codex pane marks nothing, even
    /// when herdr names its thread.
    static let markedByHerdr: AgentClient = .claude

    /// Whether herdr's focus is worth reading beside `client`'s answer: it can mark only
    /// `markedByHerdr`'s destinations, and only when there are some. `SessionListing` reads it in
    /// that client's job, so the focus comes with the answer that can settle the pick.
    static func readsHerdr(beside client: AgentClient, listed: [AgentDestination]) -> Bool {
        client == markedByHerdr && !listed.isEmpty
    }

    /// The pick `asker` starts on from the candidates found so far.
    static func choose(_ candidates: Candidates, for asker: Asker) -> Answer {
        switch asker {
        case .send(let cameFrom):
            return choose(forSend: candidates, cameFrom: cameFrom)
        case .liveNote(let pick):
            let list = unmarked(candidates)
            return Answer(list: list, complete: candidates.complete, decided: true, pick: start(pick, in: list))
        }
    }

    private static func unmarked(_ candidates: Candidates) -> [AgentDestination] {
        candidates.destinations.map { destination in
            var cleared = destination
            cleared.focus = nil
            return cleared
        }
    }

    /// Where a live ink note starts. A hand pick stays while the list has its id; the session
    /// remembered from the note before is found again, even after `/clear`.
    private static func start(_ pick: LiveNotePick, in list: [AgentDestination]) -> AgentDestination? {
        switch pick {
        case .byHand(let session?): return list.contains { $0.id == session.id } ? session : nil
        case .remembered(let session?): return again(session, in: list)
        case .byHand(nil), .remembered(nil): return nil
        }
    }

    /// `session` again in `list`: by its id, or, after `/clear` gave it a new id, as the one session
    /// of its agent in its project. Never by `project`, which falls back to the agent's name.
    private static func again(_ session: AgentDestination, in list: [AgentDestination]) -> AgentDestination? {
        if let same = list.first(where: { $0.id == session.id }) { return same }
        let alike = list.filter { $0.client == session.client && !$0.detail.isEmpty && $0.detail == session.detail }
        return alike.count == 1 ? alike[0] : nil
    }

    /// Send's pick from the candidates found so far. `cameFrom` is the agent's own app that was in
    /// front before Vignette, such as the Codex app, and the thread it shows.
    private static func choose(forSend candidates: Candidates, cameFrom: (client: AgentClient, shown: String?)?) -> Answer {
        let unmarked = Self.unmarked(candidates)
        var complete = candidates.complete
        let list: [AgentDestination]
        if let cameFrom {
            list = marked(cameFrom.client, shown: cameFrom.shown, in: unmarked, fresh: candidates.fresh)
            // Nothing marked from a kept list means the shown thread may be newer than it, so the
            // pick waits for the fresh one rather than settling on the thread used last.
            if !candidates.fresh && !list.contains(where: { $0.focus == .app }) { complete = false }
        } else {
            list = marked(unmarked, herdr: candidates.herdr)
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
    /// herdr keeps a focused pane while its terminal is behind, so its focus says nothing then. The
    /// app's session is `shown`, the id of the thread it shows, or else that client's session used
    /// last. When a list that is not `fresh` lacks `shown`, nothing is marked: the thread may have
    /// started since the list was kept, and the fresh list will say. `list` is in Send's order.
    private static func marked(_ client: AgentClient, shown: String?, in list: [AgentDestination], fresh: Bool) -> [AgentDestination] {
        var marked = list
        let ofClient = marked.indices.filter { marked[$0].client == client }
        let match = shown.flatMap { id in ofClient.first { marked[$0].id == id } }
        guard match != nil || shown == nil || fresh else { return marked }
        if let index = match ?? ofClient.first { marked[index].focus = .app }
        return marked
    }

    /// Marks where herdr's focus is. `herdr.agents` is every agent herdr runs, of any kind. A focused
    /// pane running an agent is that agent's, whether or not it is a destination. One running none,
    /// such as a browser or a shell beside the session you are working with (observed 2026-09-24),
    /// passes the focus to the one agent in its tab; a tab with two says nothing about which one.
    /// Only `markedByHerdr`'s sessions are marked.
    private static func marked(_ list: [AgentDestination], herdr: HerdrFocus?) -> [AgentDestination] {
        guard let herdr else { return list }
        let focusedAgent = herdr.agents.first { $0.pane == herdr.pane }
        let inTab = herdr.agents.filter { !herdr.tab.isEmpty && $0.tab == herdr.tab }
        return list.map { destination in
            guard destination.client == markedByHerdr else { return destination }
            var marked = destination
            if let focusedAgent {
                if focusedAgent.session == destination.id { marked.focus = .pane }
            } else if inTab.count == 1, inTab[0].session == destination.id {
                marked.focus = .tab
            }
            return marked
        }
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
