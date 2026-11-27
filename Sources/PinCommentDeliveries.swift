import Foundation

/// The comments the person posts in the editor, on their way to the screenshot's session and after
/// (ADR 0035). It holds each session's changes for the wait, hands the line to the session's client,
/// keeps what came back, and watches the turn the line started. Its records are its own, apart from
/// Send's requests: a delivery writes no image, takes no request slot, and leaves the card's Send state
/// alone (`docs/rules/send.md`).
@MainActor
final class CommentDeliveries {
    /// One line that went to a session, with the comments and pins it was about.
    struct Delivery: Codable, Equatable {
        let id: String
        /// The screenshot's path, as `ScreenshotKey` holds it. A rename moves it.
        var file: String
        let client: AgentClient
        let session: String
        let sessionName: String
        /// The comments whose words it carried.
        let comments: [UUID]
        let pins: [UUID]
        let at: Date
        var status: Status
        /// What the comment says under its words: why it did not go, or why Codex still holds it.
        var reason: String?

        var address: AgentAddress { AgentAddress(client: client, id: session) }
    }

    enum Status: String, Codable {
        /// Handed to the client, with no answer yet.
        case sending
        case sent
        /// In a Codex thread's queue.
        case queued
        /// The client did not say whether it took the line.
        case uncertain
        case failed
    }

    /// What a comment shows about its delivery (look A, `docs/voice.md`).
    struct Shown: Equatable {
        enum State: Equatable { case sending, sent, queued, uncertain, failed }
        let state: State
        let client: AgentClient
        let reason: String?
    }

    private struct Hold {
        var file: ScreenshotKey
        let destination: AgentDestination
        var changes: HeldChanges
    }

    /// The most deliveries kept. The oldest go first.
    static let kept = 1000

    /// The store's file, nil for a test that keeps nothing on disk.
    let store: URL?
    let connections: [AgentClient: any AgentConnection]
    let now: () -> TimeInterval
    let schedule: (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void
    /// Called with the screenshot whose comments' deliveries changed.
    var changed: (ScreenshotKey) -> Void = { _ in }

    private(set) var deliveries: [Delivery] = []
    /// The changes in their wait, by the id their delivery will have.
    private var holds: [String: Hold] = [:]
    private var destinations: [String: AgentDestination] = [:]
    private var turns: [String: CommentTurnWatch] = [:]
    private var queues: [String: QueueWatch] = [:]

    nonisolated static let defaultStore = Identity.applicationSupportURL.appendingPathComponent("comment-deliveries.json")

    init(store: URL?, connections: [AgentClient: any AgentConnection],
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedule: @escaping (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void = { seconds, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { work() } }
         }) {
        self.store = store
        self.connections = connections
        self.now = now
        self.schedule = schedule
        load()
    }

    // MARK: Changes

    /// Holds `item` for `destination` and `grace` seconds, with the other changes on `file` for that
    /// session. The wait does not move: changes made in it go with the first.
    func add(_ item: HeldChanges.Item, on file: ScreenshotKey, to destination: AgentDestination, grace: TimeInterval) {
        if let found = holds.first(where: { $0.value.file == file && $0.value.destination.address == destination.address }) {
            let id = found.key
            var hold = found.value
            hold.changes.add(item)
            holds[id] = hold
            if hold.changes.isEmpty {
                holds[id] = nil
                Log.write("[comments] held \(id) went empty \(file.name)")
            }
            return changed(file)
        }
        var changes = HeldChanges()
        changes.add(item)
        let id = UUID().uuidString.lowercased()
        holds[id] = Hold(file: file, destination: destination, changes: changes)
        Log.write("[comments] held \(id) \(file.name) to \(destination.address.description) for \(Int(grace * 1000))ms")
        changed(file)
        guard grace > 0 else { return release(id) }
        schedule(grace) { [weak self] in self?.release(id) }
    }

    /// The comment ids on `file` that `session` has, may have, or gets when its wait ends: every
    /// delivery to it but a failed one, and its held changes.
    func known(on file: ScreenshotKey, to session: AgentAddress) -> Set<UUID> {
        let sent = deliveries.filter { $0.file == file.path && $0.address == session && $0.status != .failed }.flatMap(\.comments)
        let held = holds.values.filter { $0.file == file && $0.destination.address == session }.flatMap(\.changes.comments)
        return Set(sent + held)
    }

    // MARK: Handing the line over

    private func release(_ id: String) {
        guard let hold = holds.removeValue(forKey: id), !hold.changes.isEmpty else { return }
        guard let connection = connections[hold.destination.address.client] else { return }
        let delivery = Delivery(id: id, file: hold.file.path, client: hold.destination.address.client, session: hold.destination.address.id,
                                sessionName: hold.destination.name, comments: hold.changes.comments,
                                pins: hold.changes.items.map(\.change.pin), at: Date(), status: .sending)
        deliveries.append(delivery)
        destinations[id] = hold.destination
        let line = hold.changes.line(file: hold.file.url.path)
        connection.submit(line, to: hold.destination, watchingTurn: false) { outcome in
            DispatchQueue.main.async { MainActor.assumeIsolated { self.finish(id, outcome) } }
        }
        changed(hold.file)
    }

    private func finish(_ id: String, _ outcome: SubmissionOutcome) {
        guard record(outcome, for: id), let delivery = deliveries.first(where: { $0.id == id }) else { return }
        switch outcome {
        case .accepted:
            watchTurn(id)
        case .queued(_, let reason, let line?):
            queues[id] = QueueWatch(line: line, queued: now(), shown: reason)
            lookAgain(id)
        default:
            break
        }
        changed(ScreenshotKey(asGiven: delivery.file))
    }

    /// Writes `outcome` into delivery `id` and logs it. False when the delivery is gone.
    @discardableResult
    private func record(_ outcome: SubmissionOutcome, for id: String) -> Bool {
        guard let index = deliveries.firstIndex(where: { $0.id == id }) else { return false }
        switch outcome {
        case .accepted: deliveries[index].status = .sent
        case .queued: deliveries[index].status = .queued
        case .uncertain: deliveries[index].status = .uncertain
        case .notSubmitted, .destinationChanged: deliveries[index].status = .failed
        }
        deliveries[index].reason = outcome.reason
        let delivery = deliveries[index]
        Log.write("[comments] \(delivery.status.rawValue) \(id) \(delivery.address.description) comments=\(delivery.comments.count) \(outcome.detail)")
        save()
        return true
    }

    // MARK: Quitting, renaming, deleting

    /// Quit: every held line goes now, and the answers that come within `limit` are kept.
    func releaseHeld(waitingUpTo limit: TimeInterval = 2) {
        let group = DispatchGroup()
        let answers = Answers()
        for (id, hold) in holds where !hold.changes.isEmpty {
            guard let connection = connections[hold.destination.address.client] else { continue }
            deliveries.append(Delivery(id: id, file: hold.file.path, client: hold.destination.address.client, session: hold.destination.address.id,
                                       sessionName: hold.destination.name, comments: hold.changes.comments,
                                       pins: hold.changes.items.map(\.change.pin), at: Date(), status: .sending))
            group.enter()
            connection.submit(hold.changes.line(file: hold.file.url.path), to: hold.destination, watchingTurn: false) { outcome in
                answers.set(id, outcome)
                group.leave()
            }
            Log.write("[comments] released at quit \(id)")
        }
        holds = [:]
        _ = group.wait(timeout: .now() + limit)
        for (id, outcome) in answers.all { record(outcome, for: id) }
        save()
    }

    private final class Answers: @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [String: SubmissionOutcome] = [:]
        func set(_ id: String, _ outcome: SubmissionOutcome) { lock.lock(); answers[id] = outcome; lock.unlock() }
        var all: [String: SubmissionOutcome] { lock.lock(); defer { lock.unlock() }; return answers }
    }

