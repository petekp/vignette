import Foundation

/// Codex's side of the responder: one `codex app-server` on a Codex home of Vignette's own, with
/// every switch in `CodexIsolation` and a model catalog that adds no tools, holding one `ephemeral`
/// thread whose base instructions are `LiveResponder.systemPrompt`
/// (docs/adr/0026-codex-answers-live-ink-too.md).
/// Each ask is one `turn/start` with the pictures as `data:` URLs and the strict answer schema. The
/// answer streams as `item/agentMessage/delta`, whose text is the answer's JSON.
///
/// Its warm-up is the isolation check: a turn on a thread whose model provider is
/// `CodexCheckProvider`, inside Vignette, and only when that request carries nothing but the prompt
/// and the warm-up does the thread asks go to start, with a warm-up of its own. It answers on the
/// sign-in kept in its own home (`CodexSignIn`).
@MainActor
final class CodexDriver: ResponderDriver {
    let client = AgentClient.codex
    let name = "Codex"

    /// The model live ink answers with when the account offers it, else the account's default: the
    /// only Codex model that answered all 12 of the spike's asks right (ADR 0026).
    static let model = "gpt-6-astra"
    static let effort = "low"
    /// The isolation check's model provider, as `-c model_providers.<name>` defines it.
    static let checkProvider = "vignette_check"

    private let binary: () -> String?
    private let home: URL
    private var process: JSONLinesProcess?
    private var check: CodexCheckProvider?
    private var report: ((ResponderEvent) -> Void)?
    private var nextID = 1
    private var replies: [Int: (Result<[String: Any], ServerError>) -> Void] = [:]
    private var checkThread: String?
    /// The thread asks go to, once the check has passed.
    private var thread: String?
    /// The turn under way on `thread`, from its `turn/started`.
    private var turn: String?
    /// An interrupt asked for before the turn under way had an id.
    private var interruptOnStart = false
    private var warmingUp = false
    private var partial = ""
    private var spoke = false
    private var usage = ""
    private var lastError: String?
    private var startedAt = Date()
    /// Counts the starts, so the check's answer to a start since stopped launches nothing.
    private var runs = 0
    /// The codex file the last start ran.
    private var started: CodexIsolation.Stamp?
    /// The codex file the isolation check refused, and the refusal, for as long as Vignette runs. A
    /// start of that same file answers with the refusal and runs nothing.
    private var refused: (file: CodexIsolation.Stamp, refusal: ResponderRefusal)?

    /// `binary` finds `codex` (`CodexConnection.binaryToRun`).
    init(binary: @escaping () -> String? = CodexConnection.binaryToRun, home: URL) {
        self.binary = binary
        self.home = home
    }

