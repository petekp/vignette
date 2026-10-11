import Foundation

/// Sending a drawing to an agent session and taking its drawing back. One object owns all of it:
/// the fixed sent image, the durable request and reply records, reply validation, the receipts an
/// agent's helper waits for, and the import that turns an accepted reply into an ordinary card.
/// Splitting the store from the coordinator would mean passing the same state through twice.
///
/// Two events are durable and different. **Acceptance** means Vignette owns every byte of a reply
/// and will keep it; it is what a receipt acknowledges. **Publication** means the reply is a card
/// the person can use. Between them the reply's file name is reserved and excluded from every
/// listing, so an interrupted import leaves nothing half-shown.
@MainActor
final class ScreenshotRequests {
    /// What the coordinator needs from the rest of the app. Closures, like ThumbnailController's,
    /// so nothing here reaches into the annotator or the stack.
    struct Callbacks {
        /// Adds marks to a screenshot's drawing and stores it, without showing anything, then answers
        /// nil, or why not. Publication waits for the answer, so a card never appears without its marks.
        /// The name is the agent's, which its notes' badges show.
        var installDrawing: (Screenshot, [AgentMark], _ agent: String?, @escaping (Drawings.Failure?) -> Void) -> Void = { _, _, _, done in
            done(Drawings.Failure(code: .writeFailed, description: "nothing stores drawings"))
        }
        /// The picture at a URL as `installDrawing` will draw an agent's answer on it, so the answer's
        /// words and labels are measured and placed there; nil leaves them in the corner and under their marks.
        var cardCanvas: (URL, _ agent: String?) -> LiveAnswer.Canvas? = { _, _ in nil }
        /// Shows a published reply's card. Managed replies never reach the watcher's capture path.
        var present: (Screenshot) -> Void = { _ in }
        /// Makes an answer to live ink its result card, from a fresh capture of the window the ink was
        /// on, then answers the indexes of the marks it could not find there, or nil when it could not
        /// capture that window and the reply is published on the request's own picture instead.
        var presentLive: (Record, LiveAnswer, @escaping ([Int]?) -> Void) -> Void = { _, _, done in done(nil) }
        var watchFolder: () -> URL = { FileManager.default.temporaryDirectory }
        /// What the client answered for a request, which the card that was sent shows.
        var delivered: (Record, SubmissionOutcome) -> Void = { _, _ in }
        /// A reply to this request was accepted and could not be made a card, which the card that
        /// was sent shows, since there is no card of the reply's own to show it on. The reason is
        /// what the person can do about it.
        var replyFailed: (Record, String) -> Void = { _, _ in }
        /// A send that waited out its grace is going to its client now. Called on the timer's turn,
        /// before the client is asked, so before `delivered`. Never called for a send with no grace.
        var released: (Record) -> Void = { _ in }
        /// A send that was waiting ended without reaching its client: Don't send, or a clear took
        /// its request.
        var cancelled: (Record) -> Void = { _ in }
    }

    var callbacks = Callbacks()
    /// The connections, by client, which `send` submits through. Injected so a test never runs codex.
    let connections: [AgentClient: any AgentConnection]

    /// The most requests kept open at once, each with its PNG and a ticket its agent can still reply
    /// with. A send past it clears the oldest: a limit that refused the send stopped Send working
    /// for good after the fiftieth, and an agent answers a request within the hour, not fifty sends later.
    static let maxLiveRequests = 50
    /// How long a cleared request's folder is kept. Until then a late reply is told the request was
    /// cleared; after it the ticket is gone and the reply is refused as unauthorized.
    static let clearedKept: TimeInterval = 7 * 24 * 3600
    /// A request's `Record`, in its request directory. `ReplyCommand` reads it to tell a retry that
    /// the request was cleared.
    nonisolated static let recordFileName = "request.json"

    /// Where the app keeps its requests. `ClaudeReadRule` names the images in it.
    nonisolated static let defaultRoot = Identity.applicationSupportURL.appendingPathComponent("requests")

