import Foundation

/// Why a driver could not start, or its warm-up refused the process.
struct ResponderRefusal: Equatable {
    /// What an ask waiting on the start is told.
    let failure: LiveResponder.Failure
    /// Why the responder cannot answer, for the note and the settings.
    let problem: String
}

extension ResponderRefusal {
    /// A refusal that says the same to the ask and in the settings.
    init(reason: String, detail: String) {
        self.init(failure: LiveResponder.Failure(reason: reason, detail: detail), problem: reason)
    }
}

/// What a driver's process said, in the responder's terms.
enum ResponderEvent {
    /// The warm-up answered and the process has nothing but the answer to give. The detail is for
    /// the log.
    case ready(String)
    case refused(ResponderRefusal)
    /// The turn's first output.
    case output
    /// The answer's JSON so far.
    case answerSoFar(String)
    /// The turn's answer, and its time, cost and tokens for the log.
    case answered(Any, usage: String)
    case turnFailed(String)
    /// The turn ended without an answer because it was interrupted.
    case interrupted(String)
    /// The process ended on its own, with the last of its standard error.
    case ended(status: Int32, tail: String)
}

/// One agent client's side of the responder: the process it runs, and what it writes and reads.
@MainActor
protocol ResponderDriver: AnyObject {
    var client: AgentClient { get }
    /// The agent's name in what the person reads.
    var name: String { get }
    /// Starts the process and its warm-up, and reports what it says through `report` from then on.
    /// Answers why it could not start. `askWaiting` says whether an ask is waiting for the start to
    /// end, which a warm-up that only warms the cache can give way to.
    func start(askWaiting: @escaping () -> Bool, report: @escaping (ResponderEvent) -> Void) -> ResponderRefusal?
    /// Writes one ask's message.
    func send(_ parts: [LiveResponder.Part])
    /// Ends the turn under way. Its end is still reported.
    func interrupt()
    /// Ends the process. Nothing is reported after it.
    func stop()
    /// Words for the person from the agent's error text, which is not an interface: a match only picks
    /// a clearer sentence, and anything else gets a general one.
    func reason(forError text: String) -> String
}
