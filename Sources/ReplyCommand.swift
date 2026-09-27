import Foundation

/// `<executable> reply …`, the skill's reply helper: answers a screenshot request with an agent's
/// drawing. The skill's `scripts/reply` finds this binary through the ticket's `app` and passes its
/// arguments on. `AppDelegate.main` runs this before `NSApplication` exists, and it always exits, so
/// the app never starts. It writes the files `ReplyProtocol` reads, sends one `reply` URL to the app
/// that issued the request, and waits for that app's receipt.
enum ReplyCommand {
    /// A problem found before anything was sent, printed as `{"status": "error"}` with exit code 1.
    struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    /// One frozen reply: its bundle's folder, its id, and the digest every attempt carries.
    struct Prepared: Equatable {
        let directory: URL
        let replyID: String
        let digest: String
    }

    /// How long to wait for the receipt. The app answers in well under a second; the margin is for
    /// an app that is busy rendering somebody's drawing.
    static let receiptTimeout: TimeInterval = 30
    static let receiptPoll: TimeInterval = 0.1

    static let usage = """
    usage: reply --ticket <ticket.json> --marks <marks.json> [--image <your image>]
           reply --ticket <ticket.json> --retry <bundle folder>

    Answers a Vignette screenshot request with a drawing of your own. Vignette sends a message
    containing "From Vignette:" that names an image, and its ticket.json is in the same folder.
    The marks arrive on a new card the person can edit like their own drawing.

    The marks file is a JSON array. Every number is a fraction of the image: x,y is a shape's
    top-left corner or an arrow's tail, w,h its size, x2,y2 an arrow's head.

        [{"type": "ellipse",   "x": 0.12, "y": 0.30, "w": 0.20, "h": 0.10},
         {"type": "arrow",     "x": 0.50, "y": 0.50, "x2": 0.70, "y2": 0.60},
         {"type": "rectangle", "x": 0.10, "y": 0.10, "w": 0.30, "h": 0.20},
         {"type": "text",      "x": 0.10, "y": 0.80, "w": 0.50, "text": "This header should not scroll"}]

    At most \(AgentMark.maxCount) marks. A mark with no "color" is coloured from the pixels it covers; to choose
    one, name it: \(MarkColor.allCases.map(\.rawValue).joined(separator: ", ")). Without --image the marks go on
    the picture you were sent. With it they go on yours, sent as a PNG of at most \(ReplyProtocol.maxImageBytes / 1_048_576) MB, and
    the marks may be an empty array. A JPEG or any other image macOS reads is converted.

    Prints one JSON line and exits 0 accepted, 1 not sent, 2 refused, or 3 unconfirmed. Not sent
    means an argument, a file or a mark is wrong, and "error" says which. Unconfirmed means
    Vignette never answered: the reply may or may not have arrived, so do not send a new one.
    Retry that exact reply instead, which can never make a second card. A retry that exits 1 sent
    nothing, but the first attempt may still have arrived, so do not send a new reply then either.
    """

    static func run(_ arguments: [String]) -> Never {
        do {
            let options = try Options(arguments)
            if options.help {
                print(usage)
                exit(0)
            }
            try send(options)
        } catch let failure as Failure {
            emit(["status": "error", "error": failure.message])
            exit(1)
        } catch {
            emit(["status": "error", "error": "\(error)"])
            exit(1)
        }
    }

