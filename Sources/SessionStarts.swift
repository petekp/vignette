import Foundation

/// How Vignette starts a Claude Code session that is not running, for a send a person aimed at it.
/// A destination with a `start` is not running: sending to it starts `claude` in a new herdr tab in
/// its folder, waits until the plugin's inbox holds the session, and then writes the line as a send
/// to a running session does (`ClaudeCodeConnection.submit(_:to:watchingTurn:completion:)`).
enum SessionStart: Equatable, Codable, Sendable {
    /// `claude --resume <id>` in `folder`: the project's last session, under its own id. Claude Code
    /// keeps the id when it resumes; only `--fork-session` makes a new one.
    case resume(folder: String)
    /// `claude --session-id <id>` in `folder`: a new session, under an id Vignette chose when Send
    /// was pressed (`ScreenshotRequests.send`), so the inbox can be checked for that exact session.
    case new(folder: String)

    var folder: String {
        switch self {
        case .resume(let folder), .new(let folder): return folder
        }
    }

    /// The project's name: the folder's own, as a session's row names its project. It labels the
    /// herdr tab.
    var label: String { (folder as NSString).lastPathComponent }

    /// The arguments to `claude` that start session `id`.
    func arguments(session id: String) -> [String] {
        switch self {
        case .resume: return ["--resume", id]
        case .new: return ["--session-id", id]
        }
    }

    /// The row id of a project's New session row. The session's own id is chosen at Send.
    static func newRowID(folder: String) -> String { "new:\(folder)" }
}

extension AgentDestination {
    /// Whether sending here starts a process. Only a person's pick may do that, so these rows travel
    /// apart from the running sessions (`DestinationChoice.Candidates.startable`).
    var startsProcess: Bool { start != nil }
}

// MARK: Which projects

/// The Claude Code projects a person used lately, each as its two rows: Continue last session and New
/// session. Read off the main thread, in a listing job of its own (`SessionListing`), since it reads a
/// transcript per project. A project that has a running session is left out when the listing joins
/// this list to the running sessions (`SessionListing.startable(_:beside:)`).
///
/// Claude Code's prompt history (`~/.claude/history.jsonl`) is the index: one line per prompt the
/// person typed, with the folder Claude Code ran in and the session. It holds interactive sessions
/// only, and its last 2 MB went back 45 days on Pete's Mac (2026-10-25). The transcripts have 11,606
/// project folders there, most of them from scripted runs, so listing them is not the index. Each
/// candidate session's facts then come from its own transcript, by the rule a running session's do
/// (`ClaudeCodeConnection.transcript(tail:)`): its title and when it was last used.
struct StartableSessions: Sendable {
    var history = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/history.jsonl")
    var transcripts = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    /// Whether Vignette can start a session at all. Without a launcher no row is offered.
    var canStart: @Sendable () -> Bool = { SendContext.herdrBinary() != nil }
    var folderExists: @Sendable (String) -> Bool = { path in
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &folder) && folder.boolValue
    }
    var now: @Sendable () -> Date = { Date() }
    var home = NSHomeDirectory()

    /// A project last used longer ago than this is not offered. On Pete's Mac on 2026-10-25, 16
    /// projects had been used in it with no session running and their folder still there.
    static let window: TimeInterval = 14 * 24 * 60 * 60
    /// How much of the history's end is read.
    static let historyBytes: UInt64 = 2 * 1024 * 1024
    /// How many of a project's sessions are read to find the one used last.
    static let sessionsPerProject = 3

    private static let readHistory = FileMemo<[Entry]>()
    private static let readTranscripts = FileMemo<ClaudeCodeConnection.Transcript>()

    func destinations() -> [AgentDestination] {
        guard canStart() else { return [] }
        let entries = Self.readHistory.value(of: history) { file in
            ClaudeCodeConnection.tail(of: file, bytes: Self.historyBytes).map(Self.entries(in:)) ?? []
        }
        let since = now().addingTimeInterval(-Self.window)
        return Self.projects(in: entries, since: since).filter { folderExists($0.folder) }.flatMap { project -> [AgentDestination] in
            let folders = [transcripts.appendingPathComponent(Self.transcriptFolder(of: project.folder))]
            let last = project.sessions.prefix(Self.sessionsPerProject).compactMap { session -> (String, ClaudeCodeConnection.Transcript)? in
                guard let file = ClaudeCodeConnection.transcriptFile(session: session, folders: folders) else { return nil }
                return (session, Self.readTranscripts.value(of: file) { ClaudeCodeConnection.tail(of: $0).map(ClaudeCodeConnection.transcript(tail:)) ?? .init() })
            }.max { ($0.1.lastUsed ?? .distantPast) < ($1.1.lastUsed ?? .distantPast) }
            let lastUsed = last?.1.lastUsed ?? project.lastTyped
            guard lastUsed >= since else { return [] }
            let found = SessionPlaces.resolve(folder: project.folder, home: home)
            return Self.rows(folder: project.folder, last: last, lastUsed: lastUsed, found: found, home: home)
        }
    }

    /// A project's rows: Continue last session when its last session's transcript is there, worded as
    /// a running session's row is, then New session.
    static func rows(folder: String, last: (session: String, transcript: ClaudeCodeConnection.Transcript)?, lastUsed: Date,
                     found: SessionPlaces.Found, home: String = NSHomeDirectory()) -> [AgentDestination] {
        var rows: [AgentDestination] = []
        if let last {
            var resume = ClaudeCodeConnection.destination(session: last.session, cwd: folder, transcript: last.transcript, found: found, home: home)
            resume.lastUsed = lastUsed
            resume.start = .resume(folder: folder)
            rows.append(resume)
        }
        let project = (folder as NSString).lastPathComponent
        rows.append(AgentDestination(id: SessionStart.newRowID(folder: folder), name: project.isEmpty ? "New session" : "New session in \(project)",
                                     detail: project, address: .claudeSession(""), lastUsed: lastUsed, place: found.place,
                                     branch: found.branch, hasOwnName: false, folder: folder, start: .new(folder: folder)))
        return rows
    }

    /// The folder Claude Code keeps `folder`'s transcripts in: every character but an ASCII letter or
    /// digit becomes "-". A transcript is looked for there only, since `--resume` looks only there.
    static func transcriptFolder(of folder: String) -> String {
        String(folder.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
    }

    // MARK: History

    /// One prompt in Claude Code's history.
    struct Entry: Equatable {
        let folder: String
        let session: String
        let time: Date
    }

    /// The prompts in a history tail, oldest first. A line without a folder, a session or a time is
    /// left out.
    static func entries(in tail: Data) -> [Entry] {
        tail.split(separator: UInt8(ascii: "\n")).compactMap { line in
            guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let folder = entry["project"] as? String, !folder.isEmpty,
                  let session = entry["sessionId"] as? String, !session.isEmpty,
                  let millis = entry["timestamp"] as? Double else { return nil }
            return Entry(folder: folder, session: session, time: Date(timeIntervalSince1970: millis / 1000))
        }
    }

    /// One project the person typed in since a moment: its folder, its sessions with the one typed
    /// in last first, and when that was.
    struct Project: Equatable {
        let folder: String
        let sessions: [String]
        let lastTyped: Date
    }

    /// The projects typed in since `since`, the one typed in last first.
    static func projects(in entries: [Entry], since: Date) -> [Project] {
        var order: [String] = []
        var sessions: [String: [String]] = [:]
        var last: [String: Date] = [:]
        for entry in entries.reversed() where entry.time >= since {
            if sessions[entry.folder] == nil { order.append(entry.folder); last[entry.folder] = entry.time }
            if !(sessions[entry.folder]?.contains(entry.session) ?? false) { sessions[entry.folder, default: []].append(entry.session) }
        }
        return order.map { Project(folder: $0, sessions: sessions[$0] ?? [], lastTyped: last[$0] ?? since) }
    }
}

