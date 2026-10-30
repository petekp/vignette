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

    private let binary: () -> String?
    private var process: JSONLinesProcess?
    private var report: ((ResponderEvent) -> Void)?
    private var warmingUp = false
    private var partial = ""
    /// The conversation's cost so far, from the last `result` line, which gives the total rather than
    /// the turn's own.
    private var totalCost = 0.0

    /// `binary` finds `claude`. In a test launch it is only what `VIGNETTE_CLAUDE` names, since any
    /// other found on the Mac runs on the person's own account.
    init(binary: @escaping () -> String? = LiveResponder.claudeBinary) {
        self.binary = binary
    }

    func start(report: @escaping (ResponderEvent) -> Void) -> ResponderRefusal? {
        guard let binary = binary() else {
            Log.write("[live-ink] responder error no-claude")
            return ResponderRefusal(failure: LiveResponder.Failure(reason: "Vignette couldn't find Claude Code.", detail: "no claude"),
                                    problem: "Live ink answers with Claude Code, and Vignette couldn't find the claude command.")
        }
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
            Log.write("[live-ink] responder error launch \(error.localizedDescription)")
            return ResponderRefusal(failure: LiveResponder.Failure(reason: "Vignette couldn't start Claude Code.", detail: error.localizedDescription),
                                    problem: "Vignette couldn't start Claude Code.")
        }
        self.report = report
        totalCost = 0
        warmingUp = true
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
            let tools = json["tools"] as? [String] ?? []
            let servers = json["mcp_servers"] as? [Any] ?? []
            guard Set(tools).isSubset(of: Self.allowedTools), servers.isEmpty else {
                Log.write("[live-ink] responder error not-isolated tools=\(tools.count) mcp=\(servers.count)")
                report?(.refused(ResponderRefusal(failure: LiveResponder.Failure(reason: "Live ink stopped Claude, which started with tools.", detail: "not isolated"),
                                                  problem: "This version of Claude Code starts with tools, so live ink can't use it.")))
                return
            }
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
            guard !failed else {
                Log.write("[live-ink] responder error warm-up \(detail)")
                let reason = reason(forError: detail)
                report?(.refused(ResponderRefusal(failure: LiveResponder.Failure(reason: reason, detail: detail), problem: reason)))
                return
            }
            report?(.ready("ms=\(milliseconds) cost=\(cost)"))
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

    func reason(forError text: String) -> String {
        let lower = text.lowercased()
        if ["log in", "login", "authenticat", "api key"].contains(where: lower.contains) {
            return "Claude Code isn't signed in. You can sign in by running claude in Terminal."
        }
        if lower.contains("limit") { return "Claude's usage limit is reached for now." }
        return "Claude couldn't answer. You can ask again."
    }

    private func ended(_ status: Int32) {
        let tail = process?.lastErrorLine ?? ""
        process = nil
        report?(.ended(status: status, tail: tail))
    }
}