    private static func send(_ options: Options) throws -> Never {
        guard let ticketPath = options.ticket else {
            throw Failure("--ticket is required: the ticket.json in the same folder as the image you were sent")
        }
        let ticketFile = URL(fileURLWithPath: ticketPath).standardizedFileURL
        let ticket = try loadTicket(ticketFile.path)
        try checkIssuer(ticket)
        let prepared: Prepared
        if let retry = options.retry {
            // A retry is the same bytes again, which is what makes it safe to send twice. Marks given
            // with it would be dropped without a word, so they are refused instead.
            guard options.marks == nil, options.image == nil else {
                throw Failure("--retry sends the prepared reply unchanged; drop --marks and --image")
            }
            do {
                prepared = try reread(URL(fileURLWithPath: retry))
            } catch is Failure where isCleared(ticket) {
                throw Failure("the user cleared this request, which removed the reply prepared for it; it takes no replies now")
            }
        } else {
            guard options.marks != nil || options.image != nil else {
                throw Failure("nothing to send: give --marks, --image, or both")
            }
            let marks = try options.marks.map { try loadMarks($0, allowingEmpty: options.image != nil) } ?? []
            let image = try options.image.map { try loadImage(URL(fileURLWithPath: $0)) }
            prepared = try prepare(ticket: ticket, marks: marks, image: image)
        }

        let attempt = try writeAttempt(ticket: ticket, prepared: prepared)
        let dispatch = self.dispatch(attempt.envelope, ticket: ticket)
        guard let receipt = waitForReceipt(ticket: ticket, prepared: prepared, attemptID: attempt.id) else {
            let retry = [Bundle.main.executablePath ?? CommandLine.arguments[0], "reply", "--ticket", ticketFile.path,
                         "--retry", prepared.directory.path].map(quoted).joined(separator: " ")
            emit(["status": "unconfirmed", "replyId": prepared.replyID, "bundle": prepared.directory.path,
                  "detail": dispatch.status == 0 ? "Vignette wrote no receipt within \(Int(receiptTimeout)) s"
                                                 : "open exited \(dispatch.status): \(dispatch.error)",
                  "retry": retry])
            exit(3)
        }
        guard receipt.acceptance == .accepted else {
            emit(["status": "refused", "replyId": prepared.replyID, "error": receipt.errorCode ?? "refused"])
            exit(2)
        }
        emit(["status": "accepted", "replyId": prepared.replyID, "publication": receipt.publication?.rawValue])
        exit(0)
    }

    // MARK: The steps

