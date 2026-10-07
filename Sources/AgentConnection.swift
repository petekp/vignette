import Foundation
import os

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

    var client: AgentClient {
        switch self {
        case .claudeSession: return .claude
        case .codexThread: return .codex
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
    /// herdr's focus is on its pane or beside it. Nil for every other session.
    var focus: Focus? = nil

    enum Focus: String, Equatable {
        /// Its agent's own app was the app in front, showing this session (`cameFrom`).
        case app
        /// herdr's focused pane runs this session.
        case pane
        /// herdr's focused pane runs no agent, and this is the one session in that pane's tab.
        case tab
    }

    var client: AgentClient { address.client }
    /// What the toolbar's target and the sent card call it: its project, or the client's name.
    var project: String { detail.isEmpty ? client.label : detail }

    /// Where Send goes when nobody has chosen: the session you came from, which is where a paste
    /// would have gone. The session an agent's app showed first, then herdr's focused pane, then the
    /// one session beside it, then the session used last. `list` is in Send's order, the session used
    /// last first.
    static func defaultTarget(in list: [AgentDestination]) -> AgentDestination? {
        list.first { $0.focus == .app } ?? list.first { $0.focus == .pane } ?? list.first { $0.focus == .tab }
            ?? list.first
    }

    /// The sessions as they stand when you came from `client`'s own app, such as the Codex app.
    /// herdr keeps a focused pane while its terminal is behind, so its focus says nothing then and is
    /// cleared. The app's session is `shown`, the id of the thread it shows, or else that client's
    /// session used last. When a list that is not `fresh` lacks `shown`, nothing is marked: the
    /// thread may have started since the list was kept, and the fresh list will say. `list` is in
    /// Send's order.
    static func cameFrom(_ client: AgentClient, shown: String?, in list: [AgentDestination], fresh: Bool = true) -> [AgentDestination] {
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

/// What happened when a request was handed to a client. The four cases are different on purpose:
/// only `notSubmitted` permits an automatic retry, and only `uncertain` may already have arrived.
/// `detail` is for the log. `reason` is for the person, on the card that was sent: what went wrong
/// and what to do about it, short enough for a card.
enum SubmissionOutcome {
    /// The runtime took the request. It does not mean a model has read the image.
    case accepted(detail: String)
    /// The runtime took the request and holds it, but nothing has the conversation open, so nothing
    /// reads it until someone opens it. It arrives then, first.
    case queued(detail: String, reason: String)
    /// Nothing reached the client. Retrying the same request is safe.
    case notSubmitted(code: CommandError, detail: String, reason: String)
    /// The conversation is gone, replaced, or no longer reachable where it was.
    case destinationChanged(detail: String, reason: String)
    /// The call did not answer in time. It may or may not have been accepted, so Vignette neither
    /// retries it nor claims it failed.
    case uncertain(detail: String, reason: String)

    var isAccepted: Bool {
        switch self {
        case .accepted, .queued: return true
        case .notSubmitted, .destinationChanged, .uncertain: return false
        }
    }

    var detail: String {
        switch self {
        case .accepted(let d), .queued(let d, _), .destinationChanged(let d, _), .uncertain(let d, _): return d
        case .notSubmitted(_, let d, _): return d
        }
    }

    var reason: String? {
        switch self {
        case .accepted: return nil
        case .queued(_, let r), .notSubmitted(_, _, let r), .destinationChanged(_, let r), .uncertain(_, let r): return r
        }
    }

    static let internalReason = "Something went wrong in Vignette. The log has details."

    /// A client's own words, cut to fit a card, for a failure Vignette has no sentence of its own for.
    static func quoted(_ client: String, _ detail: String) -> String {
        let words = detail.count > 70 ? String(detail.prefix(69)) + "…" : detail
        return "\(client): \(words)"
    }
}

/// The whole boundary a client implementation has to fill. Everything else — the fixed image, the
/// request record, reply validation, receipts, import, and the cards — is Vignette's and is shared.
/// Both calls block on a subprocess, so they never run on the main thread.
protocol AgentConnection: Sendable {
    var client: AgentClient { get }
    /// Whether this route's last list may stand in while a fresh one is asked for. A list that says
    /// where herdr's focus is may not: the focus moves whenever you change panes.
    var keepsList: Bool { get }
    /// The sessions this route can address right now. Empty when the route cannot enumerate.
    func destinations() -> [AgentDestination]
    /// The same, together with the session `id` when the route can find it though it is not among
    /// the ones it lists, such as a Codex thread used weeks ago that the Codex app shows.
    func destinations(including id: String) -> [AgentDestination]
    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome
    /// Whether the session is in the middle of a turn, or nil when the route cannot tell.
    func isWorking(_ destination: AgentDestination) -> Bool?
}

extension AgentConnection {
    var keepsList: Bool { false }
    func destinations(including id: String) -> [AgentDestination] { destinations() }
    func isWorking(_ destination: AgentDestination) -> Bool? { nil }
}

// MARK: Running a command

/// How the connections run the command line tools they talk through.
enum Subprocess {
    /// The app's environment with `adding` over it and a `PATH` that finds what `binary` needs.
    static func environment(for binary: String, adding: [String: String] = [:]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment.merging(adding) { $1 }
        environment["PATH"] = AgentTools.searchPath(for: binary)
        return environment
    }

    /// Runs a command and returns its status, its combined output, and whether the watchdog had to
    /// stop it; nil when it cannot start. It blocks, so callers keep it off the main thread. A
    /// command killed on the deadline may still have been accepted by whatever it was talking to, so
    /// a caller that has to tell a definite failure from an uncertain one reads `timedOut` rather
    /// than the exit status. `environment` is added to the app's own, with `PATH` from
    /// `AgentTools.searchPath`.
    static func run(_ binary: String, _ arguments: [String], timeout: TimeInterval, environment: [String: String] = [:])
        -> (status: Int32, output: String, timedOut: Bool)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.environment = Self.environment(for: binary, adding: environment)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return nil }
        let killed = OSAllocatedUnfairLock(initialState: false)
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            killed.withLock { $0 = true }
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "", killed.withLock { $0 })
    }

    /// A command's own words as one short log detail; nil when it said nothing. Errors often come
    /// as JSON on stderr, which the log line carries as it is.
    static func detail(_ output: String?) -> String? {
        let text = (output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(200))
    }
}

