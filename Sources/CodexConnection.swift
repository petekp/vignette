import Foundation

/// `codex queue --thread <UUID> --message <line>` hands a message to a persistent Codex thread:
/// the command finds the engine that owns it, an idle session starts a turn, and a busy one runs
/// it next. That engine resolves the UUID, so a thread no engine has is an error rather than
/// another thread. Vignette never starts, resumes, or stops a Codex session.
struct CodexConnection: AgentConnection {
    let client = AgentClient.codex
    /// The threads change only when one is used, and a discovery starts a process of its own.
    let keepsList = true
    var binary: () -> String? = CodexConnection.binaryToRun
    var run: @Sendable (String, [String], TimeInterval) -> (status: Int32, output: String, timedOut: Bool)? = {
        Subprocess.run($0, $1, timeout: $2)
    }
    /// One stdio conversation with an app-server. Injected so a test never spawns codex.
    var converse: @Sendable (String, [String], [String]) -> [String] = {
        AppServer.converse($0, $1, $2)
    }
    /// Whether an engine has the thread loaded. Injected so a test never reads the person's Codex folder.
    var isLoaded: @Sendable (String) -> Bool = { CodexConnection.isLoaded($0) }
    /// The rollouts of the threads sent to, which say when a sent line's turn ends.
    let turns = CodexTurns()
    let reportsTurns = true

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

    /// The codex Vignette runs, for Send and for live ink alike: the Codex app's own first. In a test
    /// launch it is only what `VIGNETTE_CODEX` names.
    static func binaryToRun() -> String? {
        AgentTools.forSessions("VIGNETTE_CODEX") { binary() }
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
        let listed = AppServer.threads(in: lines).map { Self.destination($0) }
        guard let shown, let thread = AppServer.read(in: lines), thread.id == shown,
              !listed.contains(where: { $0.id == shown }) else { return listed }
        return listed + [Self.destination(thread)]
    }

    static func destination(_ thread: AppServer.Thread, home: String = NSHomeDirectory()) -> AgentDestination {
        let found = SessionPlaces.resolve(folder: thread.cwd, originURL: thread.originURL, home: home)
        return AgentDestination(
            id: thread.id,
            name: name(of: thread),
            detail: (thread.cwd as NSString).lastPathComponent,
            address: .codexThread(uuid: thread.id),
            lastUsed: thread.recencyAt,
            place: found.place,
            branch: found.branch,
            started: thread.createdAt)
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
        submit(line, to: destination, watchingTurn: false)
    }

    func submit(_ line: String, to destination: AgentDestination, watchingTurn: Bool,
                completion: @escaping @Sendable (SubmissionOutcome) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { completion(submit(line, to: destination, watchingTurn: watchingTurn)) }
    }

    /// A line whose turn is watched has its thread's rollout found first, which runs an app-server.
    func submit(_ line: String, to destination: AgentDestination, watchingTurn: Bool) -> SubmissionOutcome {
        guard case .codexThread(let uuid) = destination.address else {
            return .notSubmitted(code: .noAgent, detail: "not a Codex destination", reason: SubmissionOutcome.internalReason)
        }
        guard let codex = binary() else {
            return .notSubmitted(code: .noAgent, detail: "no codex at \(AgentTools.searched("codex", fixed: Self.binaryPaths).joined(separator: " ")) or on the login shell's PATH",
                                 reason: "Sending to Codex needs the Codex app or its CLI.")
        }
        // Before the line goes, so the rollout is read from before the engine writes it.
        if watchingTurn { turns.sending(line, to: uuid, rollout: rollout(of: uuid, codex: codex), loaded: isLoaded(uuid)) }
        guard let result = run(codex, Self.arguments(thread: uuid, message: line), Self.queueTimeout) else {
            turns.unsent(line, to: uuid)
            return .notSubmitted(code: .sendFailed, detail: "codex queue did not run", reason: "Codex couldn't start. The log has details.")
        }
        if result.timedOut {
            return .uncertain(detail: "codex queue did not answer in \(Int(Self.queueTimeout)) s",
                              reason: "Codex didn't confirm it. It may still have arrived.")
        }
        guard result.status == 0 else {
            turns.unsent(line, to: uuid)
            return Self.failure(output: result.output, thread: uuid)
        }
        guard isLoaded(uuid) else {
            return .queued(detail: "thread=\(uuid) not loaded", reason: "Codex reads it when you open this thread.")
        }
        return .accepted(detail: "thread=\(uuid)")
    }

    /// Where the thread is in its turns, from its rollout, once a line went to it this launch. It
    /// reads files and can start an app-server, so it never runs on the main thread.
    func turn(of destination: AgentDestination) -> SessionTurn? {
        guard case .codexThread(let uuid) = destination.address else { return nil }
        return turns.turn(of: uuid, loaded: isLoaded) { thread in binary().map { rollout(of: thread, codex: $0) } ?? .unknown }
    }

    /// The thread's rollout file, as an app-server of its own reads it from the store.
    private func rollout(of thread: String, codex: String) -> CodexTurns.Path {
        AppServer.rolloutPath(in: converse(codex, ["app-server"], AppServer.readRequests(thread)))
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
