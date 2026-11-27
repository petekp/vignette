import Foundation

/// A line Vignette put in a Codex thread's queue, by the id `codex queue` printed for it. The queue
/// holds it until an engine that has the thread open starts it as a turn, which it does only once
/// the thread is idle and its last turn ended normally. After a stopped turn the line waits for the
/// person's next message there, with no time limit (docs/codex-queued-sends-2026-11-16.md).
struct QueuedLine: Equatable, Sendable, Codable {
    let id: String
    let thread: String

    /// The line in `codex queue`'s answer, `Queued message <id> for thread <thread>.`; nil when the
    /// answer has another form or names another thread.
    static func of(output: String, thread: String) -> QueuedLine? {
        let pattern = #"Queued message (\S+) for thread (\S+?)\.?(?:\s|$)"#
        guard let match = output.range(of: pattern, options: .regularExpression) else { return nil }
        let words = output[match].split(whereSeparator: \.isWhitespace)
        guard words.count >= 6 else { return nil }
        let named = words[5].hasSuffix(".") ? String(words[5].dropLast()) : String(words[5])
        guard named.lowercased() == thread.lowercased() else { return nil }
        return QueuedLine(id: String(words[2]), thread: thread)
    }

    /// Why Codex still holds the line, as far as Vignette can see from outside the engine: the
    /// thread's rollout and whether an engine has the thread open. A dialog other than a question
    /// leaves no mark in the rollout, so a command approval reads as a running turn.
    enum Hold: Equatable {
        case turnRunning
        /// The running turn waits on a question it asked the person.
        case question
        /// The thread's last turn was stopped. Codex starts nothing until the person's next message.
        case stopped
        /// No engine has the thread open. The line runs first once someone opens it.
        case notOpen
        /// The thread is archived. Its queue keeps the line, and Codex refuses to list or remove it
        /// until the thread is unarchived (0.169, measured 2026-11-16).
        case archived
        /// An engine has the thread open, and its last turn ended normally. It takes the line at its
        /// next look at the queue, within 10 s.
        case nothing

        static func of(_ end: RolloutEnd, loaded: Bool) -> Hold {
            if end == .stopped { return .stopped }
            guard loaded else { return .notOpen }
            switch end {
            case .running: return .turnRunning
            case .asking: return .question
            case .stopped: return .stopped
            // A thread with no turn yet, or a turn that wrote more than the tail since it started,
            // which the measured rollouts never came near.
            case .ended, .unknown: return .nothing
            }
        }

        /// What the card says under "Queued for *session*" (docs/voice.md).
        var reason: String {
            switch self {
            case .turnRunning: return "Codex reads it when its current turn ends."
            case .question: return "Codex is waiting for your answer, then reads this."
            case .stopped: return "Codex stopped its last turn. You can resume it in Codex."
            case .notOpen: return "Codex reads it when you open this thread."
            case .archived: return "This thread is archived. Codex reads it once you unarchive it."
            case .nothing: return "Codex hasn't picked it up yet. You can check the thread in Codex."
            }
        }

        var forLog: String {
            switch self {
            case .turnRunning: return "turn-running"
            case .question: return "question"
            case .stopped: return "stopped"
            case .notOpen: return "not-open"
            case .archived: return "archived"
            case .nothing: return "nothing-seen"
            }
        }
    }

    /// Where the line is at one look.
    enum State: Equatable {
        case held(Hold)
        /// The queue no longer has it and the thread's history does: an engine started it.
        case taken
        /// The queue no longer has it and the thread's history does not: someone removed it in Codex,
        /// whose app lists a thread's queued lines with Edit and Delete.
        case removed
        /// Codex can't find the thread, so the line will never run.
        case threadGone(detail: String)
        /// The queue could not be read this time.
        case unread(detail: String)
    }

    /// What taking the line back came to.
    enum Withdrawal: Equatable {
        case removed
        /// The queue no longer had it: Codex had started it.
        case alreadyTaken
        case failed(detail: String)

        /// What the card says under "Sent to *session*" (docs/voice.md).
        static let alreadyTakenReason = "Codex had already started on it."
        /// What the card says under "Queued for *session*" (docs/voice.md).
        static let refusedReason = "Vignette couldn't remove it. You can delete it in Codex."
    }
}

/// How a Codex thread's last turn stands, read from the end of its rollout. The engine writes
/// `event_msg` `task_started`, then `task_complete` or `turn_aborted`, each with the `turn_id`; a
/// question the agent asks is a `function_call` named `request_user_input`, answered by a
/// `function_call_output` with the same `call_id` (0.169, read in the investigation's live runs).
enum RolloutEnd: Equatable {
    /// A turn started and has not ended.
    case running
    /// The running turn's question has no answer yet.
    case asking
    /// The last turn was stopped: `turn_aborted`.
    case stopped
    /// The last turn ended normally: `task_complete`.
    case ended
    /// The tail held no turn's start or end, as in a thread with no turn yet.
    case unknown

