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
        /// Why the page's canvas cannot be borrowed, or nil when it is free.
        var canvasRefusal: () -> String? = { "no editor" }
        /// Turns marks into a draft without showing anything (`AnnotationController.buildDraft`).
        var buildDraft: (Screenshot, [AgentMark], @escaping (ParkResult?, String?) -> Void) -> Void = { _, _, done in done(nil, "no editor") }
        /// Stores a draft and its preview durably, or throws. Publication waits for this to succeed.
        var saveDraft: (String, Any, Data?) throws -> Void = { _, _, _ in }
        /// Shows a published reply's card. Managed replies never reach the watcher's capture path.
        var present: (Screenshot) -> Void = { _ in }
        var watchFolder: () -> URL = { FileManager.default.temporaryDirectory }
        /// One sentence for the person, on the stack's toast.
        var feedback: (String) -> Void = { _ in }
    }

    var callbacks = Callbacks()
    /// The connections, by client. Injected so a test never runs herdr or codex.
    var connections: [AgentClient: any AgentConnection] = [:]

    /// The most requests that may be live at once. A request holds a PNG and an agent may still be
    /// reading it, so the limit refuses a new send rather than deleting an old one behind the
    /// person's back; `vignette://requests?clear=all` is how room is made.
    static let maxLiveRequests = 50

    let root: URL
    private var requests: [String: Record] = [:]
    private var replies: [String: Reply] = [:]
    /// Replies waiting for the page's canvas to be free. In arrival order within a launch; a
    /// relaunch rebuilds it from the stored records, whose order is the store's.
    private var pendingImports: [String] = []
    private var importing = false

    init(root: URL) {
        self.root = root
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
            /// Stored and ready to submit; nothing has reached the client yet.
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
        var stage: Stage
        /// The person deleted the published file. Publication still happened and is not undone.
        var deleted = false
        var errorCode: String?

        enum Stage: String, Codable {
            /// Vignette owns every byte. The helper may release its bundle.
            case accepted
            /// The watch-folder name is reserved and excluded from everything.
            case reserved
            /// The card exists and is ordinary. The one publication point.
            case published
            /// The import stopped; the payload is kept and the name stays excluded.
            case failed
            /// The request was cleared before this reply was published.
            case cancelled
        }

        /// The reserved watch-folder name. Derived, so a record and its file cannot drift apart.
        var fileName: String { ReplyProtocol.replyFileName(id) }

        var publication: ReplyProtocol.Receipt.Publication {
            if deleted { return .removed }
            switch stage {
            case .accepted, .reserved: return .pending
            case .published: return .ready
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
    func load() {
        let fm = FileManager.default
        var loadedRequests = 0, loadedReplies = 0, unreadable = 0
        for directory in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            guard ReplyProtocol.isID(directory.lastPathComponent) else { continue }
            if let record: Record = decode(directory.appendingPathComponent("request.json")) {
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
        // A file that is gone is a removal the person made while the app was not running.
        for (id, reply) in replies where reply.stage == .published && !reply.deleted {
            if !fm.fileExists(atPath: callbacks.watchFolder().appendingPathComponent(reply.fileName).path) {
                replies[id]?.deleted = true
                try? write(replies[id]!)
            }
        }
        Log.write("[requests] loaded \(loadedRequests) requests \(loadedReplies) replies pending=\(pendingImports.count)\(unreadable > 0 ? " unreadable=\(unreadable)" : "") dir=\(root.path)")
    }

    // MARK: What the rest of the app asks

    /// Whether a watch-folder file may be listed, warmed, opened, or made into a card. Every
    /// consumer asks this, not only the directory listing: a cached result or a late watcher event
    /// would otherwise show a reply whose import is not finished. Fails closed on a managed name
    /// with no published record, which is also what an unreadable store leaves behind.
    func isVisible(_ url: URL) -> Bool {
        guard let id = ReplyProtocol.replyID(fromFileName: url.lastPathComponent) else { return true }
        return replies[id]?.stage == .published
    }

    /// Whether a new file in the watch folder is an ordinary capture. A managed reply never is: it
    /// is presented once by its own import, and a late watcher event for it must not copy it to
    /// the clipboard or open the editor.
    func isCapture(_ url: URL) -> Bool {
        ReplyProtocol.replyID(fromFileName: url.lastPathComponent) == nil
    }

    /// The person deleted a published reply. Publication happened; the recovery copy is not used
    /// to put the file back.
    func fileRemoved(_ url: URL) {
        guard let id = ReplyProtocol.replyID(fromFileName: url.lastPathComponent), var reply = replies[id], !reply.deleted else { return }
        reply.deleted = true
        replies[id] = reply
        try? write(reply)
        Log.write("[reply] removed \(reply.fileName)")
    }

    /// The destination a reply's card came from, so Reply goes back to the same conversation.
    func origin(of url: URL) -> AgentDestination? {
        guard let id = ReplyProtocol.replyID(fromFileName: url.lastPathComponent),
              let reply = replies[id], let request = requests[reply.requestID] else { return nil }
        return AgentDestination(id: request.destinationID, name: request.destinationName, address: request.address)
    }

    /// Every session that can be addressed right now: the ones each connection enumerates, plus
    /// the ones configured for a client that cannot. Blocks on a subprocess, so it runs off the
    /// main thread and answers on it.
    func destinations(_ completion: @escaping @Sendable @MainActor ([AgentDestination]) -> Void) {
        let connections = self.connections
        DispatchQueue.global(qos: .userInitiated).async {
            let found = connections.values.flatMap { $0.destinations() }.sorted { $0.name < $1.name }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(found) } }
        }
    }

    // MARK: Sending

    /// Stores the drawing and the request, then hands it to the client. The store happens first and
    /// on the main thread: once this answers, the request exists whatever the client does next, and
    /// the annotator may close. The submission follows off the main thread and reports through
    /// `[send]` and the toast.
    @discardableResult
    func send(png: Data, source: URL, to destination: AgentDestination) -> Record? {
        let live = requests.values.filter { $0.status != .cleared }.count
        guard live < Self.maxLiveRequests else {
            Log.write("[send] error \(CommandError.writeFailed.rawValue) \(live) requests are open; clear some with \(Identity.urlScheme)://requests?clear=all")
            return nil
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
            return nil
        }
        requests[id] = record
        Log.write("[send] prepared \(id) to \(destination.name) (\(destination.address.description)) \(png.count) bytes")
        submit(record, ticket: ticket)
        return record
    }

    /// Hands one prepared request to its client and records what came back.
    private func submit(_ record: Record, ticket: ReplyProtocol.Ticket) {
        guard let connection = connections[record.address.client] else {
            finishSubmission(record.id, .notSubmitted(code: .noAgent, detail: "no connection for \(record.address.client.rawValue)"))
            return
        }
        let destination = AgentDestination(id: record.destinationID, name: record.destinationName, address: record.address)
        let line = Self.requestLine(record: record, ticket: ticket, root: root)
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = connection.submit(line, to: destination)
            DispatchQueue.main.async { MainActor.assumeIsolated { self.finishSubmission(record.id, outcome) } }
        }
    }

    private func finishSubmission(_ id: String, _ outcome: SubmissionOutcome) {
        guard var record = requests[id] else { return }
        switch outcome {
        case .accepted: record.status = .submitted
        case .uncertain: record.status = .uncertain
        case .notSubmitted, .destinationChanged: record.status = .failed
        }
        record.detail = outcome.isAccepted ? "" : outcome.detail
        requests[id] = record
        try? write(record)
        switch outcome {
        case .accepted(let detail):
            Log.write("[send] ok \(id) \(record.destinationName) \(detail)")
            callbacks.feedback("Sent to \(record.destinationName)")
        case .uncertain(let detail):
            Log.write("[send] uncertain \(id) \(record.destinationName) \(detail)")
            callbacks.feedback("Delivery uncertain; check \(record.destinationName)")
        case .destinationChanged(let detail):
            Log.write("[send] error \(CommandError.noAgent.rawValue) \(id) \(detail)")
            callbacks.feedback("\(record.destinationName) is not there any more")
        case .notSubmitted(let code, let detail):
            Log.write("[send] error \(code.rawValue) \(id) \(detail)")
            callbacks.feedback("Could not send to \(record.destinationName); see the log")
        }
    }

    /// The one line the agent receives. One line because herdr submits it with Return, and the
    /// same shape for both clients so neither is a special case. The ticket's path travels; its
    /// secret does not, and neither does anything that would be worth logging.
    static func requestLine(record: Record, ticket: ReplyProtocol.Ticket, root: URL) -> String {
        let image = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent("image.png").path
        let helper = Self.helperPath
        // A fork answers to another scheme, so the helper is told which one rather than assuming.
        let scheme = Identity.urlScheme == "vignette" ? "" : " --scheme \(Identity.urlScheme)"
        return "Vignette request \(record.id): open the drawing at \"\(image)\" and do what it asks. "
            + "To answer with a drawing of your own, run: python3 \"\(helper)\" --ticket \"\(ticket.requestDirectory)/ticket.json\"\(scheme) --marks <marks.json>; "
            + "python3 \"\(helper)\" --help explains the mark format and what it answers."
    }

    /// The reply helper inside the app bundle. Always there and always current for this build, so
    /// the loop does not depend on the person having installed the skill.
    static var helperPath: String {
        (SkillInstaller.bundled?.appendingPathComponent("scripts/reply").path) ?? "vignette/scripts/reply"
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
            writeReceipt(attempt, acceptance: .accepted, publication: existing.publication, errorCode: existing.errorCode)
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
                          hasImage: bundle.hasImage, marks: bundle.marks, stage: .accepted)
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
        writeReceipt(attempt, acceptance: .accepted, publication: .pending, errorCode: nil)
        Commands.ok("reply", "\(reply.id) accepted for \(request.id) marks=\(reply.marks.count)\(reply.hasImage ? " image" : "")")
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
                              publication: ReplyProtocol.Receipt.Publication?, errorCode: String?) {
        let receipt = ReplyProtocol.Receipt(
            requestID: attempt.requestID, replyID: attempt.replyID, attemptID: attempt.attemptID,
            payloadDigest: attempt.payloadDigest, acceptance: acceptance, publication: publication, errorCode: errorCode)
        let url = ReplyProtocol.receiptURL(root: root, requestID: attempt.requestID, attemptID: attempt.attemptID)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encode(receipt, to: url)
        } catch {
            // Derived from the authoritative record, so a repeated submission rebuilds it.
            Log.write("[reply] error write-failed receipt \(attempt.attemptID): \(error.localizedDescription)")
        }
    }

    // MARK: Importing

    /// The page's canvas is free again: a session ended, a build finished, or the page came up.
    func canvasBecameAvailable() { importNext() }

    /// Publishes the next pending reply, one at a time. A reply whose canvas work is refused stays
    /// at the head of the queue for the next time the canvas is free.
    private func importNext() {
        guard !importing, let id = pendingImports.first, let reply = replies[id] else { return }
        guard let request = requests[reply.requestID], request.takesReplies else {
            pendingImports.removeFirst()
            fail(id, stage: .cancelled, code: "request-cleared")
            importNext()
            return
        }
        importing = true
        publish(reply) { [weak self] in
            guard let self else { return }
            self.importing = false
            // A reply that is still waiting for the canvas stays at the head of the queue: only a
            // finished one leaves it, and only then is there any point trying the next.
            guard let stage = self.replies[id]?.stage, stage != .accepted, stage != .reserved else { return }
            self.pendingImports.removeAll { $0 == id }
            self.importNext()
        }
    }

    /// One reply, from owned bytes to a card. The reserved name is excluded from everything until
    /// the last step, so a stop anywhere in here leaves no ordinary file and no half-drawn card.
    private func publish(_ reply: Reply, done: @escaping () -> Void) {
        let folder = callbacks.watchFolder()
        let destination = folder.appendingPathComponent(reply.fileName)
        var reply = reply

        // 1. Reserve the name. Persisting the record is what installs the exclusion, because
        //    `isVisible` reads the record; there is no second ledger to keep in step.
        if reply.stage == .accepted {
            reply.stage = .reserved
            replies[reply.id] = reply
            guard (try? write(reply)) != nil else { fail(reply.id, stage: .failed, code: "reserve-failed"); return done() }
            Log.write("[reply] reserved \(reply.fileName)")
        }

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

        // 3. The marks, as a draft the person edits like their own. An image-only reply needs none.
        guard !reply.marks.isEmpty else { return commit(reply, at: destination, done: done) }
        if let refusal = callbacks.canvasRefusal() {
            Log.write("[reply] waiting \(reply.id): \(refusal)")
            return done()
        }
        callbacks.buildDraft(Screenshot(url: destination), reply.marks) { [weak self] parked, error in
            guard let self else { return }
            guard error == nil, let snapshot = parked?.snapshot else {
                Log.write("[reply] error draft-failed \(reply.id): \(error ?? "the page built no snapshot")")
                self.fail(reply.id, stage: .failed, code: "draft-failed")
                return done()
            }
            do { try self.callbacks.saveDraft(destination.path, snapshot, parked?.preview) }
            catch {
                Log.write("[reply] error draft-failed \(reply.id): \(error.localizedDescription)")
                self.fail(reply.id, stage: .failed, code: "draft-store-failed")
                return done()
            }
            self.commit(reply, at: destination, done: done)
        }
    }

    /// The single publication point: the PNG, the draft it needs, and its preview are all there, so
    /// the record goes to `published` and only then is the file an ordinary one with a card.
    private func commit(_ reply: Reply, at url: URL, done: @escaping () -> Void) {
        // The record may have moved since this import started: `buildDraft` can be outstanding for
        // seconds, and a clear cancels it in that time. The stage on disk decides, not the copy
        // this import has been carrying, and the reserved file goes with the cancellation.
        guard replies[reply.id]?.stage == .reserved else {
            try? FileManager.default.removeItem(at: url)
            Log.write("[reply] dropped \(reply.fileName); the request was cleared")
            return done()
        }
        var reply = reply
        reply.stage = .published
        reply.errorCode = nil
        guard (try? write(reply)) != nil else { fail(reply.id, stage: .failed, code: "publish-failed"); return done() }
        replies[reply.id] = reply
        if let client = requests[reply.requestID]?.address.client { Agent.record(client.rawValue, on: url) }
        Log.write("[reply] published \(reply.fileName) marks=\(reply.marks.count)")
        callbacks.present(Screenshot(url: url))
        callbacks.feedback("\(requests[reply.requestID]?.destinationName ?? "An agent") replied")
        done()
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
        if stage == .failed { callbacks.feedback("A reply could not be imported; see the log") }
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
        for id in targets {
            guard var record = requests[id] else { continue }
            record.status = .cleared
            requests[id] = record
            try? write(record)
            for reply in replies.values where reply.requestID == id && reply.stage != .published {
                pendingImports.removeAll { $0 == reply.id }
                // A reserved name was copied into the watch folder but never shown. It is Vignette's
                // until publication, so clearing takes it back rather than leaving a hidden file.
                if reply.stage == .reserved {
                    try? FileManager.default.removeItem(at: callbacks.watchFolder().appendingPathComponent(reply.fileName))
                }
                fail(reply.id, stage: .cancelled, code: "request-cleared")
            }
            // Only this task's own files. The sent PNG goes; an agent that still holds the path
            // sees it disappear, which is what clearing means.
            try? FileManager.default.removeItem(at: ReplyProtocol.requestDirectory(root: root, requestID: id).appendingPathComponent("image.png"))
            try? FileManager.default.removeItem(at: ReplyProtocol.requestDirectory(root: root, requestID: id).appendingPathComponent("submissions"))
            cleared += 1
        }
        guard cleared > 0 else { Commands.error("requests", .missingFile, "no request \(clear)"); return }
        Commands.ok("requests", "cleared \(cleared)")
    }

    // MARK: The state report

    var stateJSON: [String: Any] {
        [
            "directory": root.path,
            "requests": requests.values.sorted { $0.created < $1.created }.map { record -> [String: Any] in
                ["id": record.id, "status": record.status.rawValue, "destination": record.destinationName,
                 "address": record.address.description, "guard": record.addressGuard.rawValue, "source": record.source]
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
        try encode(record, to: directory.appendingPathComponent("request.json"))
    }

    private func write(_ reply: Reply) throws {
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: reply.requestID)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("replies"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("payloads"), withIntermediateDirectories: true)
        try encode(reply, to: directory.appendingPathComponent("replies").appendingPathComponent(reply.id + ".json"))
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
