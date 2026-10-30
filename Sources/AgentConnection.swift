import Foundation

/// How Vignette reaches one agent session. The terminal a session happens to be displayed in is
/// not part of this: a destination is a conversation, and a connection is the native call that
/// puts a request into it. See docs/glossary.md for the words.
///
/// Two routes exist. Codex is addressed by its thread UUID alone, and the engine that owns the
/// thread refuses a UUID it does not have. Claude Code is addressed by its session id, through the
/// plugin's inboxes, and nothing on that route refuses a stale id, so Vignette checks that an inbox
/// still holds that exact session immediately before it writes. `AgentAddress.guardTier` is the
/// difference, and it is recorded on every request.
enum AgentClient: String, Codable, CaseIterable {
    case claude, codex

    /// What a person calls it. `rawValue` is also the `agent=` name a reply's card is badged with.
    var label: String { self == .claude ? "Claude Code" : "Codex" }
}

/// How strongly a destination's conversation is pinned at the moment of delivery.
enum AddressGuard: String, Codable {
    /// The receiving runtime resolves the conversation itself and fails when it is gone.
    case runtimeEnforced = "runtime-enforced"
    /// Vignette checks the conversation just before submitting. The window between the check and
    /// the submission is small but real, and it belongs to the person's own terminal.
    case preflight
}

/// The native identity of a destination, as its client understands it.
enum AgentAddress: Equatable, Codable {
    /// A Claude Code session id. The plugin's inboxes resolve it to the process running it at send time.
    case claudeSession(String)
    /// A Codex thread. `codex queue --thread` finds the engine that owns it, so there is nothing
    /// else to say: the UUID is the whole address.
    case codexThread(uuid: String)

    init(client: AgentClient, id: String) {
        switch client {
        case .claude: self = .claudeSession(id)
        case .codex: self = .codexThread(uuid: id)
        }
    }

    var client: AgentClient {
        switch self {
        case .claudeSession: return .claude
        case .codexThread: return .codex
        }
    }

    /// The session id or thread UUID.
    var id: String {
        switch self {
        case .claudeSession(let id): return id
        case .codexThread(let uuid): return uuid
        }
    }

    var guardTier: AddressGuard {
        switch self {
        case .claudeSession: return .preflight
        case .codexThread: return .runtimeEnforced
        }
    }

    /// How the address reads in `[state]` and in a request record's log line.
    var description: String {
        switch self {
        case .claudeSession(let id): return "claude session=\(id)"
        case .codexThread(let uuid): return "codex thread=\(uuid)"
        }
    }
}

/// One agent session a request may be addressed to.
struct AgentDestination: Equatable, Identifiable {
    /// Vignette's stable handle for it: the thread UUID for Codex, the session id for Claude
    /// Code. It is what a request records, so a reply's card can offer the conversation it came
    /// from.
    let id: String
    let name: String
    /// The project folder the session works in, shown beside its name.
    var detail: String = ""
    let address: AgentAddress
    /// When the session was last used, which is the order Send lists sessions in. Nil when its
    /// client could not say.
    var lastUsed: Date? = nil
    /// Why this is the session you came from, when it is: its agent's own app was in front, or
    /// herdr's focus is on its pane or beside it. Set only by `DestinationChoice` on the list it
    /// answers. Nil for every other session.
    var focus: Focus? = nil
    /// Where the session works: its repository, or else its folder. Filled by the client's listing.
    var place: Place = .none
    /// The checked-out branch when it is not the repository's default. Nil on the default branch,
    /// on a detached `HEAD`, and when it could not be read.
    var branch: String? = nil
    /// The label of the herdr tab the session runs in, when it runs in a herdr pane.
    var hostLabel: String? = nil
    /// When the session started, which numbers sessions with equal names.
    var started: Date? = nil
    /// Where the session is in its turns. Nil when its client does not report turns.
    var turn: SessionTurn? = nil
    /// The process whose Claude Code inbox held the session when it was listed, which names the
    /// inbox's folder. Nil for a Codex thread and for a session not listed from an inbox.
    var inbox: Int32? = nil
    /// The goal the inbox mod wrote for the session, and whether it has an open question for the person.
    var goal: String? = nil
    var needsYou = false
    /// Whether `name` is the session's own (its custom or AI title) rather than a stand-in.
    var hasOwnName = true
    /// When a drawing was last handed to this session, from the request records. Stamped by
    /// `SessionListing`; it orders the session menu.
    var lastSent: Date? = nil
    /// The folder a Claude Code session runs in, as its inbox says (`pwd -P`). Nil for a Codex thread.
    var folder: String? = nil
    /// How Vignette starts the session when a person sends to it: set on a Claude Code project's
    /// Continue last session and New session rows, which are not running (`StartableSessions`).
    /// Nil for a session that is running and can receive now.
    var start: SessionStart? = nil