    /// A rename carries the held changes and the records to the new name.
    func renamed(_ renames: [FolderWrites.Rename]) {
        var moved = false
        for rename in renames {
            for (id, hold) in holds where hold.file == rename.from { holds[id]?.file = rename.to }
            for index in deliveries.indices where deliveries[index].file == rename.from.path {
                deliveries[index].file = rename.to.path
                moved = true
            }
        }
        if moved { save() }
    }

    /// The screenshot left the folder: its held changes go nowhere, and its deliveries and their
    /// watches go.
    func fileRemoved(_ file: ScreenshotKey) {
        for (id, hold) in holds where hold.file == file {
            holds[id] = nil
            Log.write("[comments] cancelled \(id) \(file.name): the file left the folder")
        }
        let gone = Set(deliveries.filter { $0.file == file.path }.map(\.id))
        guard !gone.isEmpty else { return }
        deliveries.removeAll { gone.contains($0.id) }
        for id in gone { forget(id) }
        save()
    }

    private func forget(_ id: String) {
        turns[id] = nil
        queues[id] = nil
        destinations[id] = nil
    }

    // MARK: What the popover and the comments command read

    /// The newest delivery of `comment` on `file`, or its wait.
    func shown(comment: UUID, on file: ScreenshotKey) -> Shown? {
        if let hold = holds.values.first(where: { $0.file == file && $0.changes.comments.contains(comment) }) {
            return Shown(state: .sending, client: hold.destination.address.client, reason: nil)
        }
        guard let delivery = deliveries.last(where: { $0.file == file.path && $0.comments.contains(comment) }) else { return nil }
        let state: Shown.State
        switch delivery.status {
        case .sending: state = .sending
        case .sent: state = .sent
        case .queued: state = .queued
        case .uncertain: state = .uncertain
        case .failed: state = .failed
        }
        return Shown(state: state, client: delivery.client, reason: delivery.reason)
    }

    /// The client whose turn a delivery about `pin` started is running, and when that delivery went.
    func working(pin: UUID, on file: ScreenshotKey) -> (client: AgentClient, since: Date)? {
        deliveries.last { $0.file == file.path && $0.pins.contains(pin) && turns[$0.id]?.working == true }
            .map { ($0.client, $0.at) }
    }