// MARK: Claude Code, through the plugin's inbox

/// Claude Code has no command that puts a message into a session that is already running. The
/// Vignette plugin gives each session an inbox instead: a folder named by the Claude Code process,
/// which the plugin's monitor reads between turns, printing each request, which reaches Claude as
/// the person's message (agent-plugin/, docs/claude-code-without-herdr-2026-09-27.md). Vignette
/// addresses the session, and checks just before writing that the inbox still holds it: `/clear`
/// and `/resume` give the same process another session. What the menu says about a session comes
/// from its own transcript. herdr, when it is there, only says which session has the focus.
struct ClaudeCodeConnection: AgentConnection {
    let client = AgentClient.claude
    /// The inboxes, one folder per Claude Code process. Injected so a test never reads the real ones.
    var inboxes = AgentPlugin.inboxRoot
    /// Where Claude Code keeps its transcripts, one folder per project, for a session whose inbox
    /// does not name its transcript yet.
    var transcripts = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    var isRunning: @Sendable (Int32) -> Bool = { kill($0, 0) == 0 }
    var now: @Sendable () -> Date = { Date() }
    /// herdr's binary and its runner, for the focus hint. Injected so tests never run herdr.
    var herdr: @Sendable () -> String? = { AgentTools.forSessions("VIGNETTE_HERDR") { ClaudeCodeConnection.herdrBinary() } }
    var run: @Sendable (String, [String], TimeInterval) -> (status: Int32, output: String, timedOut: Bool)? = {
        Subprocess.run($0, $1, timeout: $2)
    }

    static let listTimeout: TimeInterval = 10
    /// The monitor touches `alive` every 3 s. An inbox older than this has no monitor reading it.
    static let aliveWindow: TimeInterval = 10