    enum Focus: String, Equatable {
        /// Its agent's own app was the app in front, showing this session (`DestinationChoice`).
        case app
        /// herdr's focused pane runs this session (`DestinationChoice`, from `HerdrFocus`).
        case pane
        /// herdr's focused pane runs no agent, and this is the one session in that pane's tab
        /// (`DestinationChoice`, from `HerdrFocus`).
        case tab
    }

    var client: AgentClient { address.client }
    /// Its project folder's name, or the client's name when it has none.
    var project: String { detail.isEmpty ? client.label : detail }

    /// Whether this session is known to be in use, which is what Send's menu lists. A Claude Code
    /// session is listed only while the Vignette plugin's monitor runs in it. Nothing says which threads the Codex
    /// app has open, so a Codex thread counts when it was used in the last day: on 2026-09-25, 2 of
    /// the 15 threads listed had been, and the rest were 33 hours to 17 days old.
    func isActive(now: Date = Date()) -> Bool {
        switch address {
        case .claudeSession: return true
        case .codexThread: return lastUsed.map { now.timeIntervalSince($0) < Self.activeWindow } ?? false
        }
    }

    static let activeWindow: TimeInterval = 24 * 60 * 60
}

/// The whole boundary a client implementation has to fill. Everything else — the fixed image, the
/// request record, reply validation, receipts, import, and the cards — is Vignette's and is shared.
/// Every call blocks on a subprocess or the disk, so none runs on the main thread.
protocol AgentConnection: Sendable {
    var client: AgentClient { get }
    /// Whether this route's last list may stand in while a fresh one is asked for. Claude Code's may
    /// not: herdr's focus is read in the same job as its list, so a kept list would let the pick
    /// settle on the session used last before the focus arrives.
    var keepsList: Bool { get }
    /// The sessions this route can address right now. Empty when the route cannot enumerate.
    func destinations() -> [AgentDestination]
    /// The same, together with the session `id` when the route can find it though it is not among
    /// the ones it lists, such as a Codex thread used weeks ago that the Codex app shows.
    func destinations(including id: String) -> [AgentDestination]
    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome
    /// The same, answering `completion` off the main thread. The default runs `submit` on a pool
    /// thread; a route that waits on something it can poll answers when that comes. `watchingTurn`
    /// says a note will read the session's turn (`turn(of:)`) once the line is in, so a route that
    /// must start reading before the line goes does so then, and only then.
    func submit(_ line: String, to destination: AgentDestination, watchingTurn: Bool,
                completion: @escaping @Sendable (SubmissionOutcome) -> Void)
    /// Where the session is in its turns, or nil when the route cannot tell.
    func turn(of destination: AgentDestination) -> SessionTurn?
    /// Whether `turn(of:)` can tell a turn's start and end; a note card to a route that cannot is not watched.
    var reportsTurns: Bool { get }
}

