import Foundation

/// What happened when a request was handed to a client. The four cases are different on purpose:
/// only `notSubmitted` permits an automatic retry, and only `uncertain` may already have arrived.
/// `detail` is for the log. `reason` is for the person, on the card that was sent: what went wrong
/// and what to do about it, short enough for a card.
enum SubmissionOutcome {
    /// The runtime took the request. It does not mean a model has read the image.
    case accepted(detail: String)
    /// The runtime took the request and holds it, but nothing has the conversation open, so nothing
    /// reads it until someone opens it. It arrives then, first.
    case queued(detail: String, reason: String)
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
        case .accepted(let d), .queued(let d, _), .destinationChanged(let d, _), .uncertain(let d, _): return d
        case .notSubmitted(_, let d, _): return d
        }
    }

    var reason: String? {
        switch self {
        case .accepted: return nil
        case .queued(_, let r), .notSubmitted(_, _, let r), .destinationChanged(_, let r), .uncertain(_, let r): return r
        }
    }

    static let internalReason = "Something went wrong in Vignette. The log has details."

    /// A client's own words, cut to fit a card, for a failure Vignette has no sentence of its own for.
    static func quoted(_ client: String, _ detail: String) -> String {
        let words = detail.count > 70 ? String(detail.prefix(69)) + "…" : detail
        return "\(client): \(words)"
    }
}
