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

extension StartableSessions {
    static func isFolder(_ path: String) -> Bool {
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &folder) && folder.boolValue
    }
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
/// Claude Code's prompt history (`history.jsonl` in `AgentPlugin.claudeRoot`) is the index: one line per prompt the
/// person typed, with the folder Claude Code ran in and the session. It holds interactive sessions
/// only, and its last 2 MB went back 45 days on Pete's Mac (2026-10-25). The transcripts have 11,606
/// project folders there, most of them from scripted runs, so listing them is not the index. Each
/// candidate session's facts then come from its own transcript, by the rule a running session's do
/// (`ClaudeCodeConnection.transcript(tail:)`): its title and when it was last used.
struct StartableSessions: Sendable {
    /// None in a test launch on the person's own Claude Code folder (`AgentPlugin.claudeRoot`).
    var history = AgentPlugin.claudeRoot?.appendingPathComponent("history.jsonl")
    var transcripts = AgentPlugin.claudeRoot?.appendingPathComponent("projects")
    /// Whether Vignette can start a session at all. Without a launcher no row is offered.
    var canStart: @Sendable () -> Bool = { HerdrFocus.appToRun() != nil && HerdrFocus.coreToRun() != nil }
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
        guard canStart(), let history, let transcripts else { return [] }
        let entries = Self.readHistory.value(of: history) { file in
            ClaudeCodeConnection.tail(of: file, bytes: Self.historyBytes).map(Self.entries(in:)) ?? []
        }
        let since = now().addingTimeInterval(-Self.window)
        return Self.projects(in: entries, since: since).filter { Self.isFolder($0.folder) }.flatMap { project -> [AgentDestination] in
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

/// Starts a Claude Code session in a new tab of the Herdr window, in the space it shows, without
/// moving what it shows. herdr-core (`hc`) runs the terminal, labelled into that space and a new tab,
/// and the Herdr app names the tab with the project, as the session menu reads it (`HerdrFocus`).
struct HerdrLauncher: Sendable {
    var app: @Sendable () -> String? = { HerdrFocus.appToRun() }
    var core: @Sendable () -> String? = { HerdrFocus.coreToRun() }
    var run: @Sendable (String, [String], TimeInterval) -> HerdrFocus.Answer? = { Subprocess.run($0, $1, timeout: $2) }
    /// The person's login shell, which runs `claude` (`wrapped`).
    var loginShell: @Sendable () -> String? = { getpwuid(getuid())?.pointee.pw_shell.map { String(cString: $0) } }
    var newTab: @Sendable () -> String = { "tb" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
    var now: @Sendable () -> Date = { Date() }
    var later: @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void = {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + $0, execute: $1)
    }

    /// How long `herdr-app status` and `hc run` may take.
    static let timeout: TimeInterval = 10
    /// The Herdr app renames only a tab it shows, and it shows a new terminal's tab a moment after
    /// `hc run`, so the rename is tried every `renameStep` for up to `renameWait`.
    static let renameStep: TimeInterval = 0.5
    static let renameWait: TimeInterval = 5

    /// What a start did: the tab and terminal it made, the tab it asked for when `hc run` did not
    /// answer in time and the terminal may have started, or why it made none.
    enum Started: Equatable {
        case started(tab: String, terminal: String)
        case timedOut(tab: String, detail: String)
        case failed(detail: String)
    }

    /// Runs session `id` in a new terminal in `start`'s folder, in the space the Herdr window shows
    /// and a tab of its own, and names the tab with the project in the background. It blocks on
    /// `herdr-app status` and `hc run`. A terminal without the `herdr.space` label would be hidden from
    /// the window, so with no space nothing is started.
    func start(_ start: SessionStart, session id: String) -> Started {
        guard let app = app() else { return .failed(detail: "no Herdr app") }
        guard let core = core() else { return .failed(detail: "no hc") }
        guard let status = run(app, ["status"], Self.timeout) else { return .failed(detail: "herdr-app status did not run") }
        guard status.status == 0, !status.timedOut else {
            return .failed(detail: "herdr-app status: \(Subprocess.detail(status.output) ?? "exit \(status.status)")")
        }
        guard let space = Self.object(in: status.output)?["space"] as? String, !space.isEmpty else {
            return .failed(detail: "herdr-app status names no space")
        }
        let tab = newTab()
        let arguments = ["run", "--bg", "--json", "--cwd", start.folder, "--no-parent",
                         "--label", "herdr.space=\(space)", "--label", "herdr.tab=\(tab)", "--"]
            + Self.wrapped(["claude"] + start.arguments(session: id), loginShell: loginShell())
        guard let ran = run(core, arguments, Self.timeout) else { return .failed(detail: "hc run did not run") }
        if ran.timedOut {
            if !start.label.isEmpty { name(tab, start.label, app: app, since: now()) }
            return .timedOut(tab: tab, detail: "hc run: no answer in \(Int(Self.timeout)) s")
        }
        guard ran.status == 0, let terminal = Self.object(in: ran.output)?["address"] as? String else {
            return .failed(detail: "hc run: \(Subprocess.detail(ran.output) ?? "exit \(ran.status)")")
        }
        if !start.label.isEmpty { name(tab, start.label, app: app, since: now()) }
        return .started(tab: tab, terminal: terminal)
    }

    /// `program` run by the person's login shell, as a tab they opened would run it: login and
    /// interactive, so it reads their startup files and finds `claude` on their own `PATH`, then a
    /// shell of the same kind once `claude` exits. zsh and bash run the line; any other login shell,
    /// such as fish, gets `/bin/zsh`. Each word stays its own argument, and no shell parses one.
    static func wrapped(_ program: [String], loginShell: String?) -> [String] {
        let shell = loginShell.flatMap { ["zsh", "bash"].contains(($0 as NSString).lastPathComponent) ? $0 : nil } ?? "/bin/zsh"
        return [shell, "-lic", #""$@"; exec "$0" -li"#, shell] + program
    }

    private func name(_ tab: String, _ label: String, app: String, since began: Date) {
        later(Self.renameStep) { [self] in
            let request = (try? JSONSerialization.data(withJSONObject: ["id": tab, "name": label], options: [.sortedKeys]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let renamed = run(app, ["do", "tab.rename", request], Self.timeout)
            if let renamed, renamed.status == 0, !renamed.timedOut { return }
            guard now().timeIntervalSince(began) < Self.renameWait else {
                let detail = renamed.map { Subprocess.detail($0.output) ?? ($0.timedOut ? "timed out" : "exit \($0.status)") }
                return Log.write("[send] tab \(tab) not named: \(detail ?? "herdr-app did not run")")
            }
            name(tab, label, app: app, since: began)
        }
    }

    /// The JSON object in `output`, from its first `{` to its last `}`: `herdr-app status` prints
    /// one over several lines, and a warning on standard error may come before or after it.
    private static func object(in output: String) -> [String: Any]? {
        guard let open = output.firstIndex(of: "{"), let close = output.lastIndex(of: "}"), open < close else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(output[open...close].utf8)) as? [String: Any]
    }
}

extension AgentDestination {
    /// The session a send to this row reached: for a row Vignette starts, the one `record` names, which
    /// runs once the send is accepted; any other row as it is.
    func sent(as record: ScreenshotRequests.Record) -> AgentDestination {
        guard start != nil else { return self }
        return AgentDestination(id: record.destinationID, name: name, detail: detail, address: record.address, lastUsed: lastUsed,
                                place: place, branch: branch, hasOwnName: hasOwnName, folder: folder)
    }
}
