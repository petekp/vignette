import Foundation

/// Claude Code's side of the responder: one `claude -p` process on the person's own Claude sign-in,
/// with none of their customisations and no tools. Each ask is one user message, and the answer
/// streams back as the `StructuredOutput` call that `--json-schema` makes the model write. The
/// warm-up checks the process's `init` line, which lists its tools.
@MainActor
final class ClaudeDriver: ResponderDriver {
    let client = AgentClient.claude
    let name = "Claude"

    /// The prompt cache's lifetime. Asks come less than a minute apart, and a 5-minute cache write
    /// costs 1.25 times plain input where a 1-hour one costs 2 (docs/live-ink-ask-cost-2026-10-06.md).
    static let promptCacheTTL = "5m"
    /// The only tool the process may have: the one `--json-schema` adds to carry the answer.
    static let allowedTools: Set<String> = ["StructuredOutput"]

    let binary: @Sendable () -> String?
    let notFound = ResponderRefusal(failure: LiveResponder.Failure(reason: "Vignette couldn't find Claude Code.", detail: "no claude"),
                                    problem: "Live ink answers with Claude Code, and Vignette couldn't find the claude command.")
    let couldNotStart = "Vignette couldn't start Claude Code."
    let couldNotAnswer = "Claude couldn't answer. You can ask again."
    private var process: JSONLinesProcess?
    private var report: ((ResponderEvent) -> Void)?
    private var warmingUp = false
    /// The process's init line listed its tools, and they passed the check.
    private var sawInit = false
    private var partial = ""
    /// The conversation's cost so far, from the last `result` line, which gives the total rather than
    /// the turn's own.
    private var totalCost = 0.0

    /// `binary` finds `claude`. In a test launch it is only what `VIGNETTE_CLAUDE` names, since any
    /// other found on the Mac runs on the person's own account.
    init(binary: @escaping @Sendable () -> String? = { ClaudeDriver.findBinary() }) {
        self.binary = binary
    }

    /// A note offers Claude even when it is not installed, to say so.
    static let alwaysOffered = true

    /// The `claude` that answers live ink. In a test launch it is only what `VIGNETTE_CLAUDE` names.
    nonisolated static func findBinary() -> String? {
        AgentTools.forSessions("VIGNETTE_CLAUDE") { PluginHost.binary(for: .claude) }
    }

    /// `claude auth status`, which sends no message and costs nothing. A `claude` whose answer cannot
    /// be read counts as ready, and the first ask then reports what the process says.
    nonisolated static func availability() -> LiveResponder.Availability {
        findBinary().map(authStatus(binary:)) ?? .notInstalled
    }

    nonisolated static func problem(_ availability: LiveResponder.Availability) -> String? {
        switch availability {
        case .checking, .ready: nil
        case .notInstalled: "Vignette couldn't find Claude Code. You can send your ink to a session."
        case .signedOut: "Claude Code isn't signed in. You can sign in by running claude in Terminal."
        }
    }

    /// How long `claude auth status` may take before the check counts as ready.
    nonisolated static let authStatusLimit: TimeInterval = 10

