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
/// and the warm-up does the thread asks go to start. That thread warms up too, unless an ask is
/// waiting by then, which is its first turn instead. It answers on the sign-in kept in its own home
/// (`CodexSignIn`).
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

    let binary: @Sendable () -> String?
    let notFound = ResponderRefusal(reason: LiveResponder.Availability.notInstalled.problem(for: .codex) ?? "", detail: "no codex")
    let couldNotStart = "Vignette couldn't start Codex."
    let couldNotAnswer = "Codex couldn't answer. You can ask again."
    private let home: URL
    /// The start under way or running. `stop` drops it, and nothing it began reports after that.
    private var run: CodexRun?

    /// `binary` finds `codex` (`CodexConnection.binaryToRun`).
    init(binary: @escaping @Sendable () -> String? = { CodexConnection.binaryToRun() }, home: URL) {
        self.binary = binary
        self.home = home
    }

    func start(binary: String, askWaiting: @escaping () -> Bool, report: @escaping (ResponderEvent) -> Void) -> String? {
        do {
            run = try CodexRun(binary: binary, home: home, askWaiting: askWaiting, report: report)
        } catch {
            return "could not listen: \(error)"
        }
        return nil
    }

    func send(_ parts: [LiveResponder.Part]) {
        run?.send(parts)
    }

    func interrupt() {
        run?.interrupt()
    }

    func stop() {
        run?.stop()
        run = nil
    }

    func reason(forError text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("unknown feature flag") {
            return "This version of Codex can't turn its tools off, so live ink can't use it."
        }
        if ["not signed in", "not logged in", "log in", "login", "unauthorized", "401", "authenticat", "refresh token"].contains(where: lower.contains) {
            return Self.signedOut
        }
        if lower.contains("limit") { return "Codex's usage limit is reached for now." }
        return nil
    }

    nonisolated static let signedOut = "Codex isn't signed in for live ink. You can sign in in Settings."

    /// The strict schema as the object `turn/start` takes.
    fileprivate static let schema: Any = (try? JSONSerialization.jsonObject(with: Data(LiveAnswer.strictSchema.utf8))) ?? [String: Any]()

    /// `text` as a TOML basic string, for a `-c` value.
    static func toml(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// One start of Codex's responder, from the check to the stop: its server, the check's provider,
/// how far the start has got, and the turn under way. Every callback holds it weakly, so once the
/// driver drops it at `stop` nothing it began reports. The check's catalog, from `codex debug
/// models`, is still made to its end, and launches nothing.
@MainActor
private final class CodexRun {
    /// How far the start has got: the check's thread and the model it runs on, then the thread asks
    /// go to, warming up and then taking asks.
    enum Phase {
        case starting
        case checking(thread: String, model: String)
        case warming(thread: String)
        case ready(thread: String)
    }

    private let home: URL
    private let askWaiting: () -> Bool
    private let report: (ResponderEvent) -> Void
    private var session: AppServerSession?
    private var check: CodexCheckProvider?
    private var phase = Phase.starting
    /// The turn under way on the thread asks go to, from its `turn/started`.
    private var turn: String?
    /// An interrupt asked for before the turn under way had an id.
    private var interruptOnStart = false
    private var partial = ""
    private var usage = ""
    private var lastError: String?
    private let startedAt = Date()

    init(binary: String, home: URL, askWaiting: @escaping () -> Bool, report: @escaping (ResponderEvent) -> Void) throws {
        self.home = home
        self.askWaiting = askWaiting
        self.report = report
        let check = try CodexCheckProvider()
        self.check = check
        let run = WeakRun(self)
        check.start { port in
            let catalog = port == nil ? nil : CodexIsolation.writeCatalog(binary: binary, home: home)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { run.value?.launch(binary, port: port, catalog: catalog) }
            }
        }
    }

    /// The thread asks go to, once the check has passed.
    private var thread: String? {
        switch phase {
        case .warming(let thread), .ready(let thread): thread
        case .starting, .checking: nil
        }
    }

    func send(_ parts: [LiveResponder.Part]) {
        guard case .ready(let thread) = phase else { return }
        partial = ""
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
        session?.call("turn/start", ["threadId": thread, "input": input, "outputSchema": CodexDriver.schema, "effort": CodexDriver.effort]) { [weak self] answer in
            if case .failure(let error) = answer { self?.report(.turnFailed(error.message)) }
        }
    }

    func interrupt() {
        guard case .ready(let thread) = phase else { return }
        guard let turn else {
            interruptOnStart = true
            return
        }
        session?.call("turn/interrupt", ["threadId": thread, "turnId": turn]) { _ in }
    }

    func stop() {
        session?.stop()
        session = nil
        check?.stop()
        check = nil
    }

    // MARK: Starting

    /// The start failed, at whichever step: one way for all of them.
    private func fail(_ detail: String) {
        report(.startFailed(detail))
    }

    private func launch(_ binary: String, port: UInt16?, catalog file: URL?) {
        guard let port else { return fail("could not listen for the check") }
        guard let file else { return fail("could not make the model catalog from codex debug models") }
        let provider = #"{name="\#(CodexDriver.checkProvider)", base_url="http://127.0.0.1:\#(port)/v1", wire_api="responses", supports_websockets=false}"#
        let arguments = ["-c", "model_catalog_json=\(CodexDriver.toml(file.path))", "-c", "model_providers.\(CodexDriver.checkProvider)=\(provider)"]
        do {
            session = try AppServerSession(binary: binary, home: home, arguments: arguments,
                                           onNotification: { [weak self] in self?.notified($0, $1) },
                                           onEnd: { [weak self] in self?.ended($0) },
                                           ready: { [weak self] in self?.initialized($0) })
        } catch {
            return fail("launch: \(error.localizedDescription)")
        }
        Log.write("[live-ink] responder starting pid=\(session?.pid ?? 0) agent=codex")
    }

    private func initialized(_ answer: Result<Void, AppServerSession.ServerError>) {
        if case .failure(let error) = answer { return fail("initialize: \(error.message)") }
        session?.call("account/read", [:]) { [weak self] answer in
            guard let self else { return }
            guard (try? answer.get())?["account"] is [String: Any] else { return fail("not signed in: no account") }
            session?.call("model/list", [:]) { [weak self] answer in self?.listed(answer) }
        }
    }

    /// The model the account offers, then the check's thread on it.
    private func listed(_ answer: Result<[String: Any], AppServerSession.ServerError>) {
        let models = (try? answer.get())?["data"] as? [[String: Any]] ?? []
        let offered = models.compactMap { $0["model"] as? String }
        let model = offered.contains(CodexDriver.model) ? CodexDriver.model
            : models.first { $0["isDefault"] as? Bool == true }?["model"] as? String
        guard let model else {
            if case .failure(let error) = answer { return fail("model/list: \(error.message)") }
            return fail("model/list offered no model")
        }
        Log.write("[live-ink] responder codex model=\(model) offered=\(offered.count)")
        startThread(model: model, provider: CodexDriver.checkProvider) { [weak self] id in
            self?.phase = .checking(thread: id, model: model)
            self?.warmUp(on: id)
        }
    }

    private func startThread(model: String, provider: String?, then started: @escaping (String) -> Void) {
        var params: [String: Any] = ["ephemeral": true, "baseInstructions": LiveResponder.systemPrompt, "model": model,
                                     "approvalPolicy": "never", "sandbox": "read-only", "cwd": home.path]
        if let provider { params["modelProvider"] = provider }
        session?.call("thread/start", params) { [weak self] answer in
            guard let self else { return }
            guard let id = ((try? answer.get())?["thread"] as? [String: Any])?["id"] as? String else {
                if case .failure(let error) = answer { return fail("thread/start: \(error.message)") }
                return fail("thread/start answered no thread")
            }
            started(id)
        }
    }

    private func warmUp(on thread: String) {
        session?.call("turn/start", ["threadId": thread, "input": [["type": "text", "text": LiveResponder.warmUp]],
                                     "outputSchema": CodexDriver.schema, "effort": CodexDriver.effort]) { [weak self] answer in
            if case .failure(let error) = answer { self?.fail("warm-up turn/start: \(error.message)") }
        }
    }

    /// The check's turn ended: the thread asks go to starts, on the check's model, only if what Codex
    /// sent the check is Vignette's prompt, the warm-up and no tools. Its warm-up only warms the
    /// cache, so an ask waiting by then goes first instead, and a cold ask is answered sooner.
    private func checked(_ ended: [String: Any], model: String) {
        phase = .starting
        let bodies = check?.requests ?? []
        check?.stop()
        check = nil
        let status = ended["status"] as? String
        guard status == "completed" else { return fail("the check's turn \(status ?? "?"): \(Self.message(of: ended) ?? "")") }
        let refusal = bodies.isEmpty ? "no request reached the check"
            : bodies.lazy.compactMap { CodexIsolation.refusal(of: $0, prompt: LiveResponder.systemPrompt, warmUp: LiveResponder.warmUp) }.first
        if let refusal {
            Log.write("[live-ink] responder error not-isolated \(refusal) agent=codex")
            report(.refused(ResponderRefusal(failure: LiveResponder.Failure(reason: "Live ink stopped Codex, which started with tools.", detail: "not isolated"),
                                             problem: "This version of Codex starts with tools, so live ink can't use it.", retry: .onceBinaryChanges)))
            return
        }
        Log.write("[live-ink] responder codex isolated requests=\(bodies.count) ms=\(Int(Date().timeIntervalSince(startedAt) * 1000))")
        startThread(model: model, provider: nil) { [weak self] id in
            guard let self else { return }
            guard !askWaiting() else {
                phase = .ready(thread: id)
                report(.ready("ms=\(Int(Date().timeIntervalSince(startedAt) * 1000)) warm-up=skipped"))
                return
            }
            phase = .warming(thread: id)
            warmUp(on: id)
        }
    }

    private func warmedUp(_ ended: [String: Any], on thread: String) {
        turn = nil
        let status = ended["status"] as? String
        guard status == "completed" else { return fail("warm-up \(status ?? "?"): \(Self.message(of: ended) ?? lastError ?? "")") }
        phase = .ready(thread: thread)
        report(.ready("ms=\(Int(Date().timeIntervalSince(startedAt) * 1000)) turn=\(ended["durationMs"] as? Int ?? 0)"))
    }

    // MARK: Talking

    private func notified(_ method: String, _ params: [String: Any]) {
        let onThread = params["threadId"] as? String
        let onAskThread = onThread != nil && onThread == thread
        var answering = false
        if case .ready(let thread) = phase { answering = onThread == thread }
        switch method {
        case "turn/started" where onAskThread:
            turn = (params["turn"] as? [String: Any])?["id"] as? String
            if interruptOnStart {
                interruptOnStart = false
                interrupt()
            }
        case "item/agentMessage/delta" where answering:
            report(.output)
            partial += params["delta"] as? String ?? ""
            report(.answerSoFar(partial))
        case _ where answering && method.hasPrefix("item/") && method.lowercased().hasSuffix("delta"):
            report(.output)
        case "thread/tokenUsage/updated" where onAskThread:
            let last = (params["tokenUsage"] as? [String: Any])?["last"] as? [String: Any] ?? [:]
            let counts = [("input", "inputTokens"), ("read", "cachedInputTokens"), ("output", "outputTokens"), ("thinking", "reasoningOutputTokens")]
            usage = counts.map { "\($0.0)=\((last[$0.1] as? Int).map(String.init) ?? "?")" }.joined(separator: " ")
        case "error":
            lastError = AppServerSession.text(of: params["error"])
        case "turn/completed":
            guard let ended = params["turn"] as? [String: Any] else { return }
            switch phase {
            case .checking(let thread, let model) where onThread == thread: checked(ended, model: model)
            case .warming(let thread) where onThread == thread: warmedUp(ended, on: thread)
            case .ready(let thread) where onThread == thread: completed(ended)
            default: break
            }
        default:
            break
        }
    }

    private func completed(_ ended: [String: Any]) {
        turn = nil
        let status = ended["status"] as? String
        let milliseconds = ended["durationMs"] as? Int ?? 0
        switch status {
        case "completed":
            let items = ended["items"] as? [[String: Any]] ?? []
            let text = items.last { $0["type"] as? String == "agentMessage" }?["text"] as? String ?? partial
            let answer = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) ?? text
            report(.answered(answer, usage: "ms=\(milliseconds) \(usage)"))
        case "interrupted":
            report(.turnFailed("interrupted"))
        default:
            report(.turnFailed(Self.message(of: ended) ?? lastError ?? "turn \(status ?? "?")"))
        }
    }

    private func ended(_ status: Int32) {
        let tail = session?.lastErrorLine ?? ""
        session = nil
        report(.ended(status: status, tail: tail))
    }

    /// A turn's error message.
    private static func message(of turn: [String: Any]) -> String? {
        AppServerSession.text(of: turn["error"])
    }
}

/// A start, held weakly, for the check provider's queue. Read only on the main thread.
private final class WeakRun: @unchecked Sendable {
    weak var value: CodexRun?
    init(_ value: CodexRun) { self.value = value }
}
