import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: What a request sends, and the line the agent receives

extension ScreenshotRequests {
    /// What a send carries to the agent.
    enum Picture {
        /// The drawing, rendered. The line names it, and the agent opens it.
        case drawing(png: Data)
        /// The agent's own image, with the drawing exactly as the agent sent it, and the person's
        /// words. The line names the card's file and its title, and no picture travels. A drawing in
        /// answer still needs a picture to go on, so the request keeps the card's own picture,
        /// without the agent's marks: `png`, or nil when the card's file is a PNG, which is cloned.
        case unchanged(card: URL, title: String?, png: Data?)

        var isUnchanged: Bool {
            if case .unchanged = self { return true }
            return false
        }

        /// Writes the picture a reply without its own image draws on, as the request's `image.png`.
        /// On APFS the clone takes no room until one of the two files changes.
        func store(at url: URL) throws {
            switch self {
            case .drawing(let png), .unchanged(_, _, let png?): try png.write(to: url, options: .atomic)
            case .unchanged(let card, _, nil): try FileManager.default.copyItem(at: card, to: url)
            }
        }

        /// For the `[send] prepared` line.
        var logged: String {
            switch self {
            case .drawing(let png): return "\(png.count) bytes"
            case .unchanged: return "unchanged, no picture sent"
            }
        }
    }

    /// Whether the file is a PNG by its bytes, which a request can clone as its `image.png`.
    nonisolated static func isPNG(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) else { return false }
        return type as String == UTType.png.identifier
    }

    /// The drawing rendered as a PNG and sent to `destination` (`send(_:source:to:…)`).
    @discardableResult
    func send(png: Data, source: ScreenshotKey, to destination: AgentDestination, message: String? = nil,
              instructions: String = SettingsData.defaultSendInstructions, grace: TimeInterval = 0,
              watchingTurn: Bool = false) throws -> Record {
        try send(.drawing(png: png), source: source, to: destination, message: message, instructions: instructions,
                 grace: grace, watchingTurn: watchingTurn)
    }

    /// The one line the agent receives, which arrives in the person's session as their own message.
    /// The person's message, already one line (`AnnotatorToolbar.Model.sentMessage`), leads, as the
    /// request, and the Vignette part follows in brackets, as a note on what came with it. One line,
    /// because the plugin's monitor makes each line it prints one message. "From Vignette:" is fixed,
    /// because the skill loads on it, and `instructions` (`sendInstructions` in settings.json) ends it.
    /// The ticket's secret never travels.
    ///
    /// A drawing names only the image; the skill says the `ticket.json` beside it answers with a
    /// drawing. An unchanged image (`Record.unchanged`) names the card's file, which the agent knows
    /// from its push or its reply, and the title it gave, and says the image is as the agent sent
    /// it, so the agent opens nothing. No image is beside that file, so it names the ticket.
    static func requestLine(record: Record, root: URL, message: String? = nil,
                            instructions: String = SettingsData.defaultSendInstructions, title: String? = nil) -> String {
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
        let about: String
        if record.unchanged == true {
            let card = record.sourceKey ?? record.source
            let titled = title.map { " (\"\($0)\")" } ?? ""
            let ticket = directory.appendingPathComponent("ticket.json").path
            about = "about your image \"\(card)\"\(titled), unchanged since you sent it. The reply ticket is \"\(ticket)\"."
        } else {
            about = "\"\(directory.appendingPathComponent("image.png").path)\"."
        }
        let note = "From Vignette: \(about)" + (instructions.isEmpty ? "" : " \(instructions)")
        return message.map { "\($0) [\(note)]" } ?? note
    }
}
