import Foundation

/// The agent that answers live ink: one process Vignette keeps running for a conversation, on the
/// person's own sign-in, with none of their customisations and no tools
/// (docs/live-ink-integration-2026-10-04.md, "The responder"). A `ResponderDriver` runs one agent
/// client's process: `ClaudeDriver` runs `claude -p`, and `CodexDriver` runs Codex's app-server.
/// This is the rest, the same for both: one ask at a time, the time limits, the idle stop and the
/// conversation's length.
///
/// It starts on the first inking, since an idle process costs memory, and stops `idleLimit` after
/// its last request. Starting runs the driver's warm-up, which checks that the process has no tools
/// before any screen content is sent, and warms the agent's cache for the first real ask.
@MainActor
final class LiveResponder {
    enum State: Equatable {
        case stopped
        case starting
        case ready
        case asking
        /// Why it cannot answer, in words a person reads under the switch and on the ink.
        case failed(String)

        var name: String {
            switch self {
            case .stopped: "stopped"
            case .starting: "starting"
            case .ready: "ready"
            case .asking: "asking"
            case .failed: "failed"
            }
        }
    }

    /// One part of an ask's message, which the driver writes in its agent's form.
    enum Part: Equatable {
        /// A PNG.
        case picture(Data)
        case text(String)
    }

    /// One ask: the message's parts, made when it is sent for the conversation it goes to, and where
    /// its answer goes. `onSay` gets the reply so far while it streams; `onAnswer` gets the whole
    /// answer or why there is none, once.
    struct Ask {
        let content: (_ conversation: Int) -> [Part]
        let onSay: (String) -> Void
        let onAnswer: (Result<LiveAnswer, Failure>) -> Void
    }

    struct Failure: Error, Equatable, CustomStringConvertible {
        /// For the person: what went wrong and, where there is one, what to do.
        let reason: String
        /// For the log.
        let detail: String
        var description: String { "\(reason) (\(detail))" }
    }

    private(set) var state: State = .stopped {
        didSet { if state != oldValue { onState?(state) } }
    }
    var onState: ((State) -> Void)?
    /// Counts the conversations started, so a caller can tell whether the conversation it sent a
    /// picture in is still the one answering.
    private(set) var conversation = 0
    /// Asks answered in this conversation, the warm-up left out.
    private(set) var answered = 0

    /// How long an ask may take before the process is stopped and the ask fails.
    static let askLimit: TimeInterval = 45
    /// How long an interrupted turn may take to end before the process is stopped.
    static let interruptLimit: TimeInterval = 3
    /// How long the process is kept after its last request. Claude's prompt cache lasts 5 minutes
    /// from each request (`ClaudeDriver.promptCacheTTL`), and an ask after that would write the whole
    /// conversation into it again, so a new process starts instead. Half a minute short of it, so an
    /// ask that begins just before the stop still reaches the cache in time.
    static let idleLimit: TimeInterval = 4.5 * 60
    /// A conversation grows by up to about 7,000 tokens a screen, for two pictures and a terminal's
    /// text (docs/live-ink-ask-cost-2026-10-06.md); past this many asks the next one starts a new
    /// process.
    static let conversationLimit = 12

    let driver: any ResponderDriver
    var client: AgentClient { driver.client }
    /// The driver's process runs, or its command is being found, from its start until it stops or ends.
    private var running: Bool {
        switch state {
        case .starting, .ready, .asking: true
        case .stopped, .failed: false
        }
    }
    /// Counts the starts, so a command found after a stop starts nothing. A driver reports nothing
    /// after its own stop.
    private var starts = 0
    /// The command file the last start ran.
    private var started: BinaryStamp?
    /// The command file the isolation check refused, and the refusal, for as long as Vignette runs. A
    /// start of that same file answers with the refusal and runs nothing.
    private var held: (file: BinaryStamp, refusal: ResponderRefusal)?
    private var current: Ask?
    /// The turn of an ask the person cancelled was interrupted, and its end has not come. Nothing is
    /// sent until it does, and what it says is not an answer.
    private var interrupting = false
    /// The ask sent while the process could not take it: during the warm-up, or until an interrupted
    /// turn ends. `LiveAsks` sends one ask at a time, so there is at most one.
    private var pending: Ask?
    /// Why the process must start again once the start or turn under way ends (`restart(whenIdle:)`).
    private var restartDue: String?
    private var lastSay: String?
    private var askTimer: Timer?
    private var idleTimer: Timer?
    /// When the ask under way was sent, and when its first output and its reply's first word came,
    /// for the log: the first output ends the reading of the prompt and the screen.
    private var sentAt = Date()
    private var firstToken: Date?
    private var firstWord: Date?

    init(driver: any ResponderDriver) {
        self.driver = driver
    }

    /// Starts the process ahead of an ask. After a failure only an ask starts it again.
    func prepare() {
        restartIfIdle()
        guard !running else { return }
        if case .failed = state { return }
        start()
    }