/// Where a session is in its turns, as far as a request sent to it is concerned.
enum SessionTurn: Equatable {
    /// A request is still in the session's inbox: its turn has not started.
    case waiting
    case busy
    case idle
}

extension AgentConnection {
    var keepsList: Bool { false }
    func destinations(including id: String) -> [AgentDestination] { destinations() }
    func turn(of destination: AgentDestination) -> SessionTurn? { nil }
    var reportsTurns: Bool { false }

    func submit(_ line: String, to destination: AgentDestination, watchingTurn: Bool,
                completion: @escaping @Sendable (SubmissionOutcome) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { completion(submit(line, to: destination)) }
    }
}

// MARK: Claude Code, through the plugin's inbox

/// Claude Code has no command that puts a message into a session that is already running. The
/// Vignette plugin gives each session an inbox instead: a folder named by the Claude Code process,
/// which the plugin's monitor reads between turns, printing each request, which reaches Claude as
/// the person's message (agent-plugin/, docs/claude-code-without-herdr-2026-09-27.md). Vignette
/// addresses the session, and checks just before writing that the inbox still holds it: `/clear`
/// and `/resume` give the same process another session. What the menu says about a session comes
/// from its own transcript. herdr's focus is read beside this list (`SessionListing`, `HerdrFocus`).
struct ClaudeCodeConnection: AgentConnection {
    let client = AgentClient.claude
    let reportsTurns = true
    /// The inboxes, one folder per Claude Code process. Injected so a test never reads the real ones.
    var inboxes = AgentPlugin.inboxRoot
    /// Where Claude Code keeps its transcripts, one folder per project, for a session whose inbox
    /// does not name its transcript yet.
    var transcripts = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    /// What the inbox mod knows about each session, by session id. Injected so a test never reads the
    /// person's own store.
    var modStore: @Sendable () -> [String: InboxModStore.Entry] = { InboxModStore.read() }
    var isRunning: @Sendable (Int32) -> Bool = { kill($0, 0) == 0 }
    var now: @Sendable () -> Date = { Date() }
    /// Starts a session that is not running. Injected so a test never runs herdr.
    var launch: @Sendable (SessionStart, String) -> HerdrLauncher.Started = { HerdrLauncher().start($0, session: $1) }
    /// Runs the next look for a started session's inbox after a pause, on a pool thread. Injected so
    /// a test does not wait.
    var later: @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void = { delay, look in
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: look)
    }

    /// How long a started session has to come up with its inbox before the send gives up. `claude`
    /// starts, reads the session's transcript when it resumes one, and starts the plugin's monitor,
    /// which writes the inbox.
    static let startTimeout: TimeInterval = 45
    static let startPoll: TimeInterval = 0.25

    /// The monitor touches `alive` every 3 s. An inbox older than this has no monitor reading it.
    static let aliveWindow: TimeInterval = 10

    static let closed = "This session has ended. You can send it to another one."
    static let cleared = "This session was cleared. You can send it to another one."
    static let notStarted = "Vignette couldn't open a herdr tab for Claude Code. The log has details."
    static let notUpInTime = "Claude Code didn't open in time. You can send again once it's running."

    /// One inbox, as the plugin's scripts wrote it.
    struct Inbox: Equatable {
        let folder: URL
        let pid: Int32
        /// The session the process runs now.
        var session: String?
        /// The folder Claude Code runs in, which is the session's project.
        var cwd: String?
        /// The session's transcript, from the last hook that ran.
        var transcript: String?
        /// The sessions the process ran before this one, which `/clear` and `/resume` leave.
        var past: [String] = []
        /// When the monitor last said it was running.
        var alive: Date?
        /// When the `session` file was created and last written: when the session started in this
        /// process, and a time to order it by when its transcript has no message yet.
        var started: Date?
        var written: Date?
    }

    /// Every inbox under `root`. Nothing is read beyond the few short files in each.
    static func inboxes(in root: URL) -> [Inbox] {
        folders(in: root).compactMap(inbox(at:))
    }

    /// The folders under `root`, each an inbox when it is named by a process id.
    static func folders(in root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    }

    /// The inbox in `folder`, or nil when the folder is not named by a process id. A folder that has
    /// gone reads as an inbox with nothing in it.
    static func inbox(at folder: URL) -> Inbox? {
        guard let pid = Int32(folder.lastPathComponent), pid > 0 else { return nil }
        func text(_ name: String) -> String {
            (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? ""
        }
        func line(_ name: String) -> String? {
            let line = text(name).trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? nil : line
        }
        let alive = (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("alive").path))?[.modificationDate] as? Date
        let session = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("session").path)
        return Inbox(folder: folder, pid: pid, session: line("session"), cwd: line("cwd"), transcript: line("transcript"),
                     past: text("past").split(whereSeparator: \.isNewline).map(String.init), alive: alive,
                     started: session?[.creationDate] as? Date, written: session?[.modificationDate] as? Date)
    }

    /// From the inbox the session was listed from: `waiting` while a request is still in it, since
    /// the monitor hands requests over only between turns; otherwise the `turn` file the plugin's
    /// hooks write, `busy` from a prompt to the end of the turn and `idle` after it. Only that one
    /// folder is read, and it must still be live and hold this exact session, as `submit` checks;
    /// a folder that has gone or holds another session reads as no turn. It reads files, so it
    /// never runs on the main thread.
    func turn(of destination: AgentDestination) -> SessionTurn? {
        listedInbox(of: destination).flatMap(Self.turn(of:))
    }

    /// The inbox `destination` was listed from, while it is live and still holds that session.
    private func listedInbox(of destination: AgentDestination) -> Inbox? {
        guard case .claudeSession(let session) = destination.address, let pid = destination.inbox,
              let inbox = Self.inbox(at: inboxes.appendingPathComponent(String(pid))),
              inbox.session == session, isLive(inbox) else { return nil }
        return inbox
    }

    /// The live inbox holding `session` now, whichever process it is in.
    private func liveInbox(holding session: String) -> Inbox? {
        liveInboxes().first { $0.session == session }
    }

    /// Whether a started session came up: the inbox that holds it, or what the send comes to.
    private enum StartAnswer {
        case up(Inbox)
        case failed(SubmissionOutcome)
    }

    /// Starts session `session` in a new herdr tab and answers once a live inbox holds it, looking
    /// every `startPoll` for up to `startTimeout`. Only the inbox folders made since the launch are
    /// looked at, and only their `session` file until one names it. It blocks on herdr to launch.
    private func startSession(_ start: SessionStart, session: String, answer: @escaping @Sendable (StartAnswer) -> Void) {
        guard UUID(uuidString: session) != nil else {
            return answer(.failed(.notSubmitted(code: .noAgent, detail: "not a session id: \(session)", reason: SubmissionOutcome.internalReason)))
        }
        // Resumed by hand since it was listed: it is running, and a second process would fork it.
        if let inbox = liveInbox(holding: session) { return answer(.up(inbox)) }
        let before = Set(Self.folders(in: inboxes).map(\.lastPathComponent))
        let began = now()
        switch launch(start, session) {
        case .failed(let detail):
            return answer(.failed(.notSubmitted(code: .sendFailed, detail: "could not start \(session) in \(start.folder): \(detail)",
                                                reason: Self.notStarted)))
        case .started(let tab, let pane):
            Log.write("[send] started claude \(start.arguments(session: session).joined(separator: " ")) in \(start.folder) tab=\(tab) pane=\(pane)")
        }
        look(for: session, in: start, besides: before, since: began, answer: answer)
    }

    private func look(for session: String, in start: SessionStart, besides before: Set<String>, since began: Date,
                      answer: @escaping @Sendable (StartAnswer) -> Void) {
        let made = Self.folders(in: inboxes).filter { !before.contains($0.lastPathComponent) }
        let holding = made.lazy.filter { folder in
            (try? String(contentsOf: folder.appendingPathComponent("session"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) == session
        }.compactMap(Self.inbox(at:)).first(where: isLive)
        if let holding {
            Log.write("[send] session \(session) came up after=\(Int(now().timeIntervalSince(began) * 1000))ms")
            return answer(.up(holding))
        }
        guard now().timeIntervalSince(began) < Self.startTimeout else {
            return answer(.failed(.notSubmitted(code: .noAgent, detail: "session \(session) had no live inbox \(Int(Self.startTimeout)) s after it was started in \(start.folder)",
                                                reason: Self.notUpInTime)))
        }
        later(Self.startPoll) { look(for: session, in: start, besides: before, since: began, answer: answer) }
    }

    /// The same, from an inbox already read.
    static func turn(of inbox: Inbox) -> SessionTurn? {
        guard let turn = try? String(contentsOf: inbox.folder.appendingPathComponent("turn"), encoding: .utf8) else { return nil }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: inbox.folder.path)) ?? []
        if names.contains(where: { $0.hasSuffix(".line") }) { return .waiting }
        switch turn.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "busy": return Self.interrupted(inbox) ? .idle : .busy
        case "idle": return .idle
        default: return nil
        }
    }

    /// Stop does not run when the person interrupts a turn, so `turn` still says busy; the
    /// transcript's last entry is then Claude Code's interrupt marker. inbox.sh reads it the same way.
    static func interrupted(_ inbox: Inbox) -> Bool {
        guard let path = inbox.transcript, let tail = tail(of: URL(fileURLWithPath: path), bytes: 4096),
              let last = tail.split(separator: UInt8(ascii: "\n")).last else { return false }
        return String(decoding: last, as: UTF8.self).contains("[Request interrupted by user")
    }

    /// The inboxes a request can be written to: the process is running and its monitor is. An
    /// inbox whose process has gone is removed, since the monitor may have been stopped before it
    /// could remove it itself.
    func liveInboxes() -> [Inbox] {
        Self.inboxes(in: inboxes).filter { inbox in
            guard isRunning(inbox.pid) else {
                try? FileManager.default.removeItem(at: inbox.folder)
                return false
            }
            return isLive(inbox)
        }
    }

    /// Whether a request can be written to `inbox`: its process is running, it holds a session, and
    /// its monitor touched it within `aliveWindow`.
    func isLive(_ inbox: Inbox) -> Bool {
        guard isRunning(inbox.pid), inbox.session.map({ UUID(uuidString: $0) != nil }) == true, let alive = inbox.alive else { return false }
        return now().timeIntervalSince(alive) < Self.aliveWindow
    }

    func destinations() -> [AgentDestination] { destinations(of: liveInboxes(), withMenuFields: true) }

    /// The sessions of `inboxes`. `withMenuFields` adds what only the menus show: the place and
    /// branch, the turn, and the inbox mod's goal and open question. Without it, a record that only
    /// needs the name, the folder and when the session was last used reads no `.git` and no store.
    /// One session can run in two processes at once, as when it is resumed in a second terminal; it
    /// is listed once, from the first inbox holding it, and a send writes to that inbox.
    func destinations(of inboxes: [Inbox], withMenuFields: Bool) -> [AgentDestination] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: transcripts, includingPropertiesForKeys: nil)) ?? []
        let mod = withMenuFields ? modStore() : [:]
        var places: [String: SessionPlaces.Found] = [:]
        var listed: Set<String> = []
        return inboxes.compactMap { inbox -> AgentDestination? in
            guard let session = inbox.session, listed.insert(session).inserted else { return nil }
            let file = inbox.transcript.map { URL(fileURLWithPath: $0) }.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                ?? Self.transcriptFile(session: session, folders: folders)
            let transcript = file.flatMap { Self.tail(of: $0) }.map(Self.transcript(tail:)) ?? Transcript()
            var found = SessionPlaces.Found(place: .none, branch: nil)
            if withMenuFields {
                let key = inbox.cwd ?? ""
                found = places[key] ?? SessionPlaces.resolve(folder: inbox.cwd)
                places[key] = found
            }
            return Self.destination(session: session, cwd: inbox.cwd, transcript: transcript, inbox: inbox, mod: mod[session], found: found)
        }
    }

    /// One session as a destination. The transcript names it and says when it was last used. A
    /// session with no title yet, one nobody has written to, is named by its project. The project is
    /// the folder Claude Code runs in: the transcript's `cwd` follows the session's shell, so a
    /// session that ran `cd .scratch` would read as a project called ".scratch" (observed 2026-09-24).
    /// `inbox` adds what it knows: when the session started, a time to order it by when its
    /// transcript has no message yet, and its turn. The place comes from the inbox's folder, never
    /// the transcript's `cwd`.
    static func destination(session: String, cwd: String?, transcript: Transcript, inbox: Inbox? = nil,
                            mod: InboxModStore.Entry? = nil, found: SessionPlaces.Found? = nil,
                            home: String = NSHomeDirectory()) -> AgentDestination {
        let folder = cwd ?? transcript.cwd ?? ""
        let project = (folder as NSString).lastPathComponent
        let found = found ?? SessionPlaces.resolve(folder: cwd, home: home)
        return AgentDestination(
            id: session,
            name: transcript.title ?? (project.isEmpty ? "New session" : "New session in \(project)"),
            detail: project,
            address: .claudeSession(session),
            lastUsed: transcript.lastUsed ?? inbox?.written,
            place: found.place,
            branch: found.branch,
            started: inbox?.started,
            turn: inbox.flatMap { turn(of: $0) },
            inbox: inbox?.pid,
            goal: mod?.goal,
            needsYou: mod?.needsYou ?? false,
            hasOwnName: transcript.title != nil,
            folder: cwd)
    }

    /// Writes the request into the session's inbox. A session that is not running is started first,
    /// through `submit(_:to:completion:)`, which this does not wait for.
    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome {
        guard case .claudeSession(let session) = destination.address else {
            return .notSubmitted(code: .noAgent, detail: "not a Claude Code destination", reason: SubmissionOutcome.internalReason)
        }
        guard destination.start == nil else {
            return .notSubmitted(code: .noAgent, detail: "\(session) is not running; it is started through submit(_:to:completion:)",
                                 reason: SubmissionOutcome.internalReason)
        }
        // The guard: the inbox has to hold this exact session now. A session in no inbox is an
        // error; it is never redirected to another one. The inbox it was listed from comes first,
        // since that is the one `turn(of:)` watches.
        guard let inbox = listedInbox(of: destination) ?? liveInbox(holding: session) else {
            let cleared = Self.inboxes(in: inboxes).contains { $0.past.contains(session) && isRunning($0.pid) }
            return .destinationChanged(detail: "Claude Code session \(session) is in no live inbox under \(inboxes.path)",
                                       reason: cleared ? Self.cleared : Self.closed)
        }
        return write(line, into: inbox, session: session)
    }

    /// A session that was not running is started, and the line goes into the inbox it came up in.
    func submit(_ line: String, to destination: AgentDestination, watchingTurn: Bool,
                completion: @escaping @Sendable (SubmissionOutcome) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let start = destination.start, case .claudeSession(let session) = destination.address else {
                return completion(submit(line, to: destination))
            }
            startSession(start, session: session) { answer in
                switch answer {
                case .up(let inbox): completion(write(line, into: inbox, session: session))
                case .failed(let outcome): completion(outcome)
                }
            }
        }
    }

    /// Writes the request into `inbox`, aside and then renamed in, so the monitor never prints half
    /// of one. It is accepted once it is there: a session in a turn reads it when the turn ends, as a
    /// Codex thread does a queued message.
    private func write(_ line: String, into inbox: Inbox, session: String) -> SubmissionOutcome {
        let name = "\(Int64(now().timeIntervalSince1970 * 1000))-\(UUID().uuidString).line"
        let aside = inbox.folder.appendingPathComponent(".\(name).tmp")
        do {
            try Data((line + "\n").utf8).write(to: aside)
            try FileManager.default.moveItem(at: aside, to: inbox.folder.appendingPathComponent(name))
        } catch {
            try? FileManager.default.removeItem(at: aside)
            return .notSubmitted(code: .sendFailed, detail: "\(inbox.folder.path): \(error.localizedDescription)",
                                 reason: SubmissionOutcome.internalReason)
        }
        return .accepted(detail: "inbox=\(inbox.pid) session=\(session)")
    }

    // MARK: Transcripts

    /// What a session's transcript says about it.
    struct Transcript: Equatable {
        /// The last `ai-title` entry's title. Claude Code rewrites it as the session goes on.
        var aiTitle: String?
        /// The last `custom-title` entry's title, which the person chose.
        var customTitle: String?
        /// The session's own name: the one the person chose, else Claude Code's.
        var title: String? { customTitle ?? aiTitle }
        /// The folder the session's shell was in at its last message. Only the project when herdr
        /// does not say where the pane runs.
        var cwd: String?
        /// The time of the last user or assistant entry. The file's modification time is not it:
        /// Claude Code writes entries with no message in them to transcripts it is not using.
        var lastUsed: Date?
    }

    /// How much of a transcript's end is read. Transcripts run to tens of MB; in the sixty used
    /// last, the last title was never more than 34 KB from the end (measured 2026-09-24).
    static let tailBytes: UInt64 = 256 * 1024

    /// A session's transcript, `<project folder>/<session id>.jsonl`. The folder is named for where
    /// the session started, which the pane may since have left, so every folder is tried. An id
    /// that is not a UUID is never used as a file name.
    static func transcriptFile(session: String, folders: [URL]) -> URL? {
        guard UUID(uuidString: session) != nil else { return nil }
        return folders.lazy.map { $0.appendingPathComponent("\(session).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The last `bytes` of a file, starting at a line.
    static func tail(of file: URL, bytes: UInt64 = tailBytes) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > bytes ? size - bytes : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        guard start > 0 else { return data }
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")) else { return Data() }
        return data[data.index(after: newline)...]
    }

    /// Reads a transcript's tail from its end. Each line is one JSON entry; only the lines that
    /// can hold what is wanted are parsed.
    static func transcript(tail: Data) -> Transcript {
        var found = Transcript()
        let titles: [(mark: Data, key: String, field: WritableKeyPath<Transcript, String?>)] = [
            (Data(#""type":"ai-title""#.utf8), "aiTitle", \.aiTitle),
            (Data(#""type":"custom-title""#.utf8), "customTitle", \.customTitle),
        ]
        let messageMarks = [Data(#""type":"user""#.utf8), Data(#""type":"assistant""#.utf8)]
        let timeMark = Data(#""timestamp":""#.utf8)
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() {
            if found.customTitle != nil && found.aiTitle != nil && found.lastUsed != nil { break }
            var titled = false
            for title in titles where found[keyPath: title.field] == nil && line.range(of: title.mark) != nil {
                guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let text = entry[title.key] as? String, !text.isEmpty else { continue }
                found[keyPath: title.field] = text
                titled = true
                break
            }
            if titled { continue }
            if found.lastUsed == nil, line.range(of: timeMark) != nil,
               messageMarks.contains(where: { line.range(of: $0) != nil }),
               let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               ["user", "assistant"].contains(entry["type"] as? String),
               let time = entry["timestamp"] as? String,
               let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(time) {
                found.lastUsed = date
                found.cwd = entry["cwd"] as? String
            }
        }
        return found
    }
}