    func start(report: @escaping (ResponderEvent) -> Void) -> ResponderRefusal? {
        guard let binary = binary() else {
            Log.write("[live-ink] responder error no-codex")
            let reason = LiveResponder.Availability.notInstalled.problem(for: .codex) ?? ""
            return ResponderRefusal(failure: LiveResponder.Failure(reason: reason, detail: "no codex"), problem: reason)
        }
        started = CodexIsolation.Stamp(path: binary)
        if let refused, refused.file == started {
            Log.write("[live-ink] responder codex not started: the isolation check refused this codex path=\(binary)")
            return refused.refusal
        }
        let check: CodexCheckProvider
        do {
            check = try CodexCheckProvider()
        } catch {
            return refusal("could not listen: \(error)")
        }
        self.report = report
        self.check = check
        warmingUp = true
        startedAt = Date()
        runs += 1
        let run = runs
        let home = home
        let driver = WeakDriver(self)
        check.start { port in
            let catalog = port == nil ? nil : CodexIsolation.catalog(binary: binary, home: home)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { driver.value?.launch(binary, port: port, catalog: catalog, run: run) }
            }
        }
        return nil
    }

    func send(_ parts: [LiveResponder.Part]) {
        guard let thread else { return }
        partial = ""
        spoke = false
        usage = ""
        lastError = nil
        turn = nil
        interruptOnStart = false
        let input = parts.map { part -> [String: Any] in
            switch part {
            case .picture(let png): ["type": "image", "url": "data:image/png;base64," + png.base64EncodedString()]
            case .text(let text): ["type": "text", "text": text]
            }
        }
        call("turn/start", ["threadId": thread, "input": input, "outputSchema": Self.schema, "effort": Self.effort]) { [weak self] answer in
            if case .failure(let error) = answer { self?.report?(.turnFailed(error.message)) }
        }
    }

    func interrupt() {
        guard let thread else { return }
        guard let turn else {
            interruptOnStart = true
            return
        }
        call("turn/interrupt", ["threadId": thread, "turnId": turn]) { _ in }
    }

    func stop() {
        process?.stop()
        process = nil
        check?.stop()
        check = nil
        report = nil
        replies = [:]
        thread = nil
        checkThread = nil
        turn = nil
        interruptOnStart = false
        lastError = nil
        warmingUp = false
    }

    func reason(forError text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("unknown feature flag") {
            return "This version of Codex can't turn its tools off, so live ink can't use it."
        }
        if ["not signed in", "not logged in", "log in", "login", "unauthorized", "401", "authenticat", "refresh token"].contains(where: lower.contains) {
            return Self.signedOut
        }
        if lower.contains("limit") { return "Codex's usage limit is reached for now." }
        return Self.couldNotAnswer
    }

    nonisolated static let signedOut = "Codex isn't signed in for live ink. You can sign in in Settings."
    static let couldNotAnswer = "Codex couldn't answer. You can ask again."
    static let couldNotStart = "Vignette couldn't start Codex."

    // MARK: Starting

    /// The strict schema as the object `turn/start` takes.
    private static let schema: Any = (try? JSONSerialization.jsonObject(with: Data(LiveAnswer.strictSchema.utf8))) ?? [String: Any]()

    private func launch(_ binary: String, port: UInt16?, catalog: Data?, run: Int) {
        guard report != nil, run == runs else { return }
        guard let port else { return refuse("could not listen for the check") }
        guard let catalog else { return refuse("could not read codex debug models") }
        let file = home.appendingPathComponent("model-catalog.json")
        do {
            try catalog.write(to: file, options: .atomic)
        } catch {
            return refuse("could not write the model catalog: \(error.localizedDescription)")
        }
        let provider = #"{name="\#(Self.checkProvider)", base_url="http://127.0.0.1:\#(port)/v1", wire_api="responses", supports_websockets=false}"#
        let arguments = ["app-server"] + CodexIsolation.arguments + CodexSignIn.arguments
            + ["-c", "model_catalog_json=\(Self.toml(file.path))", "-c", "model_providers.\(Self.checkProvider)=\(provider)"]
        do {
            process = try JSONLinesProcess(binary: binary, arguments: arguments,
                                           environment: Subprocess.environment(for: binary, adding: ["CODEX_HOME": home.path]),
                                           folder: home,
                                           onLine: { [weak self] in self?.received($0) },
                                           onEnd: { [weak self] status in self?.ended(status) })
        } catch {
            Log.write("[live-ink] responder error launch \(error.localizedDescription) agent=codex")
            report?(.refused(ResponderRefusal(failure: LiveResponder.Failure(reason: Self.couldNotStart, detail: error.localizedDescription),
                                              problem: Self.couldNotStart)))
            return
        }
        Log.write("[live-ink] responder starting pid=\(process?.pid ?? 0) agent=codex")
        call("initialize", ["clientInfo": ["name": "Vignette", "version": BuildInfo.current.version],
                            "capabilities": ["experimentalApi": true]]) { [weak self] answer in
            guard let self else { return }
            if case .failure(let error) = answer { return refuse("initialize: \(error.message)") }
            process?.write(["method": "initialized"])
            call("account/read", [:]) { [weak self] answer in
                guard let self else { return }
                guard (try? answer.get())?["account"] is [String: Any] else { return refuse("not signed in: no account") }
                call("model/list", [:]) { [weak self] answer in self?.listed(answer) }
            }
        }
    }

    /// The model the account offers, then the check's thread on it.
    private func listed(_ answer: Result<[String: Any], ServerError>) {
        let models = (try? answer.get())?["data"] as? [[String: Any]] ?? []
        let offered = models.compactMap { $0["model"] as? String }
        let model = offered.contains(Self.model) ? Self.model : models.first { $0["isDefault"] as? Bool == true }?["model"] as? String
        guard let model else {
            if case .failure(let error) = answer { return refuse("model/list: \(error.message)") }
            return refuse("model/list offered no model")
        }
        checkModel = model
        Log.write("[live-ink] responder codex model=\(model) offered=\(offered.count)")
        startThread(model: model, provider: Self.checkProvider) { [weak self] id in
            self?.checkThread = id
            self?.warmUp(on: id)
        }
    }

    private func startThread(model: String, provider: String?, then started: @escaping (String) -> Void) {
        var params: [String: Any] = ["ephemeral": true, "baseInstructions": LiveResponder.systemPrompt, "model": model,
                                     "approvalPolicy": "never", "sandbox": "read-only", "cwd": home.path]
        if let provider { params["modelProvider"] = provider }
        call("thread/start", params) { [weak self] answer in
            guard let self else { return }
            guard let id = ((try? answer.get())?["thread"] as? [String: Any])?["id"] as? String else {
                if case .failure(let error) = answer { return refuse("thread/start: \(error.message)") }
                return refuse("thread/start answered no thread")
            }
            started(id)
        }
    }

    private func warmUp(on thread: String) {
        call("turn/start", ["threadId": thread, "input": [["type": "text", "text": LiveResponder.warmUp]],
                            "outputSchema": Self.schema, "effort": Self.effort]) { [weak self] answer in
            if case .failure(let error) = answer { self?.refuse("warm-up turn/start: \(error.message)") }
        }
    }

    /// The check's turn ended: the real thread starts only if what Codex sent the check is Vignette's
    /// prompt, the warm-up and no tools.
    private func checked(_ ended: [String: Any]) {
        let bodies = check?.requests ?? []
        check?.stop()
        check = nil
        let status = ended["status"] as? String
        guard status == "completed" else { return refuse("the check's turn \(status ?? "?"): \(Self.message(of: ended) ?? "")") }
        let refusal = bodies.isEmpty ? "no request reached the check"
            : bodies.lazy.compactMap { CodexIsolation.refusal(of: $0, prompt: LiveResponder.systemPrompt, warmUp: LiveResponder.warmUp) }.first
        if let refusal {
            Log.write("[live-ink] responder error not-isolated \(refusal) agent=codex")
            let refusal = ResponderRefusal(failure: LiveResponder.Failure(reason: "Live ink stopped Codex, which started with tools.", detail: "not isolated"),
                                           problem: "This version of Codex starts with tools, so live ink can't use it.")
            if let started { refused = (started, refusal) }
            report?(.refused(refusal))
            return
        }
        Log.write("[live-ink] responder codex isolated requests=\(bodies.count) ms=\(Int(Date().timeIntervalSince(startedAt) * 1000))")
        startThread(model: checkModel ?? Self.model, provider: nil) { [weak self] id in
            self?.thread = id
            self?.warmUp(on: id)
        }
    }

    /// The model the check's thread ran on, which the thread asks go to runs on too.
    private var checkModel: String?

    /// Codex did not start: the reason its error matches (`reason(forError:)`), else that it could not.
    private func refuse(_ detail: String) {
        Log.write("[live-ink] responder error codex \(detail)")
        let named = reason(forError: detail)
        let reason = named == Self.couldNotAnswer ? Self.couldNotStart : named
        report?(.refused(ResponderRefusal(failure: LiveResponder.Failure(reason: reason, detail: detail), problem: reason)))
    }

    private func refusal(_ detail: String) -> ResponderRefusal {
        Log.write("[live-ink] responder error codex \(detail)")
        return ResponderRefusal(failure: LiveResponder.Failure(reason: Self.couldNotStart, detail: detail), problem: Self.couldNotStart)
    }

    // MARK: Talking

    private func call(_ method: String, _ params: [String: Any], then reply: @escaping (Result<[String: Any], ServerError>) -> Void) {
        let id = nextID
        nextID += 1
        replies[id] = reply
        process?.write(["id": id, "method": method, "params": params])
    }

    private func received(_ message: [String: Any]) {
        let method = message["method"] as? String
        if let id = message["id"] as? Int, method == nil {
            let reply = replies.removeValue(forKey: id)
            if let result = message["result"] as? [String: Any] { reply?(.success(result)) }
            else { reply?(.failure(ServerError(message: Self.text(of: message["error"]) ?? "no result"))) }
            return
        }
        guard let method else { return }
        let params = message["params"] as? [String: Any] ?? [:]
        if let id = message["id"] {
            // A request from the server, which the responder never grants.
            process?.write(["id": id, "error": ["code": -32601, "message": "Vignette's live ink does not support \(method)"]])
            return
        }
        let onThread = params["threadId"] as? String
        switch method {
        case "turn/started" where onThread == thread && thread != nil:
            turn = (params["turn"] as? [String: Any])?["id"] as? String
            if interruptOnStart {
                interruptOnStart = false
                interrupt()
            }
        case "item/agentMessage/delta" where onThread == thread && thread != nil && !warmingUp:
            if !spoke {
                spoke = true
                report?(.output)
            }
            partial += params["delta"] as? String ?? ""
            report?(.answerSoFar(partial))
        case _ where method.hasPrefix("item/") && method.lowercased().hasSuffix("delta") && onThread == thread && !warmingUp:
            if !spoke {
                spoke = true
                report?(.output)
            }
        case "thread/tokenUsage/updated" where onThread == thread:
            let last = (params["tokenUsage"] as? [String: Any])?["last"] as? [String: Any] ?? [:]
            let counts = [("input", "inputTokens"), ("read", "cachedInputTokens"), ("output", "outputTokens"), ("thinking", "reasoningOutputTokens")]
            usage = counts.map { "\($0.0)=\((last[$0.1] as? Int).map(String.init) ?? "?")" }.joined(separator: " ")
        case "error":
            lastError = Self.text(of: params["error"])
        case "turn/completed":
            guard let ended = params["turn"] as? [String: Any] else { return }
            if onThread == checkThread && checkThread != nil && thread == nil { return checked(ended) }
            guard onThread == thread && thread != nil else { return }
            completed(ended)
        default:
            break
        }
    }

    private func completed(_ ended: [String: Any]) {
        turn = nil
        let status = ended["status"] as? String
        let milliseconds = ended["durationMs"] as? Int ?? 0
        if warmingUp {
            warmingUp = false
            guard status == "completed" else { return refuse("warm-up \(status ?? "?"): \(Self.message(of: ended) ?? lastError ?? "")") }
            report?(.ready("ms=\(Int(Date().timeIntervalSince(startedAt) * 1000)) turn=\(milliseconds)"))
            return
        }
        switch status {
        case "completed":
            let items = ended["items"] as? [[String: Any]] ?? []
            let text = items.last { $0["type"] as? String == "agentMessage" }?["text"] as? String ?? partial
            let answer = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) ?? text
            report?(.answered(answer, usage: "ms=\(milliseconds) \(usage)"))
        case "interrupted":
            report?(.interrupted("interrupted"))
        default:
            report?(.turnFailed(Self.message(of: ended) ?? lastError ?? "turn \(status ?? "?")"))
        }
    }

    private func ended(_ status: Int32) {
        let tail = process?.lastErrorLine ?? ""
        process = nil
        report?(.ended(status: status, tail: tail))
    }

    /// A turn's error message.
    private static func message(of turn: [String: Any]) -> String? {
        text(of: turn["error"])
    }

    private static func text(of error: Any?) -> String? {
        (error as? [String: Any])?["message"] as? String
    }

    /// An app-server's error answer.
    struct ServerError: Error {
        let message: String
    }

    /// `text` as a TOML basic string, for a `-c` value.
    static func toml(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// The driver, held weakly, for the check provider's queue. Read only on the main thread.
private final class WeakDriver: @unchecked Sendable {
    weak var value: CodexDriver?
    init(_ value: CodexDriver) { self.value = value }
}