    /// Asks once the process is ready, one ask at a time: the next comes once this one has answered,
    /// failed or been cancelled. After a failure it starts the process again, and a start that fails
    /// again answers the ask with why.
    func ask(_ ask: Ask) {
        if answered >= Self.conversationLimit, current == nil, pending == nil {
            Log.write("[live-ink] responder: \(answered) asks; starting a new conversation agent=\(client.rawValue)")
            stop()
        }
        pending = ask
        if case .failed = state { state = .stopped }
        prepare()
        sendNext()
    }

    /// Starts a new conversation, for a change the running process cannot see, such as a sign-in:
    /// now, or once the start or turn under way ends. An ask waiting then goes to the new process. A
    /// failure no longer holds, so the agent is offered again.
    func restart(whenIdle reason: String) {
        restartDue = reason
        restartIfIdle()
    }

    private func restartIfIdle() {
        guard let reason = restartDue, current == nil, !interrupting, state != .starting else { return }
        restartDue = nil
        Log.write("[live-ink] responder restarting: \(reason) agent=\(client.rawValue)")
        let next = pending
        shutDown(nil, state: .stopped)
        if let next { ask(next) }
    }

    /// Stops the process, which ends the conversation; the next ask starts a new one. An ask under
    /// way or pending gets no answer and no failure. A failure stays until the next ask.
    func stop() {
        if case .failed = state { return shutDown(nil, state: state) }
        shutDown(nil, state: .stopped)
    }

    /// The person stopped the ask under way or pending: it gets no answer and no failure. A turn
    /// already sent is interrupted, which ends it and keeps the conversation, so the next ask is sent
    /// when the interrupted turn ends. A pending ask was never sent, and the warm-up, which is not an
    /// ask, runs on.
    func cancel() {
        pending = nil
        guard current != nil else { return }
        current = nil
        interrupting = true
        driver.interrupt()
        armTimer()
        Log.write("[live-ink] responder interrupted the turn agent=\(client.rawValue)")
    }

    var stateJSON: [String: Any] {
        var json: [String: Any] = ["state": state.name, "conversation": conversation, "answered": answered, "waiting": pending == nil ? 0 : 1,
                                   "agent": client.rawValue]
        if case .failed(let reason) = state { json["reason"] = reason }
        return json
    }

    // MARK: The process

    /// Finds the driver's command off the main thread, then starts it on the main thread.
    private func start() {
        starts += 1
        let start = starts
        state = .starting
        renewIdle()
        armTimer()
        let find = driver.binary
        Task { [weak self] in
            // A dispatch queue, not a detached task: the lookup can wait for the login shell, and a
            // wait on one of Swift's few cooperative threads stalls every task queued behind it.
            let found: (binary: String, file: BinaryStamp?)? = await withCheckedContinuation { found in
                DispatchQueue.global(qos: .userInitiated).async { found.resume(returning: find().map { ($0, BinaryStamp(path: $0)) }) }
            }
            guard let self, start == starts, running else { return }
            launch(found)
        }
    }

    private func launch(_ found: (binary: String, file: BinaryStamp?)?) {
        guard let found else {
            Log.write("[live-ink] responder error no-\(client.rawValue)")
            return refuse(driver.notFound)
        }
        if let held, held.file == found.file {
            Log.write("[live-ink] responder \(client.rawValue) not started: the isolation check refused this \(client.rawValue) path=\(found.binary)")
            return refuse(held.refusal)
        }
        started = found.file
        if let detail = driver.start(binary: found.binary, askWaiting: { [weak self] in self?.pending != nil },
                                     report: { [weak self] in self?.handle($0) }) {
            return startFailed(detail)
        }
        conversation += 1
        answered = 0
        Log.write("[live-ink] responder conversation=\(conversation) agent=\(client.rawValue)")
    }

    private func refuse(_ refusal: ResponderRefusal) {
        shutDown(refusal.failure, state: .failed(refusal.problem))
    }

    /// The start failed: the cause its detail names, else that the agent could not start.
    private func startFailed(_ detail: String) {
        Log.write("[live-ink] responder error start \(detail) agent=\(client.rawValue)")
        let reason = driver.reason(forError: detail) ?? driver.couldNotStart
        shutDown(Failure(reason: reason, detail: detail), state: .failed(reason))
    }

    private func sendNext() {
        guard state == .ready, current == nil, let next = pending else { return }
        pending = nil
        current = next
        lastSay = nil
        state = .asking
        sentAt = Date()
        firstToken = nil
        firstWord = nil
        renewIdle()
        driver.send(next.content(conversation))
        armTimer()
    }

