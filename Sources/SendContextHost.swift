import AppKit
import Darwin

/// The agent session a captured window shows, when it can be known for certain
/// (docs/session-detection-exploration-2026-10-08.md, Result 5). Written as `host`, or as
/// `hostWhyNot` with the first link that failed.
extension SendContext {
    /// One of this user's processes.
    struct ProcessEntry: Sendable {
        let pid: pid_t
        let parent: pid_t
        /// The kernel's name for it, cut to `MAXCOMLEN` bytes.
        let name: String
        let hasTerminal: Bool
    }

    /// This user's processes, from one `sysctl`. Nil when the table could not be read.
    static func processes() -> [ProcessEntry]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        let stride = MemoryLayout<kinfo_proc>.stride
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return nil }
            // Room for the processes that start between the two calls.
            var table = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 64)
            size = table.count * stride
            let status = table.withUnsafeMutableBytes { sysctl(&mib, 4, $0.baseAddress, &size, nil, 0) }
            guard status == 0 else {
                if errno == ENOMEM { continue }
                return nil
            }
            return table.prefix(size / stride).map { entry in
                let name = withUnsafeBytes(of: entry.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                return ProcessEntry(pid: entry.kp_proc.p_pid, parent: entry.kp_eproc.e_ppid, name: name,
                                    hasTerminal: entry.kp_eproc.e_tdev != -1)
            }
        }
        return nil
    }

    // MARK: herdr

    enum HerdrRead: Equatable { case noBinary, failed, answered(Data) }

    /// What one `herdr pane list` gave, and when.
    struct HerdrAnswer: Equatable {
        let read: HerdrRead
        let at: Date
    }

    /// The herdr `HerdrFocus.read` runs by default: none in a test launch unless VIGNETTE_HERDR names
    /// one. It must stay the same rule as that default.
    static func herdrBinary() -> String? {
        AgentTools.forSessions("VIGNETTE_HERDR") { HerdrFocus.binary() }
    }

    /// `HerdrFocus.read`, keeping herdr's raw answer for the host rule, so herdr runs once per record.
    static func readHerdr(binary: () -> String? = { SendContext.herdrBinary() },
                          run: (String, [String], TimeInterval) -> (status: Int32, output: String, timedOut: Bool)? = {
                              Subprocess.run($0, $1, timeout: $2)
                          }) -> (focus: HerdrFocus?, answer: HerdrAnswer) {
        var ran = false
        var answer: Data?
        let focus = HerdrFocus.read(binary: binary, run: { herdr, arguments, timeout in
            ran = true
            let result = run(herdr, arguments, timeout)
            if let result, result.status == 0 { answer = Data(result.output.utf8) }
            return result
        })
        let at = Date()
        guard ran else { return (focus, HerdrAnswer(read: .noBinary, at: at)) }
        return (focus, HerdrAnswer(read: answer.map { .answered($0) } ?? .failed, at: at))
    }

    /// One pane in a `herdr pane list` answer, agent or not.
    struct HerdrPane: Equatable {
        let tab: String
        let focused: Bool
        let agent: String?
        let session: String?
    }

    /// Every pane in a `herdr pane list` answer. Nil when it does not parse as a pane list. It reads
    /// the keys `HerdrFocus` reads, since `HerdrFocus.agents` drops the panes running no agent, which
    /// the split-tab rule counts.
    static func herdrPanes(in data: Data) -> [HerdrPane]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let panes = (root["result"] as? [String: Any])?["panes"] as? [[String: Any]] else { return nil }
        return panes.map { pane in
            let session = (pane["agent_session"] as? [String: Any])?["value"] as? String
            return HerdrPane(tab: pane["tab_id"] as? String ?? "", focused: pane["focused"] as? Bool == true,
                             agent: pane["agent"] as? String, session: (session?.isEmpty ?? true) ? nil : session)
        }
    }

    /// The herdr clients under a terminal app, every client, and the app's children on a terminal.
    typealias HerdrClients = (under: Int, all: Int, surfaces: Int)

    /// herdr's clients: processes named in `names`, on a terminal. herdr's server has launchd for its
    /// parent, and a `herdr` run inside a pane, as the agents' hooks run it, descends from the server,
    /// so neither is a client. `own` is Vignette, whose own herdr reads are not clients either.
    /// `surfaces` counts `app`'s children on a terminal: in Ghostty, the one terminal measured, one per
    /// window, tab or split it draws.
    static func herdrClients(of app: pid_t, own: pid_t, names: Set<String>, in table: [ProcessEntry]) -> HerdrClients {
        let byPid = Dictionary(table.map { ($0.pid, $0) }) { first, _ in first }
        var under = 0, all = 0
        for entry in table where names.contains(entry.name) && entry.hasTerminal && entry.parent != 1 {
            var pid = entry.parent, isClient = true, underApp = false, steps = 0
            while pid > 1, steps < 64 {
                if pid == own { isClient = false; break }
                if pid == app { underApp = true }
                guard let parent = byPid[pid] else { break }
                if names.contains(parent.name) { isClient = false; break }
                pid = parent.parent
                steps += 1
            }
            guard isClient else { continue }
            all += 1
            if underApp { under += 1 }
        }
        let surfaces = table.filter { $0.parent == app && $0.hasTerminal }.count
        return (under, all, surfaces)
    }

    /// "herdr", and the name the kernel gives the herdr binary Vignette would run.
    private static func herdrNames() -> Set<String> {
        var names: Set<String> = ["herdr"]
        if let binary = herdrBinary() {
            let name = URL(fileURLWithPath: binary).resolvingSymlinksInPath().lastPathComponent
            names.insert(String(decoding: name.utf8.prefix(Int(MAXCOMLEN)), as: UTF8.self))
        }
        return names
    }

    // MARK: The decision

    enum ShownWhyNot: String {
        case noWindow = "no-window"
        case display
        case codexNoThread = "codex-no-thread"
        case agentAppUnread = "agent-app-unread"
        case notAgentWindow = "not-agent-window"
        case processesUnread = "processes-unread"
        case noHerdrClient = "no-herdr-client"
        case unknownSurfaces = "unknown-surfaces"
        case severalSurfaces = "several-surfaces"
        case severalClients = "several-clients"
        case noHerdr = "no-herdr"
        case herdrUnread = "herdr-unread"
        case noFocus = "no-focus"
        case severalFocused = "several-focused"
        case splitTab = "split-tab"
        case noSession = "no-session"
        case otherAgent = "other-agent"
    }

    /// The session a window shows, or the first link that did not hold.
    enum Shown: Equatable {
        case session(client: String, id: String, how: String, live: Bool?)
        case unknown(ShownWhyNot)
    }

    /// The links a terminal's processes decide: the first that fails, or nil when herdr's answer
    /// decides the rest. `clients` is nil when the process table could not be read.
    static func terminalWhyNot(_ clients: HerdrClients?) -> ShownWhyNot? {
        guard let clients else { return .processesUnread }
        if clients.under == 0 { return .noHerdrClient }
        // With several surfaces, which one shows herdr is unknown. None counted means the terminal
        // runs its shells under some other process, so its surfaces cannot be counted at all.
        if clients.surfaces == 0 { return .unknownSurfaces }
        if clients.surfaces > 1 { return .severalSurfaces }
        if clients.all > 1 { return .severalClients }
        return nil
    }

    /// The session the window shows, only when every link holds. `kind` is the record's kind of app,
    /// `clients` what `herdrClients` counted for a terminal's app, `codexThread` the thread
    /// `AgentApp.shownThread` read for the Codex app, and `live` the sessions with a live Claude Code inbox.
    static func shown(hasWindow: Bool, capture: String?, bundle: String, kind: String,
                      clients: HerdrClients?, herdr: HerdrRead?, codexThread: String?, live: Set<String>) -> Shown {
        if capture == "display" { return .unknown(.display) }
        guard hasWindow else { return .unknown(.noWindow) }
        if bundle == AgentApp.codexBundleID {
            guard let codexThread, UUID(uuidString: codexThread) != nil else { return .unknown(.codexNoThread) }
            return .session(client: AgentClient.codex.rawValue, id: codexThread, how: "codex-app", live: nil)
        }
        if kind == "agent-app" { return .unknown(.agentAppUnread) }
        guard kind == "terminal" else { return .unknown(.notAgentWindow) }
        if let why = terminalWhyNot(clients) { return .unknown(why) }
        let panes: [HerdrPane]
        switch herdr {
        case .noBinary: return .unknown(.noHerdr)
        case .failed, nil: return .unknown(.herdrUnread)
        case .answered(let data):
            guard let parsed = herdrPanes(in: data) else { return .unknown(.herdrUnread) }
            panes = parsed
        }
        let focused = panes.filter(\.focused)
        guard let pane = focused.first else { return .unknown(.noFocus) }
        if focused.count > 1 { return .unknown(.severalFocused) }
        if panes.filter({ $0.tab == pane.tab }).count > 1 { return .unknown(.splitTab) }
        guard let agent = pane.agent, let id = pane.session, UUID(uuidString: id) != nil else { return .unknown(.noSession) }
        guard let client = AgentClient(rawValue: agent) else { return .unknown(.otherAgent) }
        return .session(client: client.rawValue, id: id, how: "herdr", live: client == .claude ? live.contains(id) : nil)
    }

    /// The fields a decision writes: `host` or `hostWhyNot`, `hostMs`, and `hostLagMs`, how long after
    /// `at` the answer was read: when herdr answered or the Codex app's log named a thread (`readAt`).
    static func hostRecord(_ shown: Shown, hostMs: Int, readAt: Date?, at: Date) -> [String: Any] {
        var out: [String: Any] = ["hostMs": hostMs]
        switch shown {
        case .session(let client, let id, let how, let live):
            var host: [String: Any] = ["client": client, "id": id, "how": how]
            if let live { host["live"] = live }
            out["host"] = host
        case .unknown(let why):
            out["hostWhyNot"] = why.rawValue
        }
        if let readAt { out["hostLagMs"] = Int(readAt.timeIntervalSince(at) * 1000) }
        return out
    }

    /// Reads what the decision needs and writes its fields. Runs on the log's queue: it reads
    /// processes and files, and runs herdr when the listing did not and its answer would decide.
    static func hostFields(capture: String?, seen: Seen, at: Date) -> [String: Any] {
        let started = Date()
        var thread: String?
        var clients: HerdrClients?
        var herdr = seen.herdr
        var readAt: Date?
        if let pid = seen.pid, capture != "display" {
            if seen.bundle == AgentApp.codexBundleID {
                thread = AgentApp.shownThread(pid: pid, launched: seen.launched)
                if thread != nil { readAt = Date() }
            } else if seen.kind == "terminal" {
                let names = herdrNames()
                clients = processes().map { herdrClients(of: pid, own: getpid(), names: names, in: $0) }
                if terminalWhyNot(clients) == nil {
                    if herdr == nil { herdr = readHerdr().answer }
                    if case .answered = herdr?.read { readAt = herdr?.at }
                }
            }
        }
        let decided = shown(hasWindow: seen.pid != nil, capture: capture, bundle: seen.bundle, kind: seen.kind,
                            clients: clients, herdr: herdr?.read, codexThread: thread, live: seen.live)
        return hostRecord(decided, hostMs: Int(Date().timeIntervalSince(started) * 1000), readAt: readAt, at: at)
    }
}
