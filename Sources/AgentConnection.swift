import Foundation
import os

/// How Vignette reaches one agent session. The terminal a session happens to be displayed in is
/// not part of this: a destination is a conversation, and a connection is the native call that
/// puts a request into it. See docs/glossary.md for the words.
///
/// Two routes exist. Codex is addressed by its thread UUID alone, and the engine that owns the
/// thread refuses a UUID it does not have. Claude Code is addressed by its session id, which herdr
/// reports for the pane running it; herdr's submission API takes a pane and has no
/// expected-session parameter, so Vignette checks the pane still holds that exact session
/// immediately before it submits. `Address.guardTier` is the difference, and it is
/// recorded on every request rather than assumed away.
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
    /// the submission is small but real, and it belongs to the person's own pane.
    case preflight
}

/// The native identity of a destination, as its client understands it.
enum AgentAddress: Equatable, Codable {
    /// A Claude Code session id. herdr resolves it to the pane running it at send time.
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
    /// cleared. The app's session is the one named `open`, the thread it shows, or else that client's
    /// session used last. When `open` names nothing in a list that is not `fresh`, nothing is
    /// marked: the thread may have started since the list was kept, and the fresh list will say.
    /// `list` is in Send's order.
    static func cameFrom(_ client: AgentClient, open: String?, in list: [AgentDestination], fresh: Bool = true) -> [AgentDestination] {
        var marked = list.map { destination -> AgentDestination in
            var cleared = destination
            cleared.focus = nil
            return cleared
        }
        let ofClient = marked.indices.filter { marked[$0].client == client }
        let shown = open.flatMap { title in ofClient.first { marked[$0].isNamed(title) } }
        guard shown != nil || open == nil || fresh else { return marked }
        if let index = shown ?? ofClient.first { marked[index].focus = .app }
        return marked
    }

    /// Whether this session is known to be in use, which is what Send's menu lists. A Claude Code
    /// session is listed only while it runs in a herdr pane. Nothing says which threads the Codex
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

    /// Whether a title an app shows is this session's name. Only letters and digits are compared:
    /// the Codex app takes a name's markdown and tags out, and `CodexConnection.name(of:)` does the
    /// same closely but not exactly. A title or a name cut short with an ellipsis matches one that
    /// goes on from where it stops.
    func isNamed(_ title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = Self.lettersAndDigits(title), own = Self.lettersAndDigits(name)
        guard !shown.isEmpty, !own.isEmpty else { return false }
        switch (title.hasSuffix("…"), name.hasSuffix("…")) {
        case (false, false): return shown == own
        case (true, false): return own.hasPrefix(shown)
        case (false, true): return shown.hasPrefix(own)
        case (true, true): return shown.hasPrefix(own) || own.hasPrefix(shown)
        }
    }