    let root: URL
    private var requests: [String: Record] = [:]
    private var replies: [String: Reply] = [:]
    /// Accepted replies not yet published, imported serially in arrival order within a launch.
    /// A relaunch rebuilds the order from the store.
    private var pendingImports: [String] = []
    private var importing = false
    private var publishedAt: [String: TimeInterval] = [:]
    private var publicationReady = false
    /// Cancellation takes effect in memory even when its record cannot yet be written.
    private var pendingCleanupWrites: Set<String> = []
    /// The sends between Send and their line reaching the client.
    private var sendGrace = SendGrace()
    private let now: () -> TimeInterval
    private let schedule: (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

    /// `now` and `schedule` are the clock and the timer a grace period runs on: a test sets both.
    /// The clock is `systemUptime`, which stops during sleep as the timer does, so a deadline and its
    /// timer stay in step.
    init(root: URL, connections: [AgentClient: any AgentConnection] = [:],
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedule: @escaping (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void = { seconds, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { work() } }
         }) {
        self.root = root
        self.connections = connections
        self.now = now
        self.schedule = schedule
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: The records

    /// One screenshot request: where it went, and how far it got. `address` is the whole identity
    /// of the destination, so Reply goes back to the same conversation and never to a guessed one.
    struct Record: Codable {
        let id: String
        let created: Date
        let destinationID: String
        let destinationName: String
        let address: AgentAddress
        let addressGuard: AddressGuard
        /// The screenshot the drawing was made on, for the log and the picker. Not a path: the
        /// original stays the person's and may be moved or deleted without touching this request.
        let source: String
        var status: Status
        /// Why the client did not take the request, for a listing after a restart. Empty when it
        /// did: an accepted submission says only what the address already says.
        var detail: String

        enum Status: String, Codable {
            /// Stored and not yet handed to the client: in its grace, or about to be.
            case prepared
            /// The client took it. Not proof that a model has read the image.
            case submitted
            /// The call did not answer. It may have arrived, so it is never resubmitted.
            case uncertain
            case failed
            /// The person cleared it: no new reply is accepted, unpublished imports are cancelled.
            case cleared
        }

        /// Whether a reply may still be accepted for this request.
        var takesReplies: Bool { status != .cleared }
    }

    /// One reply to one request, and where its import has reached.
    struct Reply: Codable {
        let id: String
        let requestID: String
        let digest: String
        /// True when the reply supplied its own PNG; false means it draws on the request's image.
        let hasImage: Bool
        let marks: [AgentMark]
        /// An answer to live ink, which comes without marks or an image (`ReplyProtocol.Bundle`).
        var answer: LiveAnswer? = nil
        var stage: Stage
        var destination: URL?
        var needsOutputCleanup: Bool?
        /// The person deleted the published file. Publication still happened and is not undone.
        var deleted = false
        var errorCode: String?
        /// For an answer, once it is drawn: the indexes of its marks that were not.
        var notDrawn: [Int]?

        enum Stage: String, Codable {
            /// Vignette owns every byte. The helper may release its bundle.
            case accepted
            /// The watch-folder name is reserved and excluded from everything.
            case reserved
            /// The card exists and is ordinary. The one publication point.
            case published
            /// An answer live ink made a result card of itself, from a fresh capture of its window.
            /// That card is an ordinary file, so the reply has no file of its own.
            case shown
            /// The import stopped; the payload is kept and the name stays excluded.
            case failed
            /// The request was cleared before this reply was published.
            case cancelled
        }

        /// What a card of this reply draws on `canvas`: its marks, or, for an answer whose window could
        /// not be captured, the answer's words beside its first mark and a ring round each mark's box.
        /// A mark that names only words is left out, since nothing finds words in the request's picture.
        func cardMarks(on canvas: LiveAnswer.Canvas?) -> [AgentMark] {
            guard let answer else { return marks }
            return answer.cardMarks(targets: answer.marks.map(\.box), on: canvas)
        }

        /// The answer's marks a card leaves out: those that name only words.
        var undrawnOnCard: [Int] {
            guard let answer else { return [] }
            return answer.marks.indices.filter { answer.marks[$0].box == nil }
        }

        /// The reserved watch-folder name. Derived, so a record and its file cannot drift apart.
        var fileName: String { ReplyProtocol.replyFileName(id) }

        var outputURL: URL? {
            guard let destination, destination.isFileURL, destination.path.hasPrefix("/"),
                  destination.lastPathComponent == fileName else { return nil }
            return destination.standardizedFileURL
        }

        var publication: ReplyProtocol.Receipt.Publication {
            if deleted { return .removed }
            switch stage {
            case .accepted, .reserved: return .pending
            case .published, .shown: return .ready
            case .failed: return .failed
            case .cancelled: return .cancelled
            }
        }
    }

    // MARK: Loading, before anything reads the watch folder

    /// Reads every request and reply from disk. Runs before the watcher starts, the stack warms, or
    /// any file action can happen: until it has, nothing knows which managed files are unfinished.
    /// A record that will not decode is dropped from memory and left on disk, which keeps its file
    /// name excluded (an unknown managed name is hidden) rather than turning it into a capture.
    /// Replies an earlier launch accepted and did not publish are imported from here.
    /// A request still prepared lost its line with the process that held it, so `clearingUnsent`
    /// clears it. A launch that replaces a running copy passes false: that copy may still be handing
    /// its waiting lines over as it quits, and clearing would delete the image they name.
    func load(clearingUnsent: Bool = true) {
        let fm = FileManager.default
        var loadedRequests = 0, loadedReplies = 0, unreadable = 0
        for directory in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            guard ReplyProtocol.isID(directory.lastPathComponent) else { continue }
            if let record: Record = decode(directory.appendingPathComponent(Self.recordFileName)) {
                requests[record.id] = record
                loadedRequests += 1
            } else { unreadable += 1 }
            for file in (try? fm.contentsOfDirectory(at: directory.appendingPathComponent("replies"), includingPropertiesForKeys: nil)) ?? [] {
                guard file.pathExtension == "json" else { continue }
                if let reply: Reply = decode(file) {
                    replies[reply.id] = reply
                    loadedReplies += 1
                    if reply.stage == .accepted || reply.stage == .reserved { pendingImports.append(reply.id) }
                } else { unreadable += 1 }
            }
        }
        for record in requests.values where record.status == .cleared { cleanup(record.id) }
        for record in requests.values where clearingUnsent && record.status == .prepared {
            Log.write("[requests] cleared \(record.id): its line never went, Vignette quit first")
            do { try clear(record.id) }
            catch { Log.write("[requests] error cleanup \(record.id): \(error.localizedDescription)") }
        }
        prune()
        Log.write("[requests] loaded \(loadedRequests) requests \(loadedReplies) replies pending=\(pendingImports.count)\(unreadable > 0 ? " unreadable=\(unreadable)" : "") dir=\(root.path)")
        importNext()
    }

    // MARK: What the rest of the app asks

    /// Whether a watch-folder file may be listed, warmed, opened, or made into a card. Every
    /// consumer asks this, not only the directory listing: a cached result or a late watcher event
    /// would otherwise show a reply whose import is not finished. Fails closed on a managed name
    /// with no published record, which is also what an unreadable store leaves behind.
    func isVisible(_ url: URL) -> Bool {
        guard let id = ReplyProtocol.replyID(fromFileName: url.lastPathComponent) else { return true }
        guard let reply = replies[id], reply.stage == .published else { return false }
        return reply.destination == nil || reply.outputURL == url.standardizedFileURL
    }

    /// Whether a new file in the watch folder is an ordinary capture. A managed reply never is: it
    /// is presented once by its own import, and a late watcher event for it must not copy it to
    /// the clipboard or open the editor.
    func isCapture(_ url: URL) -> Bool {
        ReplyProtocol.replyID(fromFileName: url.lastPathComponent) == nil
    }

    /// A file left the watch folder. A send of it still in its grace is cancelled, since deleting the
    /// card is a way of not sending it. A deleted published reply stays deleted: publication happened,
    /// and the recovery copy is not used to put the file back.
    func fileRemoved(_ url: URL) {
        unsend(file: url)
        guard let id = ReplyProtocol.replyID(fromFileName: url.lastPathComponent), var reply = replies[id],
              reply.stage == .published, reply.outputURL == url.standardizedFileURL, !reply.deleted else { return }
        reply.deleted = true
        replies[id] = reply
        try? write(reply)
        Log.write("[reply] removed \(reply.fileName)")
    }

    func reconcile(_ inventory: ScreenshotWatcher.Inventory, now: Date = Date()) {
        publicationReady = true
        for record in requests.values where record.status == .cleared { cleanup(record.id, inventory: inventory) }
        for (id, reply) in replies where reply.stage == .published && !reply.deleted {
            guard publishedAt[id, default: 0] <= inventory.observedAt, let url = reply.outputURL,
                  inventory.confirmsAbsence(of: url) else { continue }
            fileRemoved(url)
        }
        prune(now: now, inventory: inventory)
        importNext()
    }

    /// The destination a reply's card came from, so Reply goes back to the same conversation.
    func origin(of url: URL) -> AgentDestination? {
        guard let id = ReplyProtocol.replyID(fromFileName: url.lastPathComponent),
              let reply = replies[id], reply.destination == nil || reply.outputURL == url.standardizedFileURL,
              let request = requests[reply.requestID] else { return nil }
        return AgentDestination(id: request.destinationID, name: request.destinationName, address: request.address)
    }

    /// The agent answered `request` with a reply Vignette kept, whether or not its card is up yet.
    func hasReply(to request: String) -> Bool {
        replies.values.contains { $0.requestID == request && $0.stage != .failed && $0.stage != .cancelled }
    }

    // MARK: Sending

    /// A send refused before the client was invoked, with what the person reads about it.
    struct Refusal: Error { let reason: String }

    /// Stores the drawing and the request, then hands it to the client. The store happens first and
    /// on the main thread: once this answers, the request exists whatever the client does next, and
    /// the annotator may close. The client gets the line `grace` seconds later, or at once when that
    /// is 0 (`SendGrace`); the submission then runs off the main thread and reports through `[send]`
    /// and `callbacks.delivered`. Throws a `Refusal` when no live request was admitted.
    @discardableResult
    func send(png: Data, source: URL, to destination: AgentDestination, message: String? = nil,
              instructions: String = SettingsData.defaultSendInstructions, grace: TimeInterval = 0) throws -> Record {
        let open = requests.values.filter { $0.status != .cleared }.sorted { $0.created < $1.created }
        guard open.count <= Self.maxLiveRequests else {
            Log.write("[send] error \(CommandError.writeFailed.rawValue) too many open requests: \(open.count)")
            throw Refusal(reason: SubmissionOutcome.internalReason)
        }
        let id = ReplyProtocol.newID()
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: id)
        let record = Record(id: id, created: Date(), destinationID: destination.id,
                            destinationName: destination.name, address: destination.address,
                            addressGuard: destination.address.guardTier, source: source.lastPathComponent,
                            status: .prepared, detail: "")
        let ticket = ReplyProtocol.Ticket(requestID: id, secret: ReplyProtocol.newSecret(),
                                          requestDirectory: directory.path, app: Bundle.main.bundlePath)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("image.png"), options: .atomic)
            try encode(ticket, to: directory.appendingPathComponent("ticket.json"))
            try write(record)
        } catch {
            Log.write("[send] error \(CommandError.writeFailed.rawValue) \(directory.path): \(error.localizedDescription)")
            throw Refusal(reason: "Vignette couldn't save the request. \(error.localizedDescription)")
        }
        requests[id] = record
        if open.count == Self.maxLiveRequests, let oldest = open.first {
            do {
                _ = try clear(oldest.id)
                Log.write("[requests] cleared \(oldest.id) \(oldest.destinationName): the oldest of \(Self.maxLiveRequests) open")
            } catch {
                do {
                    try FileManager.default.removeItem(at: directory)
                    requests[id] = nil
                } catch {
                    var cancelled = record
                    cancelled.status = .cleared
                    cancelled.detail = "not submitted: request admission failed"
                    do {
                        try write(cancelled)
                        requests[id] = cancelled
                        cleanup(id)
                    } catch {
                        Log.write("[send] error \(CommandError.writeFailed.rawValue) unsubmitted request \(id) could not be discarded: \(error.localizedDescription)")
                    }
                }
                Log.write("[send] error \(CommandError.writeFailed.rawValue) could not clear \(oldest.id): \(error.localizedDescription)")
                throw Refusal(reason: SubmissionOutcome.internalReason)
            }
        }
        prune()
        Log.write("[send] prepared \(id) to \(destination.name) (\(destination.address.description)) \(png.count) bytes")
        if grace > 0 { Log.write("[send] waiting \(Int(grace * 1000))ms request=\(id)") }
        // The message travels in the line only: it is the person's words, so neither the record
        // nor the log keeps it.
        let line = Self.requestLine(record: record, root: root, message: message, instructions: instructions)
        run(sendGrace.handle(.sent(request: id, file: source.standardizedFileURL.path, line: line, grace: grace, at: now())))
        return record
    }

    /// Carries out what `SendGrace` decided.
    private func run(_ effects: [SendGrace.Effect]) {
        for effect in effects {
            switch effect {
            case .arm(let id, let seconds):
                schedule(seconds) { [weak self] in
                    guard let self else { return }
                    run(sendGrace.handle(.due(request: id, at: now())))
                }
            case .submit(let id, let line, let waited):
                guard let record = requests[id], record.status == .prepared else { continue }
                if let waited {
                    Log.write("[send] released request=\(id) after=\(Int(waited * 1000))ms")
                    callbacks.released(record)
                }
                submit(record, line: line)
            case .discard(let id):
                do { try clear(id) }
                catch { Log.write("[send] error \(CommandError.writeFailed.rawValue) could not clear \(id): \(error.localizedDescription)") }
                Log.write("[send] cancelled request=\(id) before it was sent")
                if let record = requests[id] { callbacks.cancelled(record) }
            case .dropped(let id):
                Log.write("[send] cancelled request=\(id) before it was sent: its request was cleared")
                if let record = requests[id] { callbacks.cancelled(record) }
            }
        }
    }

    /// Hands one prepared request to its client and records what came back.
    private func submit(_ record: Record, line: String) {
        let id = record.id
        let noClient = handOver(record, line: line, detail: "Vignette handed the line over and has no answer yet") { outcome in
            DispatchQueue.main.async { MainActor.assumeIsolated { self.finishSubmission(id, outcome) } }
        }
        if let noClient { finishSubmission(id, noClient) }
    }

    /// Asks the record's client to take `line`, off the main thread, and answers `completion` there.
    /// Answers the outcome at once, and never calls `completion`, when the record has no client to ask.
    private func handOver(_ record: Record, line: String, detail: String,
                          completion: @escaping @Sendable (SubmissionOutcome) -> Void) -> SubmissionOutcome? {
        guard let connection = connections[record.address.client] else {
            return .notSubmitted(code: .noAgent, detail: "no connection for \(record.address.client.rawValue)",
                                 reason: SubmissionOutcome.internalReason)
        }
        // Stored as uncertain before the line leaves: `load` clears a request still prepared as one whose
        // line never went, and this one's client may have it, with a call that can run 25 s.
        var going = record
        going.status = .uncertain
        going.detail = detail
        requests[record.id] = going
        do { try write(going) }
        catch { Log.write("[send] error \(CommandError.writeFailed.rawValue) could not store \(record.id): \(error.localizedDescription)") }
        let destination = AgentDestination(id: record.destinationID, name: record.destinationName, address: record.address)
        DispatchQueue.global(qos: .userInitiated).async { completion(connection.submit(line, to: destination)) }
        return nil
    }

    private func finishSubmission(_ id: String, _ outcome: SubmissionOutcome) {
        guard let record = recordOutcome(outcome, for: id) else { return }
        callbacks.delivered(record, outcome)
    }

    /// Writes what the client answered into the request's record and logs it. Answers the record.
    private func recordOutcome(_ outcome: SubmissionOutcome, for id: String) -> Record? {
        guard var record = requests[id] else { return nil }
        if record.status != .cleared {
            switch outcome {
            case .accepted, .queued: record.status = .submitted
            case .uncertain: record.status = .uncertain
            case .notSubmitted, .destinationChanged: record.status = .failed
            }
            record.detail = outcome.isAccepted ? "" : outcome.detail
            requests[id] = record
            do { try write(record) }
            catch { Log.write("[send] error \(CommandError.writeFailed.rawValue) could not store submission \(id): \(error.localizedDescription)") }
        }
        switch outcome {
        case .accepted(let detail):
            Log.write("[send] ok \(id) \(record.destinationName) \(detail)")
        case .queued(let detail, _):
            Log.write("[send] queued \(id) \(record.destinationName) \(detail)")
        case .uncertain(let detail, _):
            Log.write("[send] uncertain \(id) \(record.destinationName) \(detail)")
        case .destinationChanged(let detail, _):
            Log.write("[send] error \(CommandError.noAgent.rawValue) \(id) \(detail)")
        case .notSubmitted(let code, let detail, _):
            Log.write("[send] error \(code.rawValue) \(id) \(detail)")
        }
        return record
    }

    /// Don't send: cancels every send of `file` still in its grace, clears their requests and tells
    /// the cards. Answers the requests it cancelled, and nothing when none was waiting: the line was
    /// handed over already, or there was no send.
    @discardableResult
    func unsend(file: URL) -> [Record] {
        let effects = sendGrace.handle(.cancelled(file: file.standardizedFileURL.path))
        let cancelled = effects.compactMap { effect -> Record? in
            if case .discard(let id) = effect { return requests[id] }
            return nil
        }
        run(effects)
        return cancelled
    }

    /// The deadline, in `now`'s clock, and length of a send still in its grace; nil once it was
    /// handed over, cancelled, or had none.
    func grace(of request: String) -> SendNotice.Grace? {
        sendGrace.wait(of: request).map { SendNotice.Grace(deadline: $0.deadline, length: $0.length) }
    }

    /// Quit: hands every waiting send to its client now and waits up to `limit` for the answers,
    /// since quitting is not a retraction and the process ends right after. Records what came back
    /// and calls no callbacks: the cards are going too. A send with no answer by then stays
    /// uncertain, as a call that did not answer always is.
    func releaseHeld(waitingUpTo limit: TimeInterval = 2) {
        let outcomes = Outcomes()
        let group = DispatchGroup()
        var handedOver: [String] = []
        for case .submit(let id, let line, _) in sendGrace.handle(.quit) {
            guard let record = requests[id], record.status == .prepared else { continue }
            handedOver.append(id)
            group.enter()
            if let noClient = handOver(record, line: line, detail: "Vignette quit while the line was going",
                                       completion: { outcomes.set(id, $0); group.leave() }) {
                outcomes.set(id, noClient)
                group.leave()
            } else {
                Log.write("[send] released at quit request=\(id)")
            }
        }
        if group.wait(timeout: .now() + limit) == .timedOut {
            let missing = handedOver.filter { outcomes.all[$0] == nil }
            Log.write("[send] error uncertain released at quit: no answer in \(Int(limit * 1000))ms for \(missing.joined(separator: ","))")
        }
        for (id, outcome) in outcomes.all { _ = recordOutcome(outcome, for: id) }
    }

    /// The answers that came back from `releaseHeld`'s submissions, written by their queues.
    private final class Outcomes: @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [String: SubmissionOutcome] = [:]
        func set(_ id: String, _ outcome: SubmissionOutcome) { lock.lock(); answers[id] = outcome; lock.unlock() }
        var all: [String: SubmissionOutcome] { lock.lock(); defer { lock.unlock() }; return answers }
    }

    /// The one line the agent receives, which arrives in the person's session as their own message.
    /// It names only the image, then says `instructions` (`sendInstructions` in settings.json, one
    /// line); the skill says how to answer with a drawing, using the `ticket.json` beside it. "From Vignette:" and the
    /// image are fixed, because the skill loads on the one and the drawing is the other. The person's
    /// message, already one line (`AnnotatorToolbar.Model.sentMessage`), leads, as the request, and
    /// the Vignette part follows in brackets, as a note on what came with it. One line, because
    /// the plugin's monitor makes each line it prints one message. The ticket's secret never travels.
    static func requestLine(record: Record, root: URL, message: String? = nil,
                            instructions: String = SettingsData.defaultSendInstructions) -> String {
        let image = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent("image.png").path
        let note = "From Vignette: \"\(image)\"." + (instructions.isEmpty ? "" : " \(instructions)")
        return message.map { "\($0) [\(note)]" } ?? note
    }

    // MARK: Accepting a reply

    /// `vignette://reply?file=<attempt envelope>`. Validates the envelope, takes ownership of the
    /// reply's bytes, commits it, and only then acknowledges. Answers exactly one `[reply]` line.
    func receiveReply(envelope: URL) {
        do {
            let attempt = try ReplyProtocol.readAttempt(at: envelope, root: root)
            guard let request = requests[attempt.requestID] else {
                // Nothing to write a receipt into that is not a path a caller chose. The helper
                // sees no receipt and reports the submission as unconfirmed.
                throw ReplyProtocol.Problem(.unknownRequest, "no request \(attempt.requestID)")
            }
            do {
                try accept(attempt, request: request)
            } catch let problem as ReplyProtocol.Problem {
                reject(attempt, problem)
            }
        } catch let problem as ReplyProtocol.Problem {
            Commands.error("reply", .replyRefused, "\(problem.code.rawValue) \(problem.description)")
        } catch {
            Commands.error("reply", .replyRefused, "\(error)")
        }
    }

    private func accept(_ attempt: ReplyProtocol.Attempt, request: Record) throws {
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: request.id)
        guard let ticket: ReplyProtocol.Ticket = decode(directory.appendingPathComponent("ticket.json")),
              ReplyProtocol.secretsMatch(ticket.secret, attempt.secret) else {
            throw ReplyProtocol.Problem(.badAuthorization, "the reply ticket does not authorize this request")
        }
        // An already-known reply answers from its own record: the same payload gets the state it
        // already has, a different one is refused without touching what was accepted.
        if let existing = replies[attempt.replyID] {
            guard existing.requestID == attempt.requestID else {
                throw ReplyProtocol.Problem(.conflictingReply, "reply \(attempt.replyID) belongs to another request")
            }
            guard existing.digest == attempt.payloadDigest else {
                throw ReplyProtocol.Problem(.conflictingReply, "reply \(attempt.replyID) was accepted with other bytes")
            }
            writeReceipt(attempt, for: existing)
            Commands.ok("reply", "\(attempt.replyID) already \(existing.stage.rawValue)")
            return
        }
        guard request.takesReplies else {
            throw ReplyProtocol.Problem(.requestClosed, "request \(request.id) was cleared")
        }
        let (bundle, image, digest) = try ReplyProtocol.readBundle(for: attempt, root: root)
        guard digest == attempt.payloadDigest else {
            throw ReplyProtocol.Problem(.digestMismatch, "the bundle's bytes are not the ones this attempt names")
        }
        // Ownership first: every byte is copied into the app's own storage and the record is
        // committed before anything is acknowledged, so an accepted reply survives the helper
        // deleting all of its files.
        let reply = Reply(id: bundle.replyID, requestID: request.id, digest: digest,
                          hasImage: bundle.hasImage, marks: bundle.marks, answer: bundle.answer, stage: .accepted)
        do {
            if let image {
                let url = payloadImageURL(reply)
                // The directory first: `Data.write` creates no intermediate directory, and this is
                // the first thing written for a request whose replies have all been marks so far.
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try image.write(to: url, options: .atomic)
            }
            try write(reply)
        } catch {
            throw ReplyProtocol.Problem(.storeFailed, "could not store the reply: \(error.localizedDescription)")
        }
        replies[reply.id] = reply
        pendingImports.append(reply.id)
        writeReceipt(attempt, for: reply)
        Commands.ok("reply", "\(reply.id) accepted for \(request.id) marks=\(reply.marks.count)\(reply.hasImage ? " image" : "")\(reply.answer == nil ? "" : " answer")")
        importNext()
    }

    private func reject(_ attempt: ReplyProtocol.Attempt, _ problem: ReplyProtocol.Problem) {
        // The attempt id names the receipt, and a caller that failed authorization chose it without
        // proving anything. It may leave a refusal where there is none; it may not replace the
        // answer a genuine attempt is waiting for. Every other refusal came from a ticket holder.
        let url = ReplyProtocol.receiptURL(root: root, requestID: attempt.requestID, attemptID: attempt.attemptID)
        if problem.code == .badAuthorization && FileManager.default.fileExists(atPath: url.path) {
            Commands.error("reply", .replyRefused, "\(problem.code.rawValue) \(problem.description)")
            return
        }
        writeReceipt(attempt, acceptance: .rejected, publication: nil, errorCode: problem.code.rawValue)
        Commands.error("reply", .replyRefused, "\(problem.code.rawValue) \(problem.description)")
    }

    /// The acknowledgement, at a path Vignette derives from the attempt's own ids. Atomic, so a
    /// helper reading it never sees half a file.
    private func writeReceipt(_ attempt: ReplyProtocol.Attempt, acceptance: ReplyProtocol.Receipt.Acceptance,
                              publication: ReplyProtocol.Receipt.Publication?, errorCode: String?, notDrawn: [Int]? = nil) {
        write(ReplyProtocol.Receipt(
            requestID: attempt.requestID, replyID: attempt.replyID, attemptID: attempt.attemptID,
            payloadDigest: attempt.payloadDigest, acceptance: acceptance, publication: publication, errorCode: errorCode,
            notDrawn: notDrawn))
    }

    /// An accepted attempt's acknowledgement: where its reply has reached, from the reply's record.
    private func writeReceipt(_ attempt: ReplyProtocol.Attempt, for reply: Reply) {
        writeReceipt(attempt, acceptance: .accepted, publication: reply.publication, errorCode: reply.errorCode,
                     notDrawn: reply.notDrawn)
    }

    private func write(_ receipt: ReplyProtocol.Receipt) {
        let url = ReplyProtocol.receiptURL(root: root, requestID: receipt.requestID, attemptID: receipt.attemptID)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encode(receipt, to: url)
        } catch {
            // Derived from the authoritative record, so a repeated submission rebuilds it.
            Log.write("[reply] error write-failed receipt \(receipt.attemptID): \(error.localizedDescription)")
        }
    }

    // MARK: Importing

    /// Publishes the next pending reply, one at a time.
    private func importNext() {
        guard publicationReady, !importing, let id = pendingImports.first, let reply = replies[id] else { return }
        guard let request = requests[reply.requestID], request.takesReplies else {
            pendingImports.removeAll { $0 == id }
            fail(id, stage: .cancelled, code: "request-cleared")
            importNext()
            return
        }
        importing = true
        publish(reply) { [weak self] in
            guard let self else { return }
            self.importing = false
            self.pendingImports.removeAll { $0 == id }
            self.importNext()
        }
    }

    /// One reply, from owned bytes to a card. The reserved name is excluded from everything until
    /// the last step, so a stop anywhere in here leaves no ordinary file and no half-drawn card.
    private func publish(_ reply: Reply, done: @escaping () -> Void) {
        if let answer = reply.answer, reply.stage == .accepted, let request = requests[reply.requestID] {
            return callbacks.presentLive(request, answer) { [weak self] notDrawn in
                guard let self else { return done() }
                guard let notDrawn else { return self.publishCard(reply, done: done) }
                guard requests[reply.requestID]?.takesReplies == true, var shownReply = replies[reply.id],
                      shownReply.stage == .accepted else { return done() }
                shownReply.stage = .shown
                shownReply.notDrawn = notDrawn
                replies[reply.id] = shownReply
                if (try? write(shownReply)) == nil { Log.write("[reply] error write-failed \(reply.id) shown") }
                Log.write("[reply] shown \(reply.id) as a live ink result marks=\(answer.marks.count)")
                done()
            }
        }
        publishCard(reply, done: done)
    }

    private func publishCard(_ reply: Reply, done: @escaping () -> Void) {
        var reply = reply

        // 1. Reserve the name. Persisting the record is what installs the exclusion, because
        //    `isVisible` reads the record; there is no second ledger to keep in step.
        if reply.stage == .accepted {
            reply.destination = callbacks.watchFolder().appendingPathComponent(reply.fileName).standardizedFileURL
            reply.stage = .reserved
            replies[reply.id] = reply
            guard (try? write(reply)) != nil else { fail(reply.id, stage: .failed, code: "reserve-failed"); return done() }
            Log.write("[reply] reserved \(reply.fileName)")
        }
        guard let destination = reply.outputURL else {
            fail(reply.id, stage: .failed, code: "destination-unknown"); return done()
        }
        let folder = destination.deletingLastPathComponent()

        // 2. The owned PNG, copied atomically. An existing file here is this reply's own from an
        //    interrupted run, since the name carries its id; nothing else may use this name.
        let source = reply.hasImage ? payloadImageURL(reply) : ReplyProtocol.requestDirectory(root: root, requestID: reply.requestID).appendingPathComponent("image.png")
        guard let bytes = try? Data(contentsOf: source), Commands.isReadableImage(source) else {
            fail(reply.id, stage: .failed, code: "payload-unreadable"); return done()
        }
        guard FileManager.default.fileExists(atPath: folder.path) else {
            // The watch folder is gone: the person renamed it, or its volume left. Stop rather than
            // recreate a folder this reply was never reserved in.
            fail(reply.id, stage: .failed, code: "destination-changed"); return done()
        }
        do { try bytes.write(to: destination, options: .atomic) }
        catch { fail(reply.id, stage: .failed, code: "copy-failed"); return done() }

        // 3. The marks, in a drawing the person edits like their own. An image-only reply needs none.
        let agent = requests[reply.requestID]?.address.client.rawValue
        let marks = reply.cardMarks(on: reply.answer == nil ? nil : callbacks.cardCanvas(destination, agent))
        guard !marks.isEmpty else { return commit(reply, at: destination, done: done) }
        callbacks.installDrawing(Screenshot(url: destination), marks, agent) { [weak self] failure in
            guard let self else { return }
            // Clearing can remove the reserved file while installation is pending. The request
            // remains cancelled even when that installation later reports a failure.
            guard stillReserved(reply, at: destination) else { return done() }
            if let failure {
                // The codes stay the ones receipts have always carried for these two failures.
                let code = failure.code == .writeFailed ? "draft-store-failed" : "draft-failed"
                Log.write("[reply] error \(code) \(reply.id): \(failure)")
                self.fail(reply.id, stage: .failed, code: code)
                return done()
            }
            self.commit(reply, at: destination, done: done)
        }
    }

    /// The single publication point: the PNG and the drawing it needs are both there, so the record
    /// goes to `published` and only then is the file an ordinary one with a card.
    private func commit(_ reply: Reply, at url: URL, done: @escaping () -> Void) {
        guard stillReserved(reply, at: url) else { return done() }
        var reply = reply
        reply.stage = .published
        reply.errorCode = nil
        if reply.answer != nil { reply.notDrawn = reply.undrawnOnCard }
        guard (try? write(reply)) != nil else { fail(reply.id, stage: .failed, code: "publish-failed"); return done() }
        replies[reply.id] = reply
        publishedAt[reply.id] = ProcessInfo.processInfo.systemUptime
        if let client = requests[reply.requestID]?.address.client { Agent.record(client.rawValue, on: url) }
        Log.write("[reply] published \(reply.fileName) marks=\(reply.cardMarks(on: nil).count)")
        callbacks.present(Screenshot(url: url))
        done()
    }

    /// Whether the import may go on. The record may have moved since it started: its marks are
    /// installed on a later actor turn, and a clear cancels the import in that
    /// time. The stage on disk decides, not the copy this import has been carrying, and the reserved
    /// file goes with the cancellation.
    private func stillReserved(_ reply: Reply, at url: URL) -> Bool {
        guard requests[reply.requestID]?.takesReplies == true, replies[reply.id]?.stage == .reserved else {
            try? FileManager.default.removeItem(at: url)
            Log.write("[reply] dropped \(reply.fileName); the request was cleared")
            return false
        }
        return true
    }

    /// Stops one import with a reason, keeping the payload and the exclusion. The receipt is
    /// derived from the record, so a repeated submission reports this state.
    private func fail(_ id: String, stage: Reply.Stage, code: String) {
        guard var reply = replies[id] else { return }
        reply.stage = stage
        reply.errorCode = code
        replies[id] = reply
        try? write(reply)
        Log.write("[reply] error \(code) \(id)")
        if stage == .failed, let request = requests[reply.requestID] {
            // The agent can fix an image or marks that did not read; a write that failed here cannot.
            let theAgents = code == "payload-unreadable" || code == "draft-failed"
            callbacks.replyFailed(request, theAgents ? "You can ask \(request.address.client.label) to send it again." : "Vignette couldn't save the reply. The log has details.")
        }
    }

    // MARK: Clearing

    /// `vignette://requests[?clear=<id|all>]`. Listing says what is open; clearing stops a request
    /// taking new replies, cancels its unpublished imports, and removes only files Vignette owns.
    /// Published cards are the person's and are left alone.
    func run(clear: String?) {
        guard let clear, !clear.isEmpty else {
            for record in requests.values.sorted(by: { $0.created < $1.created }) {
                let count = replies.values.filter { $0.requestID == record.id }.count
                let why = record.detail.isEmpty ? "" : " \(record.detail)"
                Log.write("[requests] \(record.id) \(record.status.rawValue) \(record.destinationName) \(record.address.description) source=\(record.source) replies=\(count)\(why)")
            }
            Commands.ok("requests", "\(requests.count) requests, \(replies.count) replies")
            return
        }
        let targets = clear == "all" ? Array(requests.keys) : [clear]
        var cleared = 0
        var failures: [String] = []
        for id in targets {
            do { if try self.clear(id) { cleared += 1 } }
            catch { failures.append("\(id): \(error.localizedDescription)") }
        }
        if !failures.isEmpty {
            Commands.error("requests", .writeFailed, "cleared \(cleared); \(failures.joined(separator: "; "))")
            return
        }
        guard cleared > 0 else { Commands.error("requests", .missingFile, "no request \(clear)"); return }
        Commands.ok("requests", "cleared \(cleared)")
    }

    /// Deletes the folders of requests cleared more than `clearedKept` ago, dated by `request.json`,
    /// which clearing rewrites. Published replies need current proof of absence at their recorded location.
    func prune(now: Date = Date(), inventory: ScreenshotWatcher.Inventory? = nil) {
        let fm = FileManager.default
        for record in requests.values where record.status == .cleared {
            let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
            let file = directory.appendingPathComponent(Self.recordFileName)
            guard let cleared = (try? fm.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(cleared) > Self.clearedKept else { continue }
            let own = replies.values.filter { $0.requestID == record.id }
            guard !own.contains(where: { $0.needsOutputCleanup == true }) else { continue }
            guard !own.contains(where: { reply in
                guard reply.stage == .published else { return false }
                guard let inventory, let url = reply.outputURL,
                      publishedAt[reply.id, default: 0] <= inventory.observedAt else { return true }
                return !inventory.confirmsAbsence(of: url)
            })
            else { continue }
            guard (try? fm.removeItem(at: directory)) != nil else { continue }
            requests[record.id] = nil
            for reply in own {
                replies[reply.id] = nil
                publishedAt[reply.id] = nil
                pendingCleanupWrites.remove(reply.id)
            }
            Log.write("[requests] removed \(record.id), cleared \(Int(now.timeIntervalSince(cleared) / 86400)) days ago")
        }
    }

    /// Terminal state commits before any owned payload is removed.
    @discardableResult
    private func clear(_ id: String) throws -> Bool {
        // The one place a request is cleared, so a clear by URL or by admission stops a waiting send
        // too. The cards hear of it once the clear has been tried: the line is not going either way.
        let stopped = sendGrace.handle(.cleared(request: id))
        defer { run(stopped) }
        guard var record = requests[id] else { return false }
        if record.status != .cleared {
            record.status = .cleared
            try write(record)
            requests[id] = record
        }
        cleanup(id)
        return true
    }

    private func cleanup(_ id: String, inventory: ScreenshotWatcher.Inventory? = nil) {
        guard requests[id]?.status == .cleared else { return }
        for reply in replies.values where reply.requestID == id && reply.stage != .published {
            if reply.stage == .cancelled, reply.errorCode == "request-cleared", reply.needsOutputCleanup == false,
               !pendingCleanupWrites.contains(reply.id) { continue }
            pendingImports.removeAll { $0 == reply.id }
            var cancelled = reply
            if cancelled.needsOutputCleanup == nil {
                cancelled.needsOutputCleanup = reply.stage != .accepted || reply.destination != nil
            }
            cancelled.stage = .cancelled
            cancelled.errorCode = "request-cleared"
            replies[reply.id] = cancelled
            if publicationReady, cancelled.needsOutputCleanup == true, let url = cancelled.outputURL {
                do {
                    try FileManager.default.removeItem(at: url)
                    cancelled.needsOutputCleanup = false
                } catch {
                    if inventory?.confirmsAbsence(of: url) == true { cancelled.needsOutputCleanup = false }
                    else { Log.write("[requests] error cleanup \(id): \(error.localizedDescription)") }
                }
            }
            replies[reply.id] = cancelled
            if cancelled.stage != reply.stage || cancelled.errorCode != reply.errorCode
                || cancelled.needsOutputCleanup != reply.needsOutputCleanup {
                pendingCleanupWrites.insert(reply.id)
            }
            guard pendingCleanupWrites.contains(reply.id) else { continue }
            do {
                try write(cancelled)
                pendingCleanupWrites.remove(reply.id)
            }
            catch { Log.write("[requests] error cleanup-state \(id): \(error.localizedDescription)") }
        }
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: id)
        for name in ["image.png", "submissions"] {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do { try FileManager.default.removeItem(at: url) }
            catch { Log.write("[requests] error cleanup \(id): \(error.localizedDescription)") }
        }
    }

    // MARK: The state report

    var stateJSON: [String: Any] {
        [
            "directory": root.path,
            "requests": requests.values.sorted { $0.created < $1.created }.map { record -> [String: Any] in
                var json: [String: Any] = ["id": record.id, "status": record.status.rawValue, "destination": record.destinationName,
                                           "address": record.address.description, "guard": record.addressGuard.rawValue, "source": record.source]
                if let grace = self.grace(of: record.id) { json["graceMs"] = Int(max(0, grace.deadline - self.now()) * 1000) }
                return json
            },
            "replies": replies.values.sorted { $0.id < $1.id }.map { reply -> [String: Any] in
                var json: [String: Any] = ["id": reply.id, "request": reply.requestID, "stage": reply.stage.rawValue,
                                           "file": reply.fileName, "marks": reply.marks.count, "deleted": reply.deleted]
                if let code = reply.errorCode { json["error"] = code }
                return json
            },
            "pendingImports": pendingImports,
        ]
    }

    // MARK: Files

    private func payloadImageURL(_ reply: Reply) -> URL {
        ReplyProtocol.requestDirectory(root: root, requestID: reply.requestID)
            .appendingPathComponent("payloads").appendingPathComponent(reply.id + ".png")
    }

    private func write(_ record: Record) throws {
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(record, to: directory.appendingPathComponent(Self.recordFileName))
    }

    private func write(_ reply: Reply) throws {
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: reply.requestID)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("replies"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("payloads"), withIntermediateDirectories: true)
        try encode(reply, to: directory.appendingPathComponent("replies").appendingPathComponent(reply.id + ".json"))
        refreshReceipts(of: reply)
    }

    /// Brings the receipts of the reply's accepted attempts up to its record, so a helper still
    /// waiting on an answer learns where it went and which of its marks were not drawn.
    private func refreshReceipts(of reply: Reply) {
        let folder = ReplyProtocol.requestDirectory(root: root, requestID: reply.requestID).appendingPathComponent("receipts")
        for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            guard var receipt: ReplyProtocol.Receipt = decode(url), receipt.replyID == reply.id,
                  receipt.payloadDigest == reply.digest, receipt.acceptance == .accepted else { continue }
            let before = receipt
            receipt.publication = reply.publication
            receipt.errorCode = reply.errorCode
            receipt.notDrawn = reply.notDrawn
            if receipt != before { write(receipt) }
        }
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func decode<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }
}

extension String {
    /// The words with one space between each, whatever line breaks, tabs or spaces were there: what
    /// the line Send puts in a session can hold, since the plugin's monitor makes each line one message.
    var asOneLine: String { split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}
