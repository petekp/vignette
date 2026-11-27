import Foundation

/// The records `ScreenshotRequests` keeps on disk for each request and each reply.
extension ScreenshotRequests {
    /// One screenshot request: where it went, and how far it got. `address` is the whole identity
    /// of the destination, so Reply goes back to the same conversation and never to a guessed one.
    struct Record: Codable {
        let id: String
        let created: Date
        let destinationID: String
        let destinationName: String
        let address: AgentAddress
        let addressGuard: AddressGuard
        /// The screenshot the drawing was made on, for the log and the picker. Not a path: the
        /// original stays the person's and may be moved or deleted without touching this request.
        let source: String
        /// The source's path as the watch folder spelled it when the request was made. A record from
        /// before this field has only `source`, which a current folder completes.
        var sourceKey: String? = nil
        var status: Status
        /// Why the client did not take the request, for a listing after a restart. Empty when it
        /// did: an accepted submission says only what the address already says.
        var detail: String
        /// When the request's line was handed to the client. Nil while it has not been, and for a
        /// request cancelled in its grace period, which a clear also ends as `cleared`.
        var handedOver: Date? = nil
        /// How the session is started before the line goes in, when it was not running at Send.
        var start: SessionStart? = nil
        /// True when the person answered the agent's own image with words alone, so the line named
        /// that image and sent no picture (`ScreenshotRequests.Picture.unchanged`).
        var unchanged: Bool? = nil
        /// What the card called the session at Send (`SessionMenu.cardTitle`). Nil in a record from
        /// before this field.
        var cardTitle: String? = nil
        /// The person's message, as the line carried it. Nil for a send without one, and in a record
        /// from before this field. The log never holds it.
        var message: String? = nil

        enum Status: String, Codable {
            /// Stored and not yet handed to the client: in its grace, or about to be.
            case prepared
            /// The client took it. Not proof that a model has read the image.
            case submitted
            /// The call did not answer. It may have arrived, so it is never resubmitted.
            case uncertain
            case failed
            /// The person cleared it: no new reply is accepted, unpublished imports are cancelled.
            case cleared
        }

        /// Whether a reply may still be accepted for this request.
        var takesReplies: Bool { status != .cleared }

        /// This request as the send its screenshot records once it reaches the client.
        var sent: Agent.Sent {
            Agent.Sent(client: address.client, id: address.id, title: cardTitle ?? destinationName, at: Date())
        }
    }

    /// The screenshot a request was sent from. A record from before `sourceKey` keeps only its
    /// name, and a send is made from the watch folder.
    func sourceKey(of record: Record) -> ScreenshotKey {
        record.sourceKey.map { ScreenshotKey(asGiven: $0) } ?? ScreenshotKey(folder: callbacks.watchFolder(), name: record.source)
    }

    /// One reply to one request, and where its import has reached.
    struct Reply: Codable {
        let id: String
        let requestID: String
        let digest: String
        /// True when the reply supplied its own PNG; false means it draws on the request's image.
        let hasImage: Bool
        let marks: [AgentMark]
        /// An answer to live ink, which comes without marks or an image (`ReplyProtocol.Bundle`).
        var answer: LiveAnswer? = nil
        /// What the agent says the reply shows, recorded on the published file (`Agent.record(title:on:)`).
        var title: AgentTitle? = nil
        /// The agent's answers on the person's pins, which the card's pins hold. Nil for none.
        var comments: [ReplyProtocol.Comment]? = nil
        /// When Vignette accepted the reply: the time its answers were written, so a rebuilt card says
        /// the same. Nil in a record from before replies carried answers.
        var accepted: Date? = nil
        var stage: Stage
        var destination: URL?
        /// Where the person renamed the published file to, inside the watch folder. Nil while it
        /// keeps its reserved name. Only a published reply has one, and a published file is never
        /// deleted, so this is never a place cleanup removes a file from.
        var renamedTo: URL?
        var needsOutputCleanup: Bool?
        /// The person deleted the published file. Publication still happened and is not undone.
        var deleted = false
        var errorCode: String?
        /// For an answer, once it is drawn: the indexes of its marks that were not.
        var notDrawn: [Int]?

        enum Stage: String, Codable {
            /// Vignette owns every byte. The helper may release its bundle.
            case accepted
            /// The watch-folder name is reserved and excluded from everything.
            case reserved
            /// The card exists and is ordinary. The one publication point.
            case published
            /// An answer live ink made a result card of itself, from a fresh capture of its window.
            /// That card is an ordinary file, so the reply has no file of its own.
            case shown
            /// The import stopped; the payload is kept and the name stays excluded.
            case failed
            /// The request was cleared before this reply was published.
            case cancelled
        }

        /// What a card of this reply draws on `canvas`: its marks, or, for an answer whose window could
        /// not be captured, the answer's words beside its first mark and a ring round each mark's box.
        /// A mark that names only words is left out, since nothing finds words in the request's picture.
        func cardMarks(on canvas: LiveAnswer.Canvas?) -> [AgentMark] {
            guard let answer else { return marks }
            return answer.cardMarks(targets: answer.marks.map(\.box), on: canvas)
        }

        /// The answer's marks a card leaves out: those that name only words.
        var undrawnOnCard: [Int] {
            guard let answer else { return [] }
            return answer.marks.indices.filter { answer.marks[$0].box == nil }
        }

        /// The reserved watch-folder name. Derived, so a record and its file cannot drift apart.
        var fileName: String { ReplyProtocol.replyFileName(id) }

        var outputURL: URL? {
            guard let destination, destination.isFileURL, destination.path.hasPrefix("/"),
                  destination.lastPathComponent == fileName else { return nil }
            return destination.standardizedFileURL
        }

        /// The person has the reply: a card, or live ink's own result card. Clearing leaves it be.
        var isPresented: Bool { stage == .published || stage == .shown }

        /// Where the published file is now.
        var publishedURL: URL? { renamedTo?.standardizedFileURL ?? outputURL }

        var publication: ReplyProtocol.Receipt.Publication {
            if deleted { return .removed }
            switch stage {
            case .accepted, .reserved: return .pending
            case .published, .shown: return .ready
            case .failed: return .failed
            case .cancelled: return .cancelled
            }
        }
    }
}
