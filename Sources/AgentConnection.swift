import Foundation

/// How Vignette reaches one agent session. The terminal a session happens to be displayed in is
/// not part of this: a destination is a conversation, and a connection is the native call that
/// puts a request into it. See CONTEXT.md for the words.
///
/// Two routes exist. Codex is addressed by its thread UUID at an App Server endpoint the person
/// configured, and the runtime itself refuses a UUID it does not own. Claude Code is addressed by
/// its session id, which herdr reports for the pane running it; herdr's submission API takes a
/// pane and has no expected-session parameter, so Vignette checks the pane still holds that exact
/// session immediately before it submits. `Address.guardTier` is the difference, and it is
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
    /// A Codex thread, and the App Server endpoint that owns it. Nil endpoint means the local
    /// default, which exists only where a Codex daemon is installed.
    case codexThread(uuid: String, endpoint: String?)

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

    /// The Codex thread this address names, for telling a discovered session from a configured
    /// one that is the same conversation. Nil for every other client.
    var threadUUID: String? {
        if case .codexThread(let uuid, _) = self { return uuid }
        return nil
    }

    /// How the address reads in `[state]` and in a request record's log line.
    var description: String {
        switch self {
        case .claudeSession(let id): return "claude session=\(id)"
        case .codexThread(let uuid, let endpoint): return "codex thread=\(uuid)\(endpoint.map { " endpoint=\($0)" } ?? "")"
        }
    }
}

/// One agent session a request may be addressed to.
struct AgentDestination: Equatable, Identifiable {
    /// Vignette's stable handle for it: the `id` in settings.json for a configured Codex
    /// destination, the session id for Claude Code. It is what a request records, so a reply's
    /// card can offer the conversation it came from.
    let id: String
    let name: String
    /// Enough to tell two alike apart: the project folder, or the pane's title.
    var detail: String = ""
    let address: AgentAddress

    var client: AgentClient { address.client }
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
    /// The sessions this route can address right now. Empty when the route cannot enumerate.
    func destinations() -> [AgentDestination]
    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome
}

// MARK: Claude Code, through herdr

/// Claude Code has no local command that puts a message into a session that is already running.
/// herdr, which owns the pane, does: `herdr agent prompt` submits one line to an agent it is
/// running, refusing one that is waiting on a prompt of its own. herdr also reports each pane's
/// Claude Code session id, so Vignette addresses the session and resolves it to a pane at send
/// time; a session that is in no pane is an error and never a different pane's.
struct ClaudeCodeConnection: AgentConnection {
    let client = AgentClient.claude
    /// Where herdr may be, and how long one call may take. Injected so tests never run herdr.
    var binary: () -> String? = { Send.binary() }
    var run: @Sendable (String, [String], TimeInterval) -> (status: Int32, output: String, timedOut: Bool)? = {
        Send.launch($0, $1, timeout: $2)
    }

    static let listTimeout: TimeInterval = 10
    static let promptTimeout: TimeInterval = 20

    func destinations() -> [AgentDestination] {
        targets().compactMap(Self.destination)
    }

    /// One Claude Code pane as a destination, or nil for a pane whose session herdr cannot name.
    /// The name is the pane's title, which says what that session is doing; the detail is the
    /// project it is in, for two panes with the same title.
    static func destination(_ target: Send.Target) -> AgentDestination? {
        guard let session = target.session else { return nil }
        return AgentDestination(
            id: session,
            name: target.title.isEmpty ? target.id : target.title,
            detail: (target.cwd as NSString).lastPathComponent,
            address: .claudeSession(session))
    }