    /// Each comment's deliveries on `file`, oldest first, as the `comments` command writes them.
    func report(on file: ScreenshotKey) -> [UUID: [[String: Any]]] {
        var report: [UUID: [[String: Any]]] = [:]
        for delivery in deliveries where delivery.file == file.path {
            for comment in delivery.comments {
                report[comment, default: []].append(["agent": delivery.client.rawValue, "session": delivery.session, "to": delivery.sessionName,
                                                     "at": Pin.Comment.written(delivery.at), "status": delivery.status.rawValue])
            }
        }
        return report
    }

    // MARK: Watching the turn and the queue

    private func watchTurn(_ id: String) {
        guard let destination = destinations[id], connections[destination.address.client]?.reportsTurns == true else { return }
        turns[id] = CommentTurnWatch(since: now())
        lookAtTurn(id, after: 0.5)
    }

    private func lookAtTurn(_ id: String, after delay: TimeInterval) {
        schedule(delay) { [weak self] in
            guard let self, turns[id] != nil, let destination = destinations[id], let connection = connections[destination.address.client] else { return }
            DispatchQueue.global(qos: .utility).async {
                let turn = connection.turn(of: destination)
                DispatchQueue.main.async { MainActor.assumeIsolated { self.looked(id, turn) } }
            }
        }
    }

    private func looked(_ id: String, _ turn: SessionTurn?) {
        guard var watch = turns[id], let delivery = deliveries.first(where: { $0.id == id }) else { return }
        let effect = watch.look(turn, at: now())
        turns[id] = watch
        switch effect {
        case .wait:
            lookAtTurn(id, after: 1)
        case .started:
            Log.write("[comments] working \(id) \(delivery.address.description)")
            changed(ScreenshotKey(asGiven: delivery.file))
            lookAtTurn(id, after: 1)
        case .ended:
            turns[id] = nil
            if watch.working {
                Log.write("[comments] turn ended \(id) after=\(Int((now() - watch.since) * 1000))ms")
                changed(ScreenshotKey(asGiven: delivery.file))
            }
        }
    }

    private func lookAgain(_ id: String) {
        guard let watch = queues[id] else { return }
        schedule(watch.nextLook(at: now())) { [weak self] in
            guard let self, let watch = queues[id], let delivery = deliveries.first(where: { $0.id == id }),
                  let connection = connections[delivery.client] else { return }
            let marker = delivery.pins.first?.uuidString
            DispatchQueue.global(qos: .utility).async {
                let state = connection.look(at: watch.line, carrying: marker) ?? .unread(detail: "\(connection.client.label) has no queue")
                DispatchQueue.main.async { MainActor.assumeIsolated { self.lookedAtQueue(id, watch.line, state) } }
            }
        }
    }

    private func lookedAtQueue(_ id: String, _ line: QueuedLine, _ state: QueuedLine.State) {
        guard var watch = queues[id], watch.line == line, let index = deliveries.firstIndex(where: { $0.id == id }) else { return }
        let effect = watch.look(state, at: now())
        queues[id] = watch
        let file = ScreenshotKey(asGiven: deliveries[index].file)
        switch effect {
        case .wait:
            lookAgain(id)
        case .logUnread(let detail):
            Log.write("[comments] queue unread \(id) line=\(line.id): \(detail)")
            lookAgain(id)
        case .show(let hold):
            deliveries[index].reason = hold.reason
            save()
            changed(file)
            lookAgain(id)
        case .taken:
            queues[id] = nil
            deliveries[index].status = .sent
            deliveries[index].reason = nil
            Log.write("[comments] taken \(id) line=\(line.id)")
            save()
            watchTurn(id)
            changed(file)
        case .removed:
            queues[id] = nil
            deliveries[index].status = .failed
            deliveries[index].reason = Self.removedReason
            Log.write("[comments] removed in session \(id) line=\(line.id)")
            save()
            changed(file)
        case .threadGone(let detail):
            queues[id] = nil
            deliveries[index].status = .failed
            deliveries[index].reason = ScreenshotRequests.threadGoneReason
            Log.write("[comments] error thread gone \(id) line=\(line.id) \(detail)")
            save()
            changed(file)
        }
    }

    static let removedReason = "It was removed from the thread's queue in Codex."

    // MARK: The store

    private func load() {
        guard let store, let data = try? Data(contentsOf: store) else { return }
        guard let read = try? JSONDecoder().decode([Delivery].self, from: data) else {
            return Log.write("[comments] error the delivery records at \(store.path) did not decode")
        }
        // A line still going when the app stopped may or may not have reached its session.
        deliveries = read.map { delivery in
            var delivery = delivery
            if delivery.status == .sending { delivery.status = .uncertain }
            return delivery
        }
    }

    private func save() {
        if deliveries.count > Self.kept {
            let pruned = deliveries.prefix(deliveries.count - Self.kept).map(\.id)
            deliveries.removeFirst(pruned.count)
            pruned.forEach(forget)
        }
        guard let store else { return }
        do {
            try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(deliveries).write(to: store, options: .atomic)
        } catch {
            Log.write("[comments] error \(CommandError.writeFailed.rawValue) \(store.path): \(error.localizedDescription)")
        }
    }
}