    static let closed = "This session has ended. You can send it to another one."
    static let cleared = "This session was cleared. You can send it to another one."

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
    }

    /// Every inbox under `root`. Nothing is read beyond the few short files in each.
    static func inboxes(in root: URL) -> [Inbox] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            guard let pid = Int32(folder.lastPathComponent), pid > 0 else { return nil }
            func text(_ name: String) -> String {
                (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? ""
            }
            func line(_ name: String) -> String? {
                let line = text(name).trimmingCharacters(in: .whitespacesAndNewlines)
                return line.isEmpty ? nil : line
            }
            let alive = (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("alive").path))?[.modificationDate] as? Date
            return Inbox(folder: folder, pid: pid, session: line("session"), cwd: line("cwd"), transcript: line("transcript"),
                         past: text("past").split(whereSeparator: \.isNewline).map(String.init), alive: alive)
        }
    }

    /// The inboxes a request can be written to: the process is running and its monitor is. An
    /// inbox whose process has gone is removed, since the monitor may have been stopped before it
    /// could remove it itself.
    /// From the `turn` file the plugin's hooks write in the session's inbox: `busy` from a prompt
    /// to the end of the turn, `idle` after it.
    func isWorking(_ destination: AgentDestination) -> Bool? {
        guard case .claudeSession(let session) = destination.address,
              let inbox = liveInboxes().first(where: { $0.session == session }),
              let turn = try? String(contentsOf: inbox.folder.appendingPathComponent("turn"), encoding: .utf8) else { return nil }
        switch turn.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "busy": return true
        case "idle": return false
        default: return nil
        }
    }

    func liveInboxes() -> [Inbox] {
        Self.inboxes(in: inboxes).filter { inbox in
            guard isRunning(inbox.pid) else {
                try? FileManager.default.removeItem(at: inbox.folder)
                return false
            }
            guard inbox.session.map({ UUID(uuidString: $0) != nil }) == true, let alive = inbox.alive else { return false }
            return now().timeIntervalSince(alive) < Self.aliveWindow
        }
    }

    func destinations() -> [AgentDestination] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: transcripts, includingPropertiesForKeys: nil)) ?? []
        let listed = liveInboxes().compactMap { inbox -> AgentDestination? in
            guard let session = inbox.session else { return nil }
            let file = inbox.transcript.map { URL(fileURLWithPath: $0) }.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                ?? Self.transcriptFile(session: session, folders: folders)
            let transcript = file.flatMap { Self.tail(of: $0) }.map(Self.transcript(tail:)) ?? Transcript()
            return Self.destination(session: session, cwd: inbox.cwd, transcript: transcript)
        }
        guard !listed.isEmpty, let herdr = herdr(), let panes = run(herdr, ["pane", "list"], Self.listTimeout), panes.status == 0 else {
            return listed
        }
        let data = Data(panes.output.utf8)
        return Self.markFocus(listed, agents: Self.agents(in: data), focus: Self.focus(fromPaneList: data))
    }

    /// One session as a destination. The transcript names it and says when it was last used. A
    /// session with no title yet, one nobody has written to, is named by its project. The project is
    /// the folder Claude Code runs in: the transcript's `cwd` follows the session's shell, so a
    /// session that ran `cd .scratch` would read as a project called ".scratch" (observed 2026-09-24).
    static func destination(session: String, cwd: String?, transcript: Transcript) -> AgentDestination {
        let project = ((cwd ?? transcript.cwd ?? "") as NSString).lastPathComponent
        return AgentDestination(
            id: session,
            name: transcript.title ?? (project.isEmpty ? "New session" : "New session in \(project)"),
            detail: project,
            address: .claudeSession(session),
            lastUsed: transcript.lastUsed)
    }

    /// Writes the request into the session's inbox, aside and then renamed in, so the monitor never
    /// prints half of one. It is accepted once it is there: a session in a turn reads it when the
    /// turn ends, as a Codex thread does a queued message.
    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome {
        guard case .claudeSession(let session) = destination.address else {
            return .notSubmitted(code: .noAgent, detail: "not a Claude Code destination", reason: SubmissionOutcome.internalReason)
        }
        // The guard: the inbox has to hold this exact session now. A session in no inbox is an
        // error; it is never redirected to another one.
        let all = Self.inboxes(in: inboxes)
        guard let inbox = liveInboxes().first(where: { $0.session == session }) else {
            let cleared = all.contains { $0.past.contains(session) && isRunning($0.pid) }
            return .destinationChanged(detail: "Claude Code session \(session) is in no live inbox under \(inboxes.path)",
                                       reason: cleared ? Self.cleared : Self.closed)
        }
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

    // MARK: herdr's focus

    /// One agent herdr is running, of any kind, as `herdr pane list` reports it.
    struct HerdrAgent: Equatable {
        let pane: String
        /// The agent session herdr says this pane is running, when it knows one.
        var session: String? = nil
        /// The tab the pane is in.
        var tab: String = ""
    }

    /// Where herdr may be. The app is launched by LaunchServices, so it inherits no shell PATH.
    private static let herdrPaths = ["\(NSHomeDirectory())/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]

    static func herdrBinary() -> String? {
        herdrPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// herdr's focused pane and its tab, from a `herdr pane list` answer, which lists every pane,
    /// agent or not. Nil when no pane is focused or the answer does not parse.
    static func focus(fromPaneList data: Data) -> (pane: String, tab: String)? {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let panes = ((root?["result"] as? [String: Any])?["panes"] as? [[String: Any]]) ?? []
        guard let pane = panes.first(where: { $0["focused"] as? Bool == true }),
              let id = pane["pane_id"] as? String else { return nil }
        return (id, pane["tab_id"] as? String ?? "")
    }

    /// The agents in a `herdr pane list` answer. A pane running no agent is left out, and an
    /// unparseable answer is no agents.
    static func agents(in data: Data) -> [HerdrAgent] {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let panes = ((root?["result"] as? [String: Any])?["panes"] as? [[String: Any]]) ?? []
        return panes.compactMap { pane in
            guard let id = pane["pane_id"] as? String, pane["agent"] is String else { return nil }
            let session = (pane["agent_session"] as? [String: Any])?["value"] as? String
            return HerdrAgent(pane: id, session: (session?.isEmpty ?? true) ? nil : session,
                              tab: pane["tab_id"] as? String ?? "")
        }
    }

    /// Marks where herdr's focus is. `agents` is every agent herdr runs, of any kind. A focused pane
    /// running an agent is that agent's, whether or not it is a destination. One running none, such
    /// as a browser or a shell beside the session you are working with (observed 2026-09-24), passes
    /// the focus to the one agent in its tab; a tab with two says nothing about which one.
    static func markFocus(_ destinations: [AgentDestination], agents: [HerdrAgent],
                          focus: (pane: String, tab: String)?) -> [AgentDestination] {
        guard let focus else { return destinations }
        let focusedAgent = agents.first { $0.pane == focus.pane }
        let inTab = agents.filter { !focus.tab.isEmpty && $0.tab == focus.tab }
        return destinations.map { destination in
            var marked = destination
            if let focusedAgent {
                if focusedAgent.session == destination.id { marked.focus = .pane }
            } else if inTab.count == 1, inTab[0].session == destination.id {
                marked.focus = .tab
            }
            return marked
        }
    }

    // MARK: Transcripts

    /// What a session's transcript says about it.
    struct Transcript: Equatable {
        /// The last `ai-title` entry's title. Claude Code rewrites it as the session goes on.
        var title: String?
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
        let titleMark = Data(#""type":"ai-title""#.utf8)
        let messageMarks = [Data(#""type":"user""#.utf8), Data(#""type":"assistant""#.utf8)]
        let timeMark = Data(#""timestamp":""#.utf8)
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() {
            if found.title != nil && found.lastUsed != nil { break }
            if found.title == nil, line.range(of: titleMark) != nil,
               let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               let title = entry["aiTitle"] as? String, !title.isEmpty {
                found.title = title
                continue
            }
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

// MARK: Codex, through its own queue command

/// `codex queue --thread <UUID> --message <line>` hands a message to a persistent Codex thread:
/// the command finds the engine that owns it, an idle session starts a turn, and a busy one runs
/// it next. That engine resolves the UUID, so a thread no engine has is an error rather than
/// another thread. Vignette never starts, resumes, or stops a Codex session.
struct CodexConnection: AgentConnection {
    let client = AgentClient.codex
    /// The threads change only when one is used, and a discovery starts a process of its own.
    let keepsList = true
    var binary: () -> String? = { AgentTools.forSessions("VIGNETTE_CODEX") { CodexConnection.binary() } }
    var run: @Sendable (String, [String], TimeInterval) -> (status: Int32, output: String, timedOut: Bool)? = {
        Subprocess.run($0, $1, timeout: $2)
    }
    /// One stdio conversation with an app-server. Injected so a test never spawns codex.
    var converse: @Sendable (String, [String], [String]) -> [String] = {
        AppServer.converse($0, $1, $2)
    }
    /// Whether an engine has the thread loaded. Injected so a test never reads the person's Codex folder.
    var isLoaded: @Sendable (String) -> Bool = { CodexConnection.isLoaded($0) }

    static let queueTimeout: TimeInterval = 25

    /// The CLI the Codex app carries, then where the Codex CLI's installers put it. `AgentTools`
    /// looks past these. A `no codex at …` error names every folder tried.
    static var binaryPaths: [String] {
        [AgentApp.codexCLI].compactMap { $0 } + [
            "\(NSHomeDirectory())/.codex/bin/codex", "\(NSHomeDirectory())/.local/bin/codex",
            "\(NSHomeDirectory())/.vite-plus/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
        ]
    }

    static func binary(exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        AgentTools.path("codex", fixed: binaryPaths, exists: exists)
    }

    /// Every Codex session the machine knows about. `thread/list` reads the store all of them
    /// share, so an app-server started for the length of this one call answers for every session,
    /// including the ones the ChatGPT desktop app owns. No codex on the machine means no Codex
    /// destinations, which is not an error.
    func destinations() -> [AgentDestination] { discover(shown: nil) }

    /// The threads used last, and the thread `id`, such as the one the Codex app shows, whatever its
    /// age.
    func destinations(including id: String) -> [AgentDestination] { discover(shown: id) }

    private func discover(shown: String?) -> [AgentDestination] {
        guard let codex = binary() else { return [] }
        let lines = converse(codex, ["app-server"], AppServer.discoveryRequests(shown: shown))
        let listed = AppServer.threads(in: lines).map(Self.destination)
        guard let shown, let thread = AppServer.read(in: lines), thread.id == shown,
              !listed.contains(where: { $0.id == shown }) else { return listed }
        return listed + [Self.destination(thread)]
    }

    private static func destination(_ thread: AppServer.Thread) -> AgentDestination {
        AgentDestination(
            id: thread.id,
            name: name(of: thread),
            detail: (thread.cwd as NSString).lastPathComponent,
            address: .codexThread(uuid: thread.id),
            lastUsed: thread.recencyAt)
    }

    /// A thread's name as the Codex app shows it: its own name, or for a thread with none, its first
    /// message, as plain text with its lines joined, cut to 79 characters and an ellipsis when it is
    /// longer than 80. A message an IDE sent is named by the request after its context. That is the
    /// app's rule, read from its bundle on 2026-09-25, so Send names a thread as the app does.
    static func name(of thread: AppServer.Thread) -> String {
        let text = [thread.name ?? "", request(in: thread.preview ?? "")].lazy.map(plainText).first { !$0.isEmpty }
        guard let text else { return "Codex \(thread.id.prefix(8))" }
        return text.count > 80 ? text.prefix(79).trimmingCharacters(in: .whitespaces) + "…" : text
    }

    /// What follows the last "## My request for Codex:" in a first message, which is where an IDE
    /// puts the request after the context it sends; the whole message when there is none.
    static func request(in message: String) -> String {
        guard let marker = message.range(of: #"## My request(?: for Codex)?:"#, options: [.regularExpression, .backwards]) else {
            return message
        }
        return message[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Markdown as the plain text the Codex app shows for it, closely but not exactly: a link or
    /// an image keeps its text and an autolink its address; HTML tags, a divider line, and the marks
    /// that start a heading, a quote, a list item or a code fence go; each run of whitespace is one
    /// space. A tag's name is letters, digits and hyphens, so `<environment_context>` is text and
    /// stays.
    static func plainText(_ markdown: String) -> String {
        let rules = [
            (#"<(https?://[^>\s]+)>"#, "$1"),
            (#"</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>\n]*)?/?>"#, ""),
            (#"!?\[([^\]\n]*)\]\([^)\n]*\)"#, "$1"),
            (#"(?m)^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$"#, ""),
            (#"(?m)^[ \t]*(?:#{1,6}(?=[ \t]|$)|>|[-*+](?=[ \t])|\d+[.)](?=[ \t])|```\S*)[ \t]*"#, ""),
            (#"\*\*|__|`"#, ""),
            (#"\s+"#, " "),
        ]
        return rules.reduce(markdown) { text, rule in
            text.replacingOccurrences(of: rule.0, with: rule.1, options: .regularExpression)
        }.trimmingCharacters(in: .whitespaces)
    }

    /// The argv for one queue call. Built as a list, never a shell line: an image path with spaces
    /// and a message with quotes are both one element.
    static func arguments(thread: String, message: String) -> [String] {
        ["queue", "--thread", thread, "--message", message]
    }

    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome {
        guard case .codexThread(let uuid) = destination.address else {
            return .notSubmitted(code: .noAgent, detail: "not a Codex destination", reason: SubmissionOutcome.internalReason)
        }
        guard let codex = binary() else {
            return .notSubmitted(code: .noAgent, detail: "no codex at \(AgentTools.searched("codex", fixed: Self.binaryPaths).joined(separator: " ")) or on the login shell's PATH",
                                 reason: "Sending to Codex needs the Codex app or its CLI.")
        }
        guard let result = run(codex, Self.arguments(thread: uuid, message: line), Self.queueTimeout) else {
            return .notSubmitted(code: .sendFailed, detail: "codex queue did not run", reason: "Codex couldn't start. The log has details.")
        }
        if result.timedOut {
            return .uncertain(detail: "codex queue did not answer in \(Int(Self.queueTimeout)) s",
                              reason: "Codex didn't confirm it. It may still have arrived.")
        }
        guard result.status == 0 else {
            return Self.failure(output: result.output, thread: uuid)
        }
        guard isLoaded(uuid) else {
            return .queued(detail: "thread=\(uuid) not loaded", reason: "Codex reads it when you open this thread.")
        }
        return .accepted(detail: "thread=\(uuid)")
    }

    /// Whether an engine, the Codex app's or a CLI session's, has the thread loaded. `codex queue`
    /// answers the same either way: it stores the message, an engine with the thread loaded takes it
    /// within about 10 s, and a thread no engine has loaded keeps it until someone opens the thread.
    /// An engine holds `thread-writer-locks/<id>.lock` in the Codex folder while it has the thread
    /// and removes it when it lets go (`codex-rs/rollout/src/writer_lock.rs`, 0.159.2). A crash can
    /// leave the file behind, which reads as loaded, as every send did before this check.
    static func isLoaded(_ thread: String,
                         codexHome: URL = AgentPlugin.root(of: .codex, home: URL(fileURLWithPath: NSHomeDirectory()))) -> Bool {
        guard UUID(uuidString: thread) != nil else { return true }
        return FileManager.default.fileExists(atPath: codexHome.appendingPathComponent("thread-writer-locks/\(thread).lock").path)
    }

    /// What a nonzero `codex queue` means. A thread the server does not have, or a server that is
    /// not there, is the destination having changed; anything else is a definite non-submission.
    static func failure(output: String, thread: String) -> SubmissionOutcome {
        let detail = Subprocess.detail(output) ?? "codex said nothing"
        let lower = detail.lowercased()
        let missing = ["no rollout found", "thread not found", "no such thread", "session not found", "unknown thread"]
        let unreachable = ["connection refused", "failed to connect", "connection reset"]
        if missing.contains(where: lower.contains) {
            return .destinationChanged(detail: detail, reason: "Codex can't find this thread. You can send it to another one.")
        }
        if unreachable.contains(where: lower.contains) {
            return .destinationChanged(detail: detail, reason: "Codex isn't running. You can send again once it's open.")
        }
        return .notSubmitted(code: .sendFailed, detail: detail, reason: SubmissionOutcome.quoted("Codex", detail))
    }
}
