import Foundation

/// The agent sessions Send can go to, asked of every agent client off the main thread. It keeps the
/// last list of each client whose list is kept, and a second ask joins the one on its way.
@MainActor
final class SessionListing {
    /// The connections, by client, asked for their sessions. Injected so a test never runs codex.
    private let connections: [AgentClient: any AgentConnection]
    /// Reads herdr's focus. It blocks, so it runs in a client's job, never on the main thread.
    /// Injected so a test never runs herdr.
    private let readHerdr: @Sendable () -> HerdrFocus?

    /// When a drawing was last handed to each session, from the request records.
    private let sends: @MainActor () -> [String: Date]
    /// The sessions Vignette can start, for projects with none running (`StartableSessions`). Asked
    /// in a job of its own, since it reads a transcript per project, so the running sessions'
    /// answer never waits for it. Injected so a test never reads the person's history.
    private let startable: (@Sendable () -> [AgentDestination])?

    init(connections: [AgentClient: any AgentConnection], readHerdr: @escaping @Sendable () -> HerdrFocus? = { HerdrFocus.read() },
         sends: @escaping @MainActor () -> [String: Date] = { [:] }, startable: (@Sendable () -> [AgentDestination])? = nil) {
        self.connections = connections
        self.readHerdr = readHerdr
        self.sends = sends
        self.startable = startable
    }

    /// Where a listing's answers come from: an agent client, or the sessions Vignette can start.
    private enum Source: Hashable {
        case client(AgentClient)
        case startable
    }

    /// Every session that can be addressed right now, the one used last first, and herdr's focus. A
    /// client whose list is kept (`AgentConnection.keepsList`) answers from its last list at once.
    /// Every client is also asked afresh, off the main thread, and the candidates are answered on the
    /// main thread again as each fresh answer arrives. Claude Code's answer, with herdr's focus read in
    /// the same job, comes about 60 to 70 ms after the editor opens. `shown` asks that client for the
    /// session with that id too, such as the thread the Codex app shows. The sessions Vignette can
    /// start come with the answers, apart; the list counts as complete and fresh by the clients alone,
    /// since nothing picks one of them.
    func list(shown: (client: AgentClient, id: String)? = nil,
              _ completion: @escaping @MainActor (DestinationChoice.Candidates) -> Void) {
        let clients = Array(connections.keys)
        guard !clients.isEmpty else { return completion(DestinationChoice.Candidates(destinations: [], complete: true, fresh: true)) }
        let sources = clients.map(Source.client) + (startable == nil ? [] : [.startable])
        let answers = Answers()
        let history = sends()
        func deliver() {
            let running = clients.flatMap { answers.lists[.client($0)] ?? [] }
            let found = running.map { destination -> AgentDestination in
                var stamped = destination
                stamped.lastSent = history[destination.id]
                stamped.hostLabel = answers.herdr?.label(ofSession: destination.id)
                return stamped
            }.sorted(by: DestinationChoice.newestFirst)
            completion(DestinationChoice.Candidates(destinations: found, complete: clients.allSatisfy { answers.lists[.client($0)] != nil },
                                                    fresh: clients.allSatisfy { answers.fresh.contains(.client($0)) }, herdr: answers.herdr,
                                                    startable: Self.startable(answers.lists[.startable] ?? [], beside: running)))
        }
        for source in sources {
            if let list = kept[source] { answers.lists[source] = list }
        }
        // A kept list of sessions to start alone has no session to pick, so it waits for a client's.
        if clients.contains(where: { answers.lists[.client($0)] != nil }) { deliver() }
        for source in sources {
            var including: String?
            if case .client(let client) = source, client == shown?.client { including = shown?.id }
            ask(source, including: including) { listed in
                answers.lists[source] = listed.destinations
                if let herdr = listed.herdr { answers.herdr = herdr }
                answers.fresh.insert(source)
                deliver()
            }
        }
    }

    /// Asks again every source whose list is kept, so the next editor opens on a current list. Run
    /// when an editor is likely to open soon: at launch, on a capture, and when the stack opens.
    func refreshKeptLists() {
        for source in [Source.startable] + connections.keys.map(Source.client) where keepsList(source) { ask(source) { _ in } }
    }

    /// The answers one listing has so far, by source.
    private final class Answers {
        var lists: [Source: [AgentDestination]] = [:]
        var fresh: Set<Source> = []
        var herdr: HerdrFocus?
    }

    /// The sessions Vignette can start, less a project that has a running session: one in the same
    /// folder, or its last session resumed since the list was read. Both spell the folder as the
    /// filesystem does, an inbox by `pwd -P` and Claude Code's history by the folder it ran in.
    static func startable(_ startable: [AgentDestination], beside running: [AgentDestination]) -> [AgentDestination] {
        let ids = Set(running.map(\.id))
        let folders = Set(running.compactMap(\.folder))
        return startable.filter { !ids.contains($0.id) && !folders.contains($0.start?.folder ?? "") }
    }

    /// One source's answer: its destinations, and herdr's focus when it was read with them.
    private struct Listed: Sendable {
        let destinations: [AgentDestination]
        let herdr: HerdrFocus?
    }

    /// The last list of each source whose list is kept. herdr's focus is never kept.
    private var kept: [Source: [AgentDestination]] = [:]
    /// The sources being asked right now, and who is waiting for each answer. A second ask joins
    /// the one on its way instead of starting another.
    private var asking: [Source: [@MainActor (Listed) -> Void]] = [:]

    /// Whether `source`'s last list may stand in while a fresh one is asked for. The sessions Vignette
    /// can start may: nothing picks one, so an old list never settles a target.
    private func keepsList(_ source: Source) -> Bool {
        switch source {
        case .client(let client): return connections[client]?.keepsList ?? false
        case .startable: return startable != nil
        }
    }

    /// Asks one source for its sessions off the main thread. An ask that includes a session runs on
    /// its own, and its answer is not kept: it holds a session found for one editor.
    private func ask(_ source: Source, including id: String? = nil, then answer: @escaping @MainActor (Listed) -> Void) {
        let job: @Sendable () -> Listed
        switch source {
        case .client(let client):
            guard let connection = connections[client] else { return }
            let readHerdr = readHerdr
            job = { Self.job(connection, including: id, readHerdr: readHerdr) }
        case .startable:
            guard let startable else { return }
            job = { Listed(destinations: startable(), herdr: nil) }
        }
        if id != nil {
            DispatchQueue.global(qos: .userInitiated).async {
                let listed = job()
                DispatchQueue.main.async { MainActor.assumeIsolated { answer(listed) } }
            }
            return
        }
        if asking[source] != nil { asking[source]?.append(answer); return }
        asking[source] = [answer]
        let keeps = keepsList(source)
        DispatchQueue.global(qos: .userInitiated).async {
            let listed = job()
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if keeps { self.kept[source] = listed.destinations }
                    let waiting = self.asking.removeValue(forKey: source) ?? []
                    waiting.forEach { $0(listed) }
                }
            }
        }
    }

    /// What one ask of a client does off the main thread. It blocks on the client's subprocesses and on herdr's.
    private nonisolated static func job(_ connection: any AgentConnection, including id: String?,
                                        readHerdr: @Sendable () -> HerdrFocus?) -> Listed {
        let destinations = id.map { connection.destinations(including: $0) } ?? connection.destinations()
        // In the same job, so the focus arrives with the answer that can settle the target.
        let herdr = DestinationChoice.readsHerdr(beside: connection.client, listed: destinations) ? readHerdr() : nil
        return Listed(destinations: destinations, herdr: herdr)
    }
}
