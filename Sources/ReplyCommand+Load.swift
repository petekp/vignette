import Foundation

extension ReplyCommand {
    /// The marks at `path`, checked by the validator the app runs when the reply arrives, so a bad
    /// mark fails here, naming the mark and the field.
    static func loadMarks(_ path: String, allowingEmpty: Bool = false) throws -> [AgentMark] {
        do { return try AgentMark.parse(path, allowingEmpty: allowingEmpty) } catch { throw Failure("the marks at \(path): \(error)") }
    }

    /// The answers at `path`, each named by its pin's id, checked against the pins the request sent, and
    /// `resolving`, `--resolve`'s value, the pins they resolve.
    static func loadComments(_ path: String, resolving: String? = nil, ticket: ReplyProtocol.Ticket) throws -> [ReplyProtocol.Comment] {
        let pins = ReplyProtocol.sentPins(in: URL(fileURLWithPath: ticket.requestDirectory))
        do {
            return try ReplyProtocol.comments(answering: AgentMark.json(path, of: "comments"), on: pins,
                                              resolving: resolving.map(ReplyProtocol.resolveList) ?? [])
        } catch { throw Failure("the comments: \(error)") }
    }

    /// The answer at `path`, checked by the validator the app runs when the reply arrives.
    static func loadAnswer(_ path: String) throws -> LiveAnswer {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= AgentMark.maxBytes, let data = try? Data(contentsOf: url) else {
            throw Failure("cannot read an answer at \(url.path)")
        }
        guard let object = try? DrawingJSON.object(from: data) else { throw Failure("the answer at \(path) is not JSON") }
        do { return try LiveAnswer(json: object, strict: true) } catch { throw Failure("the answer at \(path): \(error)") }
    }
}