    /// The ticket at `path`. Read field by field rather than decoded, so a missing field is named.
    static func loadTicket(_ path: String) throws -> ReplyProtocol.Ticket {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Failure("cannot read the ticket at \(url.path)")
        }
        let version = object["protocolVersion"] as? Int
        guard version == ReplyProtocol.version else {
            throw Failure("this helper speaks protocol \(ReplyProtocol.version), the ticket says \(version.map(String.init) ?? "none")")
        }
        func text(_ key: String) throws -> String {
            guard let value = object[key] as? String, !value.isEmpty else { throw Failure("the ticket has no \(key)") }
            return value
        }
        let ticket = ReplyProtocol.Ticket(requestID: try text("requestId"), secret: try text("secret"),
                                          requestDirectory: try text("requestDirectory"), app: try text("app"))
        // Every path this writes is derived from the request's folder and the ids, as the app derives
        // the paths it reads. `scripts/reply` checked the folder the ticket is in, so that folder has
        // to be the one the ticket names.
        let directory = URL(fileURLWithPath: ticket.requestDirectory)
        guard ReplyProtocol.isID(ticket.requestID), directory.lastPathComponent == ticket.requestID,
              Commands.realPath(directory) == Commands.realPath(url.deletingLastPathComponent()) else {
            throw Failure("the ticket's requestDirectory is not its request's folder, where the ticket is")
        }
        return ticket
    }

    /// Refuses a ticket another app issued. `scripts/reply` reads the ticket's `app` to find this
    /// binary and parses the arguments on its own; were the two ever to read different tickets, the
    /// reply must not go out through a binary its request did not come from.
    static func checkIssuer(_ ticket: ReplyProtocol.Ticket, bundle: URL = Bundle.main.bundleURL) throws {
        guard Commands.realPath(URL(fileURLWithPath: ticket.app)) == Commands.realPath(bundle) else {
            throw Failure("this ticket is for the Vignette at \(ticket.app), not this one at \(bundle.path)")
        }
    }

    /// The marks at `path`, checked by the validator the app runs when the reply arrives, so a bad
    /// mark fails here, naming the mark and the field.
    static func loadMarks(_ path: String, allowingEmpty: Bool = false) throws -> [AgentMark] {
        do { return try AgentMark.parse(path, allowingEmpty: allowingEmpty) } catch { throw Failure("the marks at \(path): \(error)") }
    }

    /// The agent's picture as the PNG the app accepts (`ReplyProtocol.isPNG`): a PNG as it is, and
    /// any other image ImageIO reads converted, so a JPEG or a HEIC works as well.
    static func loadImage(_ url: URL) throws -> Data {
        // A regular file only: a pipe or a device would block the read.
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true, let size = values?.fileSize else { throw Failure("no image at \(url.path)") }
        let limit = ReplyProtocol.maxImageBytes
        guard size <= limit else { throw Failure("the image at \(url.path) is \(megabytes(size)); at most \(megabytes(limit))") }
        guard let png = Thumbnailer.png(from: url), ReplyProtocol.isPNG(png) else {
            throw Failure("no image this app can read at \(url.path)")
        }
        guard png.count <= limit else {
            throw Failure("the image at \(url.path) is \(megabytes(png.count)) as a PNG; at most \(megabytes(limit))")
        }
        return png
    }

    /// Freezes one reply: a new reply id, the marks, and a staged copy of any image, written once.
    /// A retry sends this again rather than reading the agent's files a second time, so a reply
    /// cannot change under a resend and cannot become a second card.
    static func prepare(ticket: ReplyProtocol.Ticket, marks: [AgentMark], image: Data?) throws -> Prepared {
        let root = root(of: ticket)
        let replyID = ReplyProtocol.newID()
        let directory = ReplyProtocol.submissionDirectory(root: root, requestID: ticket.requestID, replyID: replyID)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Staged before anything is dispatched, so the agent may delete its own file the moment
            // this returns without changing what a retry would send.
            try image?.write(to: ReplyProtocol.bundleImageURL(root: root, requestID: ticket.requestID, replyID: replyID))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let bundle = try encoder.encode(BundleFile(protocolVersion: ReplyProtocol.version, requestId: ticket.requestID,
                                                       replyId: replyID, hasImage: image != nil, marks: marks))
            try bundle.write(to: ReplyProtocol.bundleURL(root: root, requestID: ticket.requestID, replyID: replyID))
            return Prepared(directory: directory, replyID: replyID,
                            digest: ReplyProtocol.payloadDigest(bundle: bundle, image: image))
        } catch {
            throw Failure("cannot write the reply bundle in \(directory.path): \(error.localizedDescription)")
        }
    }

    /// A prepared bundle, for `--retry`: the same reply id and the same digest as when it was made.
    static func reread(_ directory: URL) throws -> Prepared {
        guard let bundle = try? Data(contentsOf: directory.appendingPathComponent("bundle.json")),
              let object = (try? JSONSerialization.jsonObject(with: bundle)) as? [String: Any],
              let replyID = object["replyId"] as? String, ReplyProtocol.isID(replyID) else {
            throw Failure("cannot read the prepared bundle at \(directory.path); --retry takes the bundle folder an earlier run printed")
        }
        var image: Data?
        if object["hasImage"] as? Bool == true {
            guard let bytes = try? Data(contentsOf: directory.appendingPathComponent("image.png")) else {
                throw Failure("cannot read the prepared image at \(directory.path)")
            }
            image = bytes
        }
        return Prepared(directory: directory, replyID: replyID, digest: ReplyProtocol.payloadDigest(bundle: bundle, image: image))
    }

    /// Whether the user cleared the request. Clearing removes its prepared replies, so a retry that
    /// finds no bundle says why rather than only that it is missing.
    private static func isCleared(_ ticket: ReplyProtocol.Ticket) -> Bool {
        let record = URL(fileURLWithPath: ticket.requestDirectory).appendingPathComponent(ScreenshotRequests.recordFileName)
        guard let data = try? Data(contentsOf: record),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return object["status"] as? String == ScreenshotRequests.Record.Status.cleared.rawValue
    }

    /// Writes one attempt's envelope where its ids say it belongs. The secret travels in this file
    /// and never in the URL, which the app logs.
    static func writeAttempt(ticket: ReplyProtocol.Ticket, prepared: Prepared) throws -> (id: String, envelope: URL) {
        let attemptID = ReplyProtocol.newID()
        let envelope = ReplyProtocol.attemptURL(root: root(of: ticket), requestID: ticket.requestID,
                                                replyID: prepared.replyID, attemptID: attemptID)
        let object: [String: Any] = [
            "protocolVersion": ReplyProtocol.version, "requestId": ticket.requestID, "replyId": prepared.replyID,
            "attemptId": attemptID, "payloadDigest": prepared.digest, "secret": ticket.secret,
        ]
        do {
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: envelope)
        } catch {
            throw Failure("cannot write the envelope at \(envelope.path): \(error.localizedDescription)")
        }
        return (attemptID, envelope)
    }

    /// Hands the envelope to the app that issued the request. A nonzero `open` says the URL was not
    /// delivered; it is not proof that nothing was accepted, and a zero one is not proof that
    /// anything was. Only the receipt answers.
    static func dispatch(_ envelope: URL, ticket: ReplyProtocol.Ticket) -> (status: Int32, error: String) {
        // The scheme is the issuing app's, so a fork's reply goes to the fork.
        let scheme = Identity.urlScheme(in: Bundle(path: ticket.app)?.infoDictionary ?? [:]) ?? "vignette"
        let url = "\(scheme)://reply?file=" + (envelope.path.addingPercentEncoding(withAllowedCharacters: queryValue) ?? "")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // -a names the app that issued the request. Without it `open` hands the URL to whichever copy
        // of the bundle id LaunchServices registered last, which on a Mac with a second build is not
        // the app holding this request.
        process.arguments = ["-g", "-a", ticket.app, url]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The receipt for this attempt, or nil when none came within `receiptTimeout`.
    static func waitForReceipt(ticket: ReplyProtocol.Ticket, prepared: Prepared, attemptID: String) -> ReplyProtocol.Receipt? {
        let url = ReplyProtocol.receiptURL(root: root(of: ticket), requestID: ticket.requestID, attemptID: attemptID)
        let deadline = Date().addingTimeInterval(receiptTimeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let receipt = try? JSONDecoder().decode(ReplyProtocol.Receipt.self, from: data),
               answers(receipt, ticket: ticket, prepared: prepared, attemptID: attemptID) {
                return receipt
            }
            Thread.sleep(forTimeInterval: receiptPoll)
        }
        return nil
    }

    /// Every correlation field is checked: a receipt for some other attempt does not answer this one.
    static func answers(_ receipt: ReplyProtocol.Receipt, ticket: ReplyProtocol.Ticket, prepared: Prepared,
                        attemptID: String) -> Bool {
        receipt.protocolVersion == ReplyProtocol.version && receipt.requestID == ticket.requestID
            && receipt.replyID == prepared.replyID && receipt.attemptID == attemptID
            && receipt.payloadDigest == prepared.digest
    }

    // MARK: Parts

    /// What `bundle.json` holds. `ReplyProtocol.readBundle` reads it field by field.
    private struct BundleFile: Encodable {
        let protocolVersion: Int
        let requestId: String
        let replyId: String
        let hasImage: Bool
        let marks: [AgentMark]
    }

    /// The arguments. `scripts/reply` finds `--ticket` the same way, so change both together.
    struct Options {
        var ticket: String?
        var marks: String?
        var image: String?
        var retry: String?
        var help = false

        init(_ arguments: [String]) throws {
            var rest = arguments[...]
            while let argument = rest.popFirst() {
                if argument == "-h" || argument == "--help" { help = true; continue }
                let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                let name = parts[0]
                guard ["--ticket", "--marks", "--image", "--retry"].contains(name) else {
                    throw Failure("unknown argument \(argument); see --help")
                }
                guard let value = parts.count > 1 ? parts[1] : rest.popFirst() else { throw Failure("\(name) needs a value") }
                switch name {
                case "--ticket": ticket = value
                case "--marks": marks = value
                case "--image": image = value
                default: retry = value
                }
            }
        }
    }

    /// `<requests>`: the folder `ReplyProtocol` derives a request's paths from.
    private static func root(of ticket: ReplyProtocol.Ticket) -> URL {
        URL(fileURLWithPath: ticket.requestDirectory).deletingLastPathComponent()
    }

    /// What a query value may carry unencoded: ASCII letters and digits and `-._~/`, as a path
    /// needs, and nothing that ends a value, like `&` or `#`.
    private static let queryValue = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")

    private static func quoted(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    /// One JSON line with its fields in the order given, so `status` reads first. A nil value is
    /// left out.
    private static func emit(_ fields: KeyValuePairs<String, String?>) {
        func json(_ value: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
            return data.map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        }
        let parts = fields.compactMap { key, value in value.map { "\(json(key)): \(json($0))" } }
        print("{" + parts.joined(separator: ", ") + "}")
    }
}
