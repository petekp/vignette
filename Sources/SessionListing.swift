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

    /// Every session that can be addressed right now, the one used last first, and herdr's focus. A
    /// client whose list is kept (`AgentConnection.keepsList`) answers from its last list at once.
    /// Every client is also asked afresh, off the main thread, and the candidates are answered on the
    /// main thread again as each fresh answer arrives. Claude Code's answer, with herdr's focus read in
    /// the same job, comes about 60 to 70 ms after the editor opens. `shown` asks that client for the
    /// session with that id too, such as the thread the Codex app shows.
    func list(shown: (client: AgentClient, id: String)? = nil,
              _ completion: @escaping @MainActor (DestinationChoice.Candidates) -> Void) {
        let clients = Array(connections.keys)
        guard !clients.isEmpty else { return completion(DestinationChoice.Candidates(destinations: [], complete: true, fresh: true)) }
        let answers = Answers()
        let history = sends()
        func deliver() {
            let running = answers.lists.values.flatMap { $0 }
            let found = (running + Self.startable(answers.startable, beside: running)).map { destination -> AgentDestination in
                var stamped = destination
                stamped.lastSent = history[destination.id]
                stamped.hostLabel = answers.herdr?.label(ofSession: destination.id)
                return stamped
            }.sorted(by: DestinationChoice.newestFirst)
            let fresh = answers.fresh.count == clients.count && (startable == nil || answers.startableFresh)
            completion(DestinationChoice.Candidates(destinations: found, complete: answers.lists.count == clients.count,
                                                    fresh: fresh, herdr: answers.herdr))
        }
        for client in clients {
            if let list = kept[client] { answers.lists[client] = list }
        }
        answers.startable = keptStartable
        if !answers.lists.isEmpty { deliver() }
        askStartable { found in
            answers.startable = found
            answers.startableFresh = true
            deliver()
        }
        for client in clients {
            ask(client, including: shown?.client == client ? shown?.id : nil) { listed in
                answers.lists[client] = listed.destinations
                if let herdr = listed.herdr { answers.herdr = herdr }
                answers.fresh.insert(client)
                deliver()
            }
        }
    }

    /// Asks again every client whose list is kept, and the sessions Vignette can start, so the next
    /// editor opens on a current list and a read transcript. Run when an editor is likely to open
    /// soon: at launch, on a capture, and when the stack opens.
    func refreshKeptLists() {
        for (client, connection) in connections where connection.keepsList { ask(client) { _ in } }
        askStartable { _ in }
    }

    /// The answers one listing has so far, by client.
    private final class Answers {
        var lists: [AgentClient: [AgentDestination]] = [:]
        var fresh: Set<AgentClient> = []
        var herdr: HerdrFocus?
        var startable: [AgentDestination] = []
        var startableFresh = false
    }

    /// The sessions Vignette can start, less any whose session is among the running ones: one
    /// resumed since its list was read.
    static func startable(_ startable: [AgentDestination], beside running: [AgentDestination]) -> [AgentDestination] {
        let ids = Set(running.map(\.id))
        return startable.filter { !ids.contains($0.id) }
    }

    /// The last list of sessions Vignette can start, shown until a fresh one comes.
    private var keptStartable: [AgentDestination] = []
    private var askingStartable: [@MainActor ([AgentDestination]) -> Void]?

    private func askStartable(_ answer: @escaping @MainActor ([AgentDestination]) -> Void) {
        guard let startable else { return }
        if askingStartable != nil { askingStartable?.append(answer); return }
        askingStartable = [answer]
        DispatchQueue.global(qos: .userInitiated).async {
            let found = startable()
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.keptStartable = found
                    let waiting = self.askingStartable ?? []
                    self.askingStartable = nil
                    waiting.forEach { $0(found) }
                }
            }
        }
    }

    /// One client's answer: its destinations, and herdr's focus when it was read with them.
    private struct Listed: Sendable {
        let destinations: [AgentDestination]
        let herdr: HerdrFocus?
    }

    /// The last list of each client whose list is kept. herdr's focus is never kept.
    private var kept: [AgentClient: [AgentDestination]] = [:]
    /// The clients being asked right now, and who is waiting for each answer. A second ask joins
    /// the one on its way instead of starting another.
    private var asking: [AgentClient: [@MainActor (Listed) -> Void]] = [:]

    /// Asks one client for its sessions off the main thread. An ask that includes a session runs on
    /// its own, and its answer is not kept: it holds a session found for one editor.
    private func ask(_ client: AgentClient, including id: String? = nil, then answer: @escaping @MainActor (Listed) -> Void) {
        guard let connection = connections[client] else { return }
        let readHerdr = readHerdr
        if let id {
            DispatchQueue.global(qos: .userInitiated).async {
                let listed = Self.job(connection, including: id, readHerdr: readHerdr)
                DispatchQueue.main.async { MainActor.assumeIsolated { answer(listed) } }
            }
            return
        }
        if asking[client] != nil { asking[client]?.append(answer); return }
        asking[client] = [answer]
        DispatchQueue.global(qos: .userInitiated).async {
            let listed = Self.job(connection, including: nil, readHerdr: readHerdr)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if connection.keepsList { self.kept[client] = listed.destinations }
                    let waiting = self.asking.removeValue(forKey: client) ?? []
                    waiting.forEach { $0(listed) }
                }
            }
        }
    }

    /// What one ask does off the main thread. It blocks on the client's subprocesses and on herdr's.
    private nonisolated static func job(_ connection: any AgentConnection, including id: String?,
                                        readHerdr: @Sendable () -> HerdrFocus?) -> Listed {
        let destinations = id.map { connection.destinations(including: $0) } ?? connection.destinations()
        // In the same job, so the focus arrives with the answer that can settle the target.
        let herdr = DestinationChoice.readsHerdr(beside: connection.client, listed: destinations) ? readHerdr() : nil
        return Listed(destinations: destinations, herdr: herdr)
    }
}
