import Foundation

/// Why a responder cannot answer, in words of the driver's own: its command was not found, or its
/// isolation check refused the process.
struct ResponderRefusal: Equatable {
    /// What an ask waiting on the start is told.
    let failure: LiveResponder.Failure
    /// Why the responder cannot answer, for the note and the settings.
    let problem: String
    /// When an ask may start the agent again.
    var retry = Retry.always

    enum Retry: Equatable {
        case always
        /// Once the file at the command's path is another (`BinaryStamp`): the isolation check's
        /// answer holds for one file, for as long as Vignette runs.
        case onceBinaryChanges
    }
}

extension ResponderRefusal {
    /// A refusal that says the same to the ask and in the settings.
    init(reason: String, detail: String) {
        self.init(failure: LiveResponder.Failure(reason: reason, detail: detail), problem: reason)
    }
}

/// A command's file as it is now: the path it was found at, and the size and modification date of
/// the file that path leads to.
struct BinaryStamp: Equatable {
    let path: String
    let size: Int
    let modified: Date

    /// It reads the disk, so it runs off the main thread.
    init?(path: String) {
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file),
              let size = attributes[.size] as? Int, let modified = attributes[.modificationDate] as? Date else { return nil }
        self.path = path
        self.size = size
        self.modified = modified
    }
}

/// What a driver's process said, in the responder's terms.
enum ResponderEvent {
    /// The warm-up answered and the process has nothing but the answer to give. The detail is for
    /// the log.
    case ready(String)
    /// The start failed before it was ready, with the detail for the log.
    case startFailed(String)
    case refused(ResponderRefusal)
    /// The turn's first output.
    case output
    /// The answer's JSON so far.
    case answerSoFar(String)
    /// The turn's answer, and its time, cost and tokens for the log.
    case answered(Any, usage: String)
    /// The turn ended without an answer, interrupted or failed, with the detail.
    case turnFailed(String)
    /// The process ended on its own, with the last of its standard error.
    case ended(status: Int32, tail: String)
}

/// One agent client's side of the responder: the process it runs, and what it writes and reads.
@MainActor
protocol ResponderDriver: AnyObject {
    var client: AgentClient { get }
    /// The agent's name in what the person reads.
    var name: String { get }
    /// Finds the agent's command. It reads the disk, so it is called off the main thread.
    var binary: @Sendable () -> String? { get }
    /// What an ask is told when the command is not found.
    var notFound: ResponderRefusal { get }
    /// What the person reads when the process could not start, and when a turn could not answer,
    /// unless the error names a cause `reason(forError:)` knows.
    var couldNotStart: String { get }
    var couldNotAnswer: String { get }
    /// Starts `binary` and its warm-up, and reports what it says through `report` from then on.
    /// Answers why it could not start, for the log. `askWaiting` says whether an ask is waiting for
    /// the start to end, which a warm-up that only warms the cache can give way to.
    func start(binary: String, askWaiting: @escaping () -> Bool, report: @escaping (ResponderEvent) -> Void) -> String?
    /// Writes one ask's message.
    func send(_ parts: [LiveResponder.Part])
    /// Ends the turn under way. Its end is still reported.
    func interrupt()
    /// Ends the process. Nothing is reported after it.
    func stop()
    /// Words for the person when the agent's error text names a cause they can act on, else nil.
    /// The text is not an interface: a match only picks a clearer sentence.
    func reason(forError text: String) -> String?
    /// Whether the agent can answer, as its own tools report it, without sending a message. It reads
    /// the disk and may run the agent's command, so it runs off the main thread.
    nonisolated static func availability() -> LiveResponder.Availability
    /// For the person: why the agent cannot answer, or nil when it can.
    nonisolated static func problem(_ availability: LiveResponder.Availability) -> String?
    /// Whether a note offers the agent even when it is not installed, to say so.
    static var alwaysOffered: Bool { get }
}