    /// Every Claude Code session herdr is running. A session herdr cannot identify is left out: a
    /// pane id is not a conversation, and addressing one would be the thing this route must not do.
    private func targets() -> [Send.Target] {
        guard let herdr = binary(), let list = run(herdr, ["agent", "list"], Self.listTimeout), list.status == 0 else { return [] }
        return Send.targets(fromAgentList: Data(list.output.utf8)).filter { $0.kind == "claude" && $0.session != nil }
    }

    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome {
        guard case .claudeSession(let session) = destination.address else {
            return .notSubmitted(code: .noAgent, detail: "not a Claude Code destination")
        }
        guard let herdr = binary() else {
            return .notSubmitted(code: .noAgent, detail: "no herdr at \(Send.binaryPaths.joined(separator: " "))")
        }
        guard let list = run(herdr, ["agent", "list"], Self.listTimeout) else {
            return .notSubmitted(code: .noAgent, detail: "herdr agent list did not run")
        }
        guard list.status == 0 else {
            return .notSubmitted(code: .noAgent, detail: "herdr agent list: \(Send.detail(list.output) ?? "no output")")
        }
        // The guard: the pane has to be running this exact session now, not a session it ran
        // before. A session in no pane is an error; it is never redirected to another one.
        let agents = Send.targets(fromAgentList: Data(list.output.utf8))
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
            let detail = Send.detail(sent.output) ?? "herdr said nothing"
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

/// `codex queue --thread <UUID> --message <line>` hands a message to a persistent Codex thread at
/// the App Server that owns it: an idle session starts a turn, a busy one runs it next. The thread
/// UUID is resolved by that server, so a thread it does not own is an error rather than another
/// thread. Vignette never starts, resumes, or stops a Codex server or session; the endpoint and
/// the thread are configuration.
struct CodexConnection: AgentConnection {
    let client = AgentClient.codex
    /// The configured Codex destinations, as settings.json names them.
    var configured: [AgentDestination] = []
    var binary: () -> String? = { CodexConnection.binary() }
    var run: @Sendable (String, [String], TimeInterval) -> (status: Int32, output: String, timedOut: Bool)? = {
        Send.launch($0, $1, timeout: $2)
    }
    /// One stdio conversation with a running app-server. Injected so a test never spawns codex.
    var converse: @Sendable (String, [String], [String]) -> [String] = {
        AppServer.converse($0, $1, $2)
    }
    /// Whether a running app-server has published its control socket. Injected for the same reason.
    var controlSocketExists: @Sendable () -> Bool = { AppServer.controlSocketExists }

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

    /// Every Codex session that can be addressed: the ones a running app-server reports, plus the
    /// ones settings.json names. A configured entry the server also reported is kept once, under
    /// the configured name, because that is the name the person chose.
    func destinations() -> [AgentDestination] {
        let discovered = self.discovered()
        let named = Set(configured.compactMap(\.address.threadUUID))
        return configured + discovered.filter { !named.contains($0.address.threadUUID ?? "") }
    }

    /// Every Codex session the machine knows about. `thread/list` reads the store all of them
    /// share, so any app-server can answer it: a running daemon's control socket when there is
    /// one, and otherwise a server started for the length of this one call. That is why
    /// discovery needs no daemon and no endpoint, and why the sessions a person actually has,
    /// which the ChatGPT desktop app owns, are in the menu on a Mac with neither.
    private func discovered() -> [AgentDestination] {
        guard let codex = binary() else { return [] }
        let arguments = controlSocketExists()
            ? ["app-server", "proxy", "--sock", AppServer.controlSocket.path]
            : ["app-server"]
        let lines = converse(codex, arguments, AppServer.discoveryRequests())
        return AppServer.threads(in: lines).map { thread in
            AgentDestination(
                id: thread.id,
                name: thread.name?.isEmpty == false ? thread.name! : "Codex \(thread.id.prefix(8))",
                detail: (thread.cwd as NSString).lastPathComponent,
                // No endpoint: `codex queue --thread <uuid>` finds the engine that owns the thread
                // by itself, including the desktop app's, which listens on nothing (verified
                // 2026-09-21, a message queued with no --remote arrived in a Codex Desktop
                // session). An endpoint stays a setting, for a server that is not this Mac's.
                address: .codexThread(uuid: thread.id, endpoint: nil))
        }
    }

    /// The argv for one queue call. Built as a list, never a shell line: an image path with spaces
    /// and a message with quotes are both one element.
    static func arguments(thread: String, endpoint: String?, message: String) -> [String] {
        var args = ["queue", "--thread", thread]
        if let endpoint, !endpoint.isEmpty { args += ["--remote", endpoint] }
        return args + ["--message", message]
    }

    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome {
        guard case .codexThread(let uuid, let endpoint) = destination.address else {
            return .notSubmitted(code: .noAgent, detail: "not a Codex destination")
        }
        guard let codex = binary() else {
            return .notSubmitted(code: .noAgent, detail: "no codex at \(Self.binaryPaths.joined(separator: " "))")
        }
        guard let result = run(codex, Self.arguments(thread: uuid, endpoint: endpoint, message: line), Self.queueTimeout) else {
            return .notSubmitted(code: .sendFailed, detail: "codex queue did not run")
        }
        if result.timedOut {
            return .uncertain(detail: "codex queue did not answer in \(Int(Self.queueTimeout)) s")
        }
        guard result.status == 0 else {
            return Self.failure(output: result.output, thread: uuid)
        }
        return .accepted(detail: "thread=\(uuid)\(endpoint.map { " endpoint=\($0)" } ?? "")")
    }

    /// What a nonzero `codex queue` means. A thread the server does not have, or a server that is
    /// not there, is the destination having changed; anything else is a definite non-submission.
    static func failure(output: String, thread: String) -> SubmissionOutcome {
        let detail = Send.detail(output) ?? "codex said nothing"
        let lower = detail.lowercased()
        let gone = ["thread not found", "no such thread", "session not found", "unknown thread",
                    "connection refused", "failed to connect", "connection reset"]
        if gone.contains(where: lower.contains) {
            return .destinationChanged(detail: detail)
        }
        return .notSubmitted(code: .sendFailed, detail: detail)
    }
}