    /// How much of a rollout's end is read. One line can run to tens of KB, and a turn's end is the
    /// last thing it writes, so its end is near the file's end.
    static let tailBytes: UInt64 = 512 * 1024

    /// The last turn in `tail`, the end of a rollout. A first line cut in the middle is skipped. A
    /// turn of a sub-agent, whose `root_turn_id` names another turn, is not the thread's own.
    static func of(tail: Data) -> RolloutEnd {
        var end = RolloutEnd.unknown
        var questions: Set<String> = []
        for line in tail.split(separator: UInt8(ascii: "\n")) {
            guard let entry = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let payload = entry["payload"] as? [String: Any], let kind = payload["type"] as? String else { continue }
            switch (entry["type"] as? String, kind) {
            case ("event_msg", "task_started"):
                guard isOwn(payload) else { continue }
                end = .running
                questions = []
            case ("event_msg", "task_complete"):
                guard isOwn(payload) else { continue }
                end = .ended
                questions = []
            case ("event_msg", "turn_aborted"):
                guard isOwn(payload) else { continue }
                end = .stopped
                questions = []
            case ("response_item", "function_call") where payload["name"] as? String == "request_user_input":
                if let call = payload["call_id"] as? String { questions.insert(call) }
            case ("response_item", "function_call_output"):
                if let call = payload["call_id"] as? String { questions.remove(call) }
            default:
                continue
            }
        }
        if end == .running && !questions.isEmpty { return .asking }
        return end
    }

    /// The end of a rollout file, nil when it cannot be read. A compressed rollout (`.zst`) is one
    /// the engine is done with.
    static func of(file path: String) -> RolloutEnd? {
        guard !path.hasSuffix(".zst"), let tail = ClaudeCodeConnection.tail(of: URL(fileURLWithPath: path), bytes: tailBytes) else { return nil }
        return of(tail: tail)
    }

    private static func isOwn(_ payload: [String: Any]) -> Bool {
        let turn = payload["turn_id"] as? String
        let root = payload["root_turn_id"] as? String ?? (payload["turn_attribution"] as? [String: Any])?["root_turn_id"] as? String
        guard let turn, let root else { return true }
        return turn == root
    }
}

/// One queued line's watch, from the send's answer until Codex takes the line. Pure:
/// `ScreenshotRequests` runs the looks and the timer.
struct QueueWatch: Equatable {
    let line: QueuedLine
    /// When the line went into the queue, in the clock the looks run on.
    let queued: TimeInterval
    /// The reason the card shows under "Queued for", nil while it says Sent.
    private(set) var shown: String?
    /// Since when the looks have seen nothing holding the line.
    private var nothingSince: TimeInterval?
    /// The `unread` detail already logged, so a queue that keeps refusing logs once.
    private var loggedUnread: String?
    /// True while Don't send is taking the line out, when a look's answer is stale.
    var withdrawing = false

    /// How long nothing may be seen holding a line before the card says Codex hasn't picked it up:
    /// an engine looks at the queue every 10 s.
    static let pickUpWithin: TimeInterval = 15

    /// `shown` is the reason the send's answer put on the card, nil for an answer that said Sent.
    init(line: QueuedLine, queued: TimeInterval, shown: String?) {
        self.line = line
        self.queued = queued
        self.shown = shown
        nothingSince = queued
    }

    /// What a look comes to.
    enum Effect: Equatable {
        /// The card says Queued with this reason now.
        case show(QueuedLine.Hold)
        /// Nothing new to say; look again.
        case wait
        /// The unread detail is new: log it, then look again.
        case logUnread(String)
        /// Codex took the line. `wasShown`: the card says Queued and is to say Sent.
        case taken(wasShown: Bool)
        case removed
        case threadGone(detail: String)
    }

    mutating func look(_ state: QueuedLine.State, at now: TimeInterval) -> Effect {
        switch state {
        case .taken: return .taken(wasShown: shown != nil)
        case .removed: return .removed
        case .threadGone(let detail): return .threadGone(detail: detail)
        case .unread(let detail):
            guard loggedUnread != detail else { return .wait }
            loggedUnread = detail
            return .logUnread(detail)
        case .held(let hold):
            loggedUnread = nil
            // A turn that just ended leaves the line for the engine's next look at the queue.
            // Saying so before that look would put a reason on the card and take it off seconds later.
            if hold == .nothing {
                let since = nothingSince ?? now
                nothingSince = since
                guard now - since >= Self.pickUpWithin else { return .wait }
            } else {
                nothingSince = nil
            }
            guard hold.reason != shown else { return .wait }
            shown = hold.reason
            return .show(hold)
        }
    }

    /// How long until the next look: every 3 s in the first minute, every 10 s to five minutes, every
    /// 30 s to half an hour, then every minute. A look runs an app-server, and a line behind a
    /// stopped turn can wait for hours.
    func nextLook(at now: TimeInterval) -> TimeInterval {
        let waited = now - queued
        if waited < 60 { return 3 }
        if waited < 5 * 60 { return 10 }
        if waited < 30 * 60 { return 30 }
        return 60
    }
}
