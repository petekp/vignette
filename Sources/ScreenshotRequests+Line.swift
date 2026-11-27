import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: What a request sends, and the line the agent receives

extension ScreenshotRequests {
    /// What a send carries to the agent.
    enum Picture {
        /// The drawing, rendered, and its pins, whose words the line carries and `pins.json` keeps. The
        /// line names the image, and the agent opens it. `base` is the drawing rendered without its
        /// pins, which a reply goes on (`ReplyProtocol.baseImageURL`); nil when it has none. `apps` are
        /// the apps the screenshot shows (`CaptureApps`), which the line names.
        case drawing(png: Data, pins: [Pin] = [], base: Data? = nil, apps: [String] = [])
        /// The agent's own image, with the drawing exactly as the agent sent it, and the person's
        /// words. The line names the card's file and its title, and no picture travels. A drawing in
        /// answer still needs a picture to go on, so the request keeps the card's own picture,
        /// without the agent's marks: `png`, or nil when the card's file is a PNG, which is cloned.
        case unchanged(card: URL, title: String?, png: Data?)

        var isUnchanged: Bool {
            if case .unchanged = self { return true }
            return false
        }

        /// Writes the picture a reply without its own image draws on, as `image.png` in the request's
        /// `directory`, and the pins beside it as `pins.json` when there are any. On APFS a clone takes
        /// no room until one of the two files changes.
        func store(in directory: URL) throws {
            let image = directory.appendingPathComponent("image.png")
            switch self {
            case .drawing(let png, _, _, _), .unchanged(_, _, let png?): try png.write(to: image, options: .atomic)
            case .unchanged(let card, _, nil): try FileManager.default.copyItem(at: card, to: image)
            }
            guard !pins.isEmpty else { return }
            if case .drawing(_, _, let base?, _) = self { try base.write(to: ReplyProtocol.baseImageURL(in: directory), options: .atomic) }
            try DrawingJSON.encode(["pins": pins.map(PinRecord.init)]).write(to: directory.appendingPathComponent("pins.json"), options: .atomic)
        }

        var pins: [Pin] {
            if case .drawing(_, let pins, _, _) = self { return pins.sorted { $0.number < $1.number } }
            return []
        }

        var apps: [String] {
            if case .drawing(_, _, _, let apps) = self { return apps }
            return []
        }

        /// The title the agent gave the unchanged image, which the line repeats.
        var title: String? {
            if case .unchanged(_, let title, _) = self { return title }
            return nil
        }

        /// For the `[send] prepared` line.
        var logged: String {
            switch self {
            case .drawing(let png, let pins, _, let apps):
                return "\(png.count) bytes" + (pins.isEmpty ? "" : " pins=\(pins.count)") + (apps.isEmpty ? "" : " apps=\(apps.count)")
            case .unchanged: return "unchanged, no picture sent"
            }
        }
    }

    /// What a press of Send or Reply carries.
    enum Carried: Equatable {
        /// Reply on the agent's own image with no words and the drawing as the agent sent it: nothing
        /// is sent, and Return copies and closes as Done does.
        case nothingNew
        /// The person's words on the agent's own image, which the line names (`Picture.unchanged`).
        case wordsAlone
        /// The drawing, rendered.
        case drawing

        /// What a press carries. Words alone only to the session the card came from, since another
        /// has not seen the image, and only for a card whose path the line can quote: a line break
        /// in it would split the line into two messages.
        static func of(card: URL, origin: AgentAddress?, destination: AgentAddress, asTheAgentSent: Bool,
                       message: String?) -> Carried {
            guard origin == destination, asTheAgentSent else { return .drawing }
            guard message != nil else { return .nothingNew }
            return card.path.rangeOfCharacter(from: .controlCharacters) == nil ? .wordsAlone : .drawing
        }

        /// The drawing to render for this press, without its resolved pins. Words alone keep the card's
        /// own picture, without the agent's marks or pins, as the one a drawn answer goes on: what the
        /// clone of a PNG card holds too.
        func rendering(_ drawing: Drawing) -> Drawing {
            guard self == .wordsAlone else { return drawing.handedOver }
            var picture = drawing
            picture.marks = []
            picture.pins = []
            return picture
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
              watchingTurn: Bool = false, cardTitle: String? = nil) throws -> Record {
        try send(.drawing(png: png), source: source, to: destination, message: message, instructions: instructions,
                 grace: grace, watchingTurn: watchingTurn, cardTitle: cardTitle)
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
    ///
    /// The pins' words follow the message, as `Pin.lineWords` writes them, and lead the line when
    /// there is no message. `apps`, the apps the screenshot shows (`CaptureApps`), follow the image.
    static func requestLine(record: Record, root: URL, message: String? = nil,
                            instructions: String = SettingsData.defaultSendInstructions, title: String? = nil,
                            pins: [Pin] = [], apps: [String] = []) -> String {
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
        let about: String
        if record.unchanged == true {
            let card = record.sourceKey ?? record.source
            let titled = title.map { " (\"\($0)\")" } ?? ""
            let ticket = directory.appendingPathComponent("ticket.json").path
            about = "about your image \"\(card)\"\(titled), unchanged since you sent it. The reply ticket is \"\(ticket)\"."
        } else {
            about = "\"\(directory.appendingPathComponent("image.png").path)\"." + (apps.isEmpty ? "" : " The screenshot shows \(listed(apps)).")
        }
        let note = "From Vignette: \(about)" + (instructions.isEmpty ? "" : " \(instructions)")
        guard !pins.isEmpty else { return message.map { "\($0) [\(note)]" } ?? note }
        let request = [message.map(Pin.ended), Pin.lineWords(pins)].compactMap { $0 }.joined(separator: " ")
        return "\(request) [\(note)]"
    }

    /// The line for `picture`, with the title, the pins and the apps it carries.
    static func requestLine(record: Record, root: URL, message: String?, instructions: String, picture: Picture) -> String {
        requestLine(record: record, root: root, message: message, instructions: instructions, title: picture.title,
                    pins: picture.pins, apps: picture.apps)
    }

    /// "Safari", "Safari and Xcode", "Safari, Xcode and Finder".
    private static func listed(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}

extension String {
    /// The words with one space between each, whatever line breaks, tabs or spaces were there: what
    /// the line Send puts in a session can hold, since the plugin's monitor makes each line one message.
    var asOneLine: String { split(whereSeparator: \.isWhitespace).joined(separator: " ") }
}