/// What was read from each file, kept while the file's size and modification date stay the same. A
/// session that is not running does not change its transcript, and the history changes only when a
/// prompt is typed, so a listing reads each once.
final class FileMemo<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [String: (size: UInt64, modified: Date, value: Value)] = [:]

    func value(of file: URL, read: (URL) -> Value) -> Value {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = attributes?[.modificationDate] as? Date ?? .distantPast
        if let hit = lock.withLock({ kept[file.path] }), hit.size == size, hit.modified == modified { return hit.value }
        let value = read(file)
        lock.withLock { kept[file.path] = (size, modified, value) }
        return value
    }
}

// MARK: Where it runs

/// Starts a Claude Code session in a new herdr tab in its folder. herdr is the terminal host
/// Vignette already reads the focus of (`HerdrFocus`); the person's own shell in the tab runs
/// `claude`, so it is found as it is in any of their terminals.
struct HerdrLauncher: Sendable {
    var binary: @Sendable () -> String? = { SendContext.herdrBinary() }
    var run: @Sendable (String, [String], TimeInterval) -> (status: Int32, output: String, timedOut: Bool)? = {
        Subprocess.run($0, $1, timeout: $2)
    }

    /// What a start did: the tab and pane it made, or why it made none.
    enum Started: Equatable {
        case started(tab: String, pane: String)
        case failed(detail: String)
    }

    /// Opens a tab in `start`'s folder, labelled with its project, without moving herdr's focus, and
    /// types the command that starts session `id` into its shell. It blocks on herdr.
    func start(_ start: SessionStart, session id: String) -> Started {
        guard let herdr = binary() else { return .failed(detail: "no herdr") }
        var create = ["tab", "create", "--cwd", start.folder, "--no-focus"]
        if !start.label.isEmpty { create += ["--label", start.label] }
        guard let made = run(herdr, create, HerdrFocus.timeout) else { return .failed(detail: "herdr tab create did not run") }
        guard made.status == 0, !made.timedOut, let (tab, pane) = Self.created(in: Data(made.output.utf8)) else {
            return .failed(detail: "herdr tab create: \(Subprocess.detail(made.output) ?? "exit \(made.status)")")
        }
        let command = (["claude"] + start.arguments(session: id)).map(ReplyCommand.quoted).joined(separator: " ")
        guard let typed = run(herdr, ["pane", "run", pane, command], HerdrFocus.timeout), typed.status == 0, !typed.timedOut else {
            return .failed(detail: "herdr pane run \(pane) failed")
        }
        return .started(tab: tab, pane: pane)
    }

    /// The tab and its first pane from a `herdr tab create` answer.
    static func created(in data: Data) -> (tab: String, pane: String)? {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = root?["result"] as? [String: Any]
        guard let tab = (result?["tab"] as? [String: Any])?["tab_id"] as? String,
              let pane = (result?["root_pane"] as? [String: Any])?["pane_id"] as? String else { return nil }
        return (tab, pane)
    }
}