    /// The answer of `claude auth status --json`. A check that does not answer within
    /// `authStatusLimit` stops the process and counts as ready.
    nonisolated private static func authStatus(binary: String) -> LiveResponder.Availability {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["auth", "status", "--json"]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.write("[live-ink] responder check could not run \(binary): \(error)")
            return .ready
        }
        let exited = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            exited.signal()
        }
        guard exited.wait(timeout: .now() + authStatusLimit) == .success else {
            process.terminate()
            Log.write("[live-ink] responder check timed out")
            return .ready
        }
        let answer = (try? JSONSerialization.jsonObject(with: output.fileHandleForReading.readDataToEndOfFile())) as? [String: Any]
        guard let loggedIn = answer?["loggedIn"] as? Bool else { return .ready }
        return loggedIn ? .ready : .signedOut
    }

    func start(binary: String, askWaiting: @escaping () -> Bool, report: @escaping (ResponderEvent) -> Void) -> String? {
        let arguments = [
            "-p", "--model", "sonnet",
            "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
            "--json-schema", LiveAnswer.schema,
            // The person's hooks, plugins, MCP servers and instructions stay out, and so do all tools:
            // started plainly, the process registered itself as a session in Vignette's inbox and
            // could read files (docs/live-ink-step2-spike-2026-10-04.md).
            "--safe-mode", "--tools", "",
            "--system-prompt", LiveResponder.systemPrompt,
            "--no-session-persistence",
        ]
        let folder = Identity.applicationSupportURL.appendingPathComponent("live-ink", isDirectory: true)
        let environment = Subprocess.environment(for: binary, adding: ["CLAUDE_CODE_PROMPT_CACHE_TTL": Self.promptCacheTTL])
        do {
            process = try JSONLinesProcess(binary: binary, arguments: arguments, environment: environment, folder: folder,
                                           onLine: { [weak self] in self?.received($0) },
                                           onEnd: { [weak self] status in self?.ended(status) })
        } catch {
            return "launch: \(error.localizedDescription)"
        }
        self.report = report
        totalCost = 0
        warmingUp = true
        sawInit = false
        Log.write("[live-ink] responder starting pid=\(process?.pid ?? 0) agent=claude")
        write(content: [["type": "text", "text": LiveResponder.warmUp]])
        return nil
    }

    func send(_ parts: [LiveResponder.Part]) {
        partial = ""
        write(content: parts.map { part in
            switch part {
            case .picture(let png):
                ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]]
            case .text(let text):
                ["type": "text", "text": text]
            }
        })
    }

    func interrupt() {
        process?.write(["type": "control_request", "request_id": UUID().uuidString, "request": ["subtype": "interrupt"]])
    }

    func stop() {
        process?.stop()
        process = nil
        report = nil
        warmingUp = false
    }

    private func write(content: [[String: Any]]) {
        process?.write(["type": "user", "message": ["role": "user", "content": content]])
    }

    private func received(_ json: [String: Any]) {
        switch json["type"] as? String {
        case "system" where json["subtype"] as? String == "init":
            // A missing or reshaped list proves nothing, so it fails the check as tools would.
            guard let tools = json["tools"] as? [String] else { return refuseUnisolated("init lists no tools") }
            let servers = json["mcp_servers"] as? [Any] ?? []
            guard Set(tools).isSubset(of: Self.allowedTools), servers.isEmpty else {
                return refuseUnisolated("tools=\(tools.count) mcp=\(servers.count)")
            }
            sawInit = true
        case "stream_event":
            guard !warmingUp, let event = json["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta", let delta = event["delta"] as? [String: Any] else { return }
            report?(.output)
            guard delta["type"] as? String == "input_json_delta", let piece = delta["partial_json"] as? String else { return }
            partial += piece
            report?(.answerSoFar(partial))
        case "result":
            finished(json)
        default:
            break
        }
    }

    private func finished(_ result: [String: Any]) {
        let failed = result["is_error"] as? Bool ?? false || result["subtype"] as? String != "success"
        let detail = (result["result"] as? String).map { String($0.prefix(200)) } ?? "no result"
        let milliseconds = result["duration_ms"] as? Int ?? 0
        let total = result["total_cost_usd"] as? Double
        let cost = total.map { String(format: "%.4f", $0 - totalCost) } ?? "?"
        if let total { totalCost = total }
        if warmingUp {
            warmingUp = false
            // The warm-up is sent before any screen content, so a process that never showed its tools stops here.
            guard failed || sawInit else { return refuseUnisolated("no init before the warm-up's result") }
            report?(failed ? .startFailed("warm-up: \(detail)") : .ready("ms=\(milliseconds) cost=\(cost)"))
            return
        }
        if failed {
            report?(.turnFailed(detail))
        } else {
            report?(.answered(result["structured_output"] as Any, usage: "ms=\(milliseconds) cost=\(cost) \(Self.tokens(in: result))"))
        }
    }

    /// A `result` line's tokens for the log: plain input, written to and read from the cache, output,
    /// and the part of the output that was thinking.
    private static func tokens(in result: [String: Any]) -> String {
        let usage = result["usage"] as? [String: Any] ?? [:]
        let thinking = (usage["output_tokens_details"] as? [String: Any])?["thinking_tokens"]
        let counts: [(String, Any?)] = [("input", usage["input_tokens"]), ("written", usage["cache_creation_input_tokens"]),
                                        ("read", usage["cache_read_input_tokens"]), ("output", usage["output_tokens"]), ("thinking", thinking)]
        return counts.map { "\($0.0)=\(($0.1 as? Int).map(String.init) ?? "?")" }.joined(separator: " ")
    }

    func reason(forError text: String) -> String? {
        let lower = text.lowercased()
        if ["log in", "login", "authenticat", "api key"].contains(where: lower.contains) { return Self.problem(.signedOut) }
        if lower.contains("limit") { return "Claude's usage limit is reached for now." }
        return nil
    }

    /// Stops this `claude` for good: it may have tools, so no screen content goes to it.
    private func refuseUnisolated(_ detail: String) {
        Log.write("[live-ink] responder error not-isolated \(detail)")
        report?(.refused(ResponderRefusal(failure: LiveResponder.Failure(reason: "Live ink stopped Claude, which started with tools.", detail: "not isolated"),
                                          problem: "This version of Claude Code starts with tools, so live ink can't use it.",
                                          retry: .onceBinaryChanges)))
    }

    private func ended(_ status: Int32) {
        let tail = process?.lastErrorLine ?? ""
        process = nil
        report?(.ended(status: status, tail: tail))
    }
}