    /// Each write is a request, which renews the prompt cache, so the idle limit runs from it.
    private func renewIdle() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleLimit, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.current == nil, self.pending == nil, self.running else { return }
                Log.write("[live-ink] responder idle; stopping it agent=\(self.client.rawValue)")
                self.stop()
            }
        }
    }

    /// Times the turn under way: the warm-up, an ask, or an interrupt waiting for its turn to end.
    private func armTimer() {
        let limit = interrupting ? Self.interruptLimit : Self.askLimit
        askTimer?.invalidate()
        askTimer = Timer.scheduledTimer(withTimeInterval: limit, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.interrupting { return self.interruptUnanswered() }
                Log.write("[live-ink] responder error timeout after \(Int(limit))s agent=\(self.client.rawValue)")
                self.shutDown(Failure(reason: "\(self.driver.name) took too long to answer. You can ask again.", detail: "timeout"), state: .stopped)
            }
        }
    }

    /// The interrupted turn never ended: the process stops, and the ask made since starts a new one.
    private func interruptUnanswered() {
        Log.write("[live-ink] responder error interrupt unanswered after \(Int(Self.interruptLimit))s agent=\(client.rawValue)")
        let next = pending
        stop()
        if let next { ask(next) }
    }

    private func handle(_ event: ResponderEvent) {
        switch event {
        case .ready(let detail):
            guard state == .starting else { return }
            askTimer?.invalidate()
            Log.write("[live-ink] responder ready \(detail) agent=\(client.rawValue)")
            state = .ready
            restartIfIdle()
            sendNext()
        case .startFailed(let detail):
            startFailed(detail)
        case .refused(let refusal):
            if refusal.retry == .onceBinaryChanges, let started { held = (started, refusal) }
            refuse(refusal)
        case .output:
            if current != nil, firstToken == nil { firstToken = Date() }
        case .answerSoFar(let json):
            guard let current, !interrupting, let say = LiveAnswer.partialSay(in: json), say != lastSay else { return }
            if firstWord == nil { firstWord = Date() }
            lastSay = say
            current.onSay(say)
        case .answered(let output, let usage):
            turnEnded { ask in
                do {
                    let answer = try LiveAnswer(responder: output)
                    answered += 1
                    // A mark that points at nothing, such as a box in pixels rather than thousandths, is
                    // thrown out as the answer is read, before `drew answer` could count it.
                    let given = min(((output as? [String: Any])?["marks"] as? [Any])?.count ?? 0, LiveAnswer.maxMarks)
                    Log.write("[live-ink] answered \(usage) firstToken=\(Self.since(sentAt, firstToken)) firstWord=\(Self.since(sentAt, firstWord)) marks=\(answer.marks.count) thrownOut=\(given - answer.marks.count) agent=\(client.rawValue)")
                    ask.onAnswer(.success(answer))
                } catch {
                    Log.write("[live-ink] responder error invalid-answer \(error) agent=\(client.rawValue)")
                    ask.onAnswer(.failure(Failure(reason: "Vignette couldn't draw \(driver.name)'s answer. You can ask again.", detail: "\(error)")))
                }
            }
        case .turnFailed(let detail):
            turnEnded { ask in failAnswer(of: ask, detail) }
        case .firstTurnFailed(let detail):
            askTimer?.invalidate()
            if let ask = current {
                current = nil
                failAnswer(of: ask, detail)
            }
            startFailed(detail)
        case .ended(let status, let tail):
            Log.write("[live-ink] responder ended status=\(status)\(tail.isEmpty ? "" : " stderr=\(tail)") agent=\(client.rawValue)")
            let reason = driver.reason(forError: tail) ?? (state == .starting ? driver.couldNotStart : driver.couldNotAnswer)
            shutDown(Failure(reason: reason, detail: "ended \(status)"), state: .failed(reason))
        }
    }

    private func failAnswer(of ask: Ask, _ detail: String) {
        Log.write("[live-ink] responder error answer \(detail) agent=\(client.rawValue)")
        ask.onAnswer(.failure(Failure(reason: driver.reason(forError: detail) ?? driver.couldNotAnswer, detail: detail)))
    }

    /// A turn ended. The turn of an ask the person cancelled says nothing; otherwise `answer` answers
    /// the ask under way. Then the next ask goes.
    private func turnEnded(_ answer: (Ask) -> Void) {
        askTimer?.invalidate()
        if interrupting {
            interrupting = false
            Log.write("[live-ink] responder turn interrupted ms=\(Self.since(sentAt, Date())) agent=\(client.rawValue)")
            state = .ready
        } else {
            guard let ask = current else { return }
            current = nil
            state = .ready
            answer(ask)
        }
        restartIfIdle()
        sendNext()
    }

    /// Milliseconds from `start` to `moment`, for the log.
    private static func since(_ start: Date, _ moment: Date?) -> String {
        moment.map { String(Int($0.timeIntervalSince(start) * 1000)) } ?? "none"
    }

    /// Stops the process, if it runs, and fails the ask under way or pending with `failure`, or with
    /// none drops it.
    private func shutDown(_ failure: Failure?, state final: State) {
        idleTimer?.invalidate()
        askTimer?.invalidate()
        if running { driver.stop() }
        interrupting = false
        let dropped = [current, pending].compactMap { $0 }
        current = nil
        pending = nil
        state = final
        guard let failure else { return }
        for ask in dropped { ask.onAnswer(.failure(failure)) }
    }
}