    private static func lettersAndDigits(_ text: String) -> String {
        String(String.UnicodeScalarView(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
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
enum SubmissionOutcome {
    /// The runtime took the request. It does not mean a model has read the image.
    case accepted(detail: String)
    /// Nothing reached the client. Retrying the same request is safe.
    case notSubmitted(code: CommandError, detail: String)
    /// The conversation is gone, replaced, or no longer reachable where it was.
    case destinationChanged(detail: String)
    /// The call did not answer in time. It may or may not have been accepted, so Vignette neither
    /// retries it nor claims it failed.
    case uncertain(detail: String)

    var isAccepted: Bool { if case .accepted = self { return true }; return false }

    var detail: String {
        switch self {
        case .accepted(let d), .destinationChanged(let d), .uncertain(let d): return d
        case .notSubmitted(_, let d): return d
        }
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
    /// The same, together with any session named `title` that the route can find though it is not
    /// among the ones it lists, such as a Codex thread used weeks ago that the Codex app shows.
    func destinations(named title: String) -> [AgentDestination]
    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome
}

extension AgentConnection {
    var keepsList: Bool { false }
    func destinations(named title: String) -> [AgentDestination] { destinations() }
}

// MARK: Running a command

/// How the connections run the command line tools they talk through.
enum Subprocess {
    /// Runs a command and returns its status, its combined output, and whether the watchdog had to
    /// stop it; nil when it cannot start. It blocks, so callers keep it off the main thread. A
    /// command killed on the deadline may still have been accepted by whatever it was talking to, so
    /// a caller that has to tell a definite failure from an uncertain one reads `timedOut` rather
    /// than the exit status.
    static func run(_ binary: String, _ arguments: [String], timeout: TimeInterval)
        -> (status: Int32, output: String, timedOut: Bool)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
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

// MARK: Claude Code, through herdr

/// Claude Code has no local command that puts a message into a session that is already running.
/// herdr, which owns the pane, does: `herdr agent prompt` submits one line to an agent it is
/// running, refusing one that is waiting on a prompt of its own. herdr also reports each pane's
/// Claude Code session id, so Vignette addresses the session and resolves it to a pane at send
/// time; a session that is in no pane is an error and never a different pane's. What the menu says
/// about a session comes from its own transcript.
struct ClaudeCodeConnection: AgentConnection {
    let client = AgentClient.claude
    /// Where herdr may be, and how long one call may take. Injected so tests never run herdr.
    var binary: () -> String? = { ClaudeCodeConnection.binary() }
    var run: @Sendable (String, [String], TimeInterval) -> (status: Int32, output: String, timedOut: Bool)? = {
        Subprocess.run($0, $1, timeout: $2)
    }
    /// Where Claude Code keeps its transcripts, one folder per project. Injected so a test never
    /// reads the real ones.
    var transcripts = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")

    static let listTimeout: TimeInterval = 10
    static let promptTimeout: TimeInterval = 20

    /// One agent herdr is running, as `herdr agent list` reports it.
    struct HerdrAgent: Equatable {
        /// The name herdr answers to: the agent's name, or its pane id when it has none.
        let id: String
        let pane: String
        /// claude, codex, cursor, … whichever herdr recognized.
        let kind: String
        let cwd: String
        /// idle, working, blocked, or unknown.
        let status: String
        /// The agent session herdr says this pane is running, when it knows one: for Claude Code
        /// that is the conversation's own id. A pane hosts different sessions over time, so this,
        /// and not the pane, is what a screenshot request is addressed to.
        var session: String? = nil
        /// What the pane's title says it is doing. Only a label; two panes may share it.
        var title: String = ""
        /// The tab the pane is in, and whether it is herdr's focused pane.
        var tab: String = ""
        var focused = false
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

    /// Where herdr may be. The app is launched by LaunchServices, so it inherits no shell PATH.
    static let binaryPaths = ["\(NSHomeDirectory())/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]

    static func binary(exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        binaryPaths.first(where: exists)
    }

    /// The agents in a `herdr agent list` answer, or in a `herdr pane list` answer with `list`
    /// "panes": the same fields, and a pane running no agent is left out. An unparseable answer is
    /// no agents.
    static func agents(in data: Data, list: String = "agents") -> [HerdrAgent] {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let agents = ((root?["result"] as? [String: Any])?[list] as? [[String: Any]]) ?? []
        return agents.compactMap { agent in
            guard let pane = agent["pane_id"] as? String, let kind = agent["agent"] as? String else { return nil }
            let name = (agent["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let session = (agent["agent_session"] as? [String: Any])?["value"] as? String
            return HerdrAgent(id: name ?? pane, pane: pane, kind: kind, cwd: agent["cwd"] as? String ?? "",
                              status: agent["agent_status"] as? String ?? "unknown",
                              session: (session?.isEmpty ?? true) ? nil : session,
                              title: agent["terminal_title_stripped"] as? String ?? "",
                              tab: agent["tab_id"] as? String ?? "",
                              focused: agent["focused"] as? Bool ?? false)
        }
    }

    func destinations() -> [AgentDestination] {
        guard let herdr = binary(), let list = run(herdr, ["pane", "list"], Self.listTimeout), list.status == 0 else { return [] }
        let data = Data(list.output.utf8)
        // A session herdr cannot identify is left out: a pane id is not a conversation, and
        // addressing one would be the thing this route must not do.
        let all = Self.agents(in: data, list: "panes")
        let agents = all.filter { $0.kind == "claude" && $0.session != nil }
        let folders = (try? FileManager.default.contentsOfDirectory(at: transcripts, includingPropertiesForKeys: nil)) ?? []
        return Self.markFocus(agents.compactMap { agent in
            let transcript = agent.session
                .flatMap { Self.transcriptFile(session: $0, folders: folders) }
                .flatMap { Self.tail(of: $0) }
                .map(Self.transcript(tail:))
            return Self.destination(agent, transcript: transcript ?? Transcript())
        }, agents: all, focus: Self.focus(fromPaneList: data))
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

    /// One Claude Code pane as a destination, or nil for a pane whose session herdr cannot name.
    /// The transcript names it and says when it was last used; the pane's title, which is the same
    /// title cut short, stands in when the transcript has none. Its project is the folder the pane
    /// runs Claude Code in. The transcript's `cwd` follows the session's shell, so a session that
    /// ran `cd .scratch` would read as a project called ".scratch" (observed 2026-09-24).
    static func destination(_ target: HerdrAgent, transcript: Transcript = Transcript()) -> AgentDestination? {
        guard let session = target.session else { return nil }
        return AgentDestination(
            id: session,
            name: transcript.title ?? (target.title.isEmpty ? target.id : target.title),
            detail: ((target.cwd.isEmpty ? transcript.cwd ?? "" : target.cwd) as NSString).lastPathComponent,
            address: .claudeSession(session),
            lastUsed: transcript.lastUsed)
    }

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

    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome {
        guard case .claudeSession(let session) = destination.address else {
            return .notSubmitted(code: .noAgent, detail: "not a Claude Code destination")
        }
        guard let herdr = binary() else {
            return .notSubmitted(code: .noAgent, detail: "no herdr at \(Self.binaryPaths.joined(separator: " "))")
        }
        guard let list = run(herdr, ["agent", "list"], Self.listTimeout) else {
            return .notSubmitted(code: .noAgent, detail: "herdr agent list did not run")
        }
        guard list.status == 0 else {
            return .notSubmitted(code: .noAgent, detail: "herdr agent list: \(Subprocess.detail(list.output) ?? "no output")")
        }
        // The guard: the pane has to be running this exact session now, not a session it ran
        // before. A session in no pane is an error; it is never redirected to another one.
        let agents = Self.agents(in: Data(list.output.utf8))
        guard let target = agents.first(where: { $0.session == session }) else {
            return .destinationChanged(detail: "Claude Code session \(session) is in no herdr pane now")
        }
        guard target.status != "blocked" else {
            return .notSubmitted(code: .sendFailed, detail: "\(target.id) is waiting on a prompt of its own; answer it first")
        }
        guard let sent = run(herdr, ["agent", "prompt", target.pane, line], Self.promptTimeout) else {
            return .notSubmitted(code: .sendFailed, detail: "herdr agent prompt did not run")
        }
        if sent.timedOut {
            return .uncertain(detail: "herdr agent prompt did not answer in \(Int(Self.promptTimeout)) s")
        }
        guard sent.status == 0 else {
            let detail = Subprocess.detail(sent.output) ?? "herdr said nothing"
            // herdr checks the pane again on its own side. Only `agent_not_found` says the session
            // is gone; `agent_blocked` says it is there, waiting on a prompt of its own, which is
            // the same non-submission the preflight above reports and is worth retrying.
            if detail.contains("agent_not_found") {
                return .destinationChanged(detail: detail)
            }
            if detail.contains("agent_blocked") {
                return .notSubmitted(code: .sendFailed, detail: "\(detail); answer the agent's own prompt first")
            }
            return .notSubmitted(code: .sendFailed, detail: detail)
        }
        return .accepted(detail: "pane=\(target.pane) session=\(session)")
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
    var binary: () -> String? = { CodexConnection.binary() }
    var run: @Sendable (String, [String], TimeInterval) -> (status: Int32, output: String, timedOut: Bool)? = {
        Subprocess.run($0, $1, timeout: $2)
    }
    /// One stdio conversation with an app-server. Injected so a test never spawns codex.
    var converse: @Sendable (String, [String], [String]) -> [String] = {
        AppServer.converse($0, $1, $2)
    }

    static let queueTimeout: TimeInterval = 25

    /// Where the Codex CLI may be. The app is launched by LaunchServices, so it inherits no shell
    /// PATH. A `no codex at …` error names every path tried, so an install somewhere else is one
    /// symlink away rather than another setting.
    static let binaryPaths = [
        "\(NSHomeDirectory())/.codex/bin/codex", "\(NSHomeDirectory())/.local/bin/codex",
        "\(NSHomeDirectory())/.vite-plus/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
    ]

    static func binary(exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        binaryPaths.first(where: exists)
    }

    /// Every Codex session the machine knows about. `thread/list` reads the store all of them
    /// share, so an app-server started for the length of this one call answers for every session,
    /// including the ones the ChatGPT desktop app owns. No codex on the machine means no Codex
    /// destinations, which is not an error.
    func destinations() -> [AgentDestination] { discover(title: nil) }

    /// The threads used last, and the thread the Codex app shows under `title`, found by searching
    /// the store whatever its age (`AppServer.searchTerms`).
    func destinations(named title: String) -> [AgentDestination] { discover(title: title) }

    private func discover(title: String?) -> [AgentDestination] {
        guard let codex = binary() else { return [] }
        let lines = converse(codex, ["app-server"], AppServer.discoveryRequests(title: title))
        let listed = AppServer.threads(in: lines).map(Self.destination)
        guard let title else { return listed }
        let shown = AppServer.searched(in: lines).map(Self.destination)
            .filter { found in found.isNamed(title) && !listed.contains { $0.id == found.id } }
        return listed + shown
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
    /// app's rule, read from its bundle on 2026-09-25. Cutting it where the app does keeps what tells
    /// two threads apart: at 60 characters, two threads with one long start matched the same title.
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

    /// Markdown as the plain text the Codex app shows for it, close enough for `isNamed`: a link or
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
            return .notSubmitted(code: .noAgent, detail: "not a Codex destination")
        }
        guard let codex = binary() else {
            return .notSubmitted(code: .noAgent, detail: "no codex at \(Self.binaryPaths.joined(separator: " "))")
        }
        guard let result = run(codex, Self.arguments(thread: uuid, message: line), Self.queueTimeout) else {
            return .notSubmitted(code: .sendFailed, detail: "codex queue did not run")
        }
        if result.timedOut {
            return .uncertain(detail: "codex queue did not answer in \(Int(Self.queueTimeout)) s")
        }
        guard result.status == 0 else {
            return Self.failure(output: result.output, thread: uuid)
        }
        return .accepted(detail: "thread=\(uuid)")
    }

    /// What a nonzero `codex queue` means. A thread the server does not have, or a server that is
    /// not there, is the destination having changed; anything else is a definite non-submission.
    static func failure(output: String, thread: String) -> SubmissionOutcome {
        let detail = Subprocess.detail(output) ?? "codex said nothing"
        let lower = detail.lowercased()
        let gone = ["thread not found", "no such thread", "session not found", "unknown thread",
                    "connection refused", "failed to connect", "connection reset"]
        if gone.contains(where: lower.contains) {
            return .destinationChanged(detail: detail)
        }
        return .notSubmitted(code: .sendFailed, detail: detail)
    }
}
