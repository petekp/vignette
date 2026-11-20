import Foundation

/// What happened when a request was handed to a client. The four cases are different on purpose:
/// only `notSubmitted` permits an automatic retry, and only `uncertain` may already have arrived.
/// `detail` is for the log. `reason` is for the person, on the card that was sent: what went wrong
/// and what to do about it, short enough for a card.
enum SubmissionOutcome {
    /// The runtime took the request. It does not mean a model has read the image. `line` names a
    /// line an idle conversation's queue still holds, which it starts at its next look there; nil
    /// once the runtime started it, and from a runtime with no queue.
    case accepted(detail: String, line: QueuedLine? = nil)
    /// The runtime took the request and holds it in the conversation's queue: a turn is running, the
    /// last turn was stopped, or nothing has the conversation open. `reason` says when it will be
    /// read. `line` names it in the queue, so Vignette can watch it until the runtime takes it and
    /// take it back; nil when the runtime did not say which line it is.
    case queued(detail: String, reason: String, line: QueuedLine? = nil)
    /// Nothing reached the client. Retrying the same request is safe.
    case notSubmitted(code: CommandError, detail: String, reason: String)
    /// The conversation is gone, replaced, or no longer reachable where it was.
    case destinationChanged(detail: String, reason: String)
    /// The call did not answer in time. It may or may not have been accepted, so Vignette neither
    /// retries it nor claims it failed.
    case uncertain(detail: String, reason: String)

    var isAccepted: Bool {
        switch self {
        case .accepted, .queued: return true
        case .notSubmitted, .destinationChanged, .uncertain: return false
        }
    }

    var detail: String {
        switch self {
        case .accepted(let d, _), .queued(let d, _, _), .destinationChanged(let d, _), .uncertain(let d, _): return d
        case .notSubmitted(_, let d, _): return d
        }
    }

    var reason: String? {
        switch self {
        case .accepted: return nil
        case .queued(_, let r, _), .notSubmitted(_, _, let r), .destinationChanged(_, let r), .uncertain(_, let r): return r
        }
    }

    /// The line the runtime's queue still holds, which Vignette watches until the runtime takes it.
    var queuedLine: QueuedLine? {
        switch self {
        case .accepted(_, let line), .queued(_, _, let line): return line
        default: return nil
        }
    }

    static let internalReason = "Something went wrong in Vignette. The log has details."

    /// A request Vignette could not store: nothing was sent, and the system says why.
    static func notSaved(_ error: Error) -> String { "Vignette couldn't save the request. \(error.localizedDescription)" }

    /// A client's own words, cut to fit a card, for a failure Vignette has no sentence of its own for.
    static func quoted(_ client: String, _ detail: String) -> String {
        let words = detail.count > 70 ? String(detail.prefix(69)) + "…" : detail
        return "\(client): \(words)"
    }
}
