import CryptoKit
import Foundation

/// The bytes an agent's reply helper writes and the acknowledgement Vignette writes back. The
/// helper freezes a bundle once and submits it as many times as it needs to; Vignette owns the
/// request directory those files live in, decides what a reply may say, and answers in a receipt
/// file at a path it derives itself. `skills/vignette/scripts/reply` is the other half of this
/// file: change both together and raise `version`.
///
/// A `vignette://` URL has no authenticated sender, so authorization is a per-request bearer
/// secret in the request's own directory. Holding it permits replies to that one request. It does
/// not establish which process produced a reply, and there is no verified-author badge.
enum ReplyProtocol {
    /// Goes up with any change to the envelope, the bundle, the digest, or the receipt. A helper
    /// built for another version is refused rather than half-understood.
    static let version = 1

    /// The most a bundle or an attempt file may be. Marks are a few kilobytes; anything near this
    /// is a mistake, and both files are read on the main thread.
    static let maxBundleBytes = AgentMark.maxBytes + 16 * 1024
    static let maxAttemptBytes = 16 * 1024
    /// The most an accepted reply image may be. A screenshot is well under this.
    static let maxImageBytes = 64 * 1024 * 1024
    /// Why a reply was refused, in the words `[reply] error <code>` uses and the receipt records.
    enum Refusal: String {
        case badEnvelope = "bad-envelope"
        case unknownRequest = "unknown-request"
        case protocolMismatch = "protocol-mismatch"
        case badAuthorization = "bad-authorization"
        case requestClosed = "request-closed"
        case digestMismatch = "digest-mismatch"
        case conflictingReply = "conflicting-reply"
        case badPayload = "bad-payload"
        case tooLarge = "too-large"
        case storeFailed = "store-failed"
    }

    struct Problem: Error, CustomStringConvertible {
        let code: Refusal
        let description: String
        init(_ code: Refusal, _ description: String) { self.code = code; self.description = description }
    }

    // MARK: Identities

    /// Ids are UUIDs, lowercased. Everything that becomes a path component is checked with this, so
    /// no decoded field can carry `..`, a slash, or a name that escapes the request directory.
    static func isID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil && value == value.lowercased()
    }

    static func newID() -> String { UUID().uuidString.lowercased() }

    /// The watch-folder name an accepted reply is published under. Reserved for this feature: a
    /// file in this shape is not an ordinary capture, whatever else is in the folder.
    static func replyFileName(_ replyID: String) -> String { "Agent reply \(replyID).png" }

    /// The reply id a managed file name carries, or nil when the name is an ordinary screenshot's.
    /// Only this exact shape counts; a file merely starting with "Agent" is a capture like any other.
    static func replyID(fromFileName name: String) -> String? {
        guard name.hasPrefix("Agent reply "), name.hasSuffix(".png") else { return nil }
        let id = String(name.dropFirst("Agent reply ".count).dropLast(".png".count))
        return isID(id) ? id : nil
    }

    // MARK: The ticket

    /// What the agent is given: where its reply goes and the secret that authorizes it. Written
    /// into the request's own directory; its path travels in the request line, the secret does not.
    struct Ticket: Codable, Equatable {
        var protocolVersion = ReplyProtocol.version
        let requestID: String
        let secret: String
        /// The request directory. The helper derives every path it writes from this one.
        let requestDirectory: String
        /// The app bundle that issued this request. A reply belongs to the instance that asked for
        /// it, and `open` on its own hands a `vignette://` URL to whichever copy of the bundle id
        /// LaunchServices registered last — another build on the machine, which answers
        /// `unknown-command`. Naming the bundle is what keeps a reply on the right app.
        let app: String

        enum CodingKeys: String, CodingKey {
            case protocolVersion, requestID = "requestId", secret, requestDirectory, app
        }
    }

    /// 32 random bytes, base64url without padding: a URL, a file name, and an argv element all
    /// carry it unchanged.
    static func newSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Compares two secrets in time that does not depend on how much of them matches.
    static func secretsMatch(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    // MARK: The bundle and the attempt

    /// A frozen reply: the drawing the agent means to send back, with a new reply id, written
    /// once. A retry submits this same bundle again rather than reading the agent's files a second
    /// time. It carries no words: an agent answers in its own session, where the person is looking.
    struct Bundle: Equatable {
        let requestID: String
        let replyID: String
        /// True when the reply supplies its own PNG, which sits beside the bundle as `image.png`.
        /// False means the marks go on the request's own fixed image.
        let hasImage: Bool
        let marks: [AgentMark]
    }

    /// One dispatch of a bundle. Carries the authorization and the digest; never the payload.
    struct Attempt: Equatable {
        let protocolVersion: Int
        let requestID: String
        let replyID: String
        let attemptID: String
        let payloadDigest: String
        let secret: String
    }

    /// The identity of a reply's bytes: the bundle exactly as it was written, then the image bytes
    /// when there are any. Over bytes rather than over re-encoded fields, so the helper and the app
    /// cannot disagree about how a number is spelled.
    static func payloadDigest(bundle: Data, image: Data?) -> String {
        var hasher = SHA256()
        hasher.update(data: bundle)
        hasher.update(data: Data([0]))
        if let image { hasher.update(data: image) }
        return "sha256:" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Where the helper's files must be

    /// `<requests>/<requestID>`. The one place a request's files live.
    static func requestDirectory(root: URL, requestID: String) -> URL {
        root.appendingPathComponent(requestID)
    }

    static func submissionDirectory(root: URL, requestID: String, replyID: String) -> URL {
        requestDirectory(root: root, requestID: requestID)
            .appendingPathComponent("submissions").appendingPathComponent(replyID)
    }

    static func bundleURL(root: URL, requestID: String, replyID: String) -> URL {
        submissionDirectory(root: root, requestID: requestID, replyID: replyID).appendingPathComponent("bundle.json")
    }

    static func bundleImageURL(root: URL, requestID: String, replyID: String) -> URL {
        submissionDirectory(root: root, requestID: requestID, replyID: replyID).appendingPathComponent("image.png")
    }

    static func attemptURL(root: URL, requestID: String, replyID: String, attemptID: String) -> URL {
        submissionDirectory(root: root, requestID: requestID, replyID: replyID)
            .appendingPathComponent("attempt-" + attemptID + ".json")
    }

    static func receiptURL(root: URL, requestID: String, attemptID: String) -> URL {
        requestDirectory(root: root, requestID: requestID)
            .appendingPathComponent("receipts").appendingPathComponent(attemptID + ".json")
    }

    // MARK: Reading what the helper wrote

    /// The attempt at `url`, refused unless the file is where its own ids say it should be. The
    /// path is derived from the decoded ids and compared with the caller's, so a caller cannot
    /// name a file outside the request directory or reach one through a link.
    static func readAttempt(at url: URL, root: URL) throws -> Attempt {
        let data = try read(url, limit: maxAttemptBytes, what: "the envelope")
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Problem(.badEnvelope, "the envelope is not a JSON object")
        }
        func text(_ key: String) throws -> String {
            guard let value = object[key] as? String, !value.isEmpty else {
                throw Problem(.badEnvelope, "the envelope has no \(key)")
            }
            return value
        }
        let requestID = try text("requestId"), replyID = try text("replyId"), attemptID = try text("attemptId")
        guard isID(requestID), isID(replyID), isID(attemptID) else {
            throw Problem(.badEnvelope, "requestId, replyId, and attemptId must be lowercase UUIDs")
        }
        let attempt = Attempt(
            protocolVersion: object["protocolVersion"] as? Int ?? 0,
            requestID: requestID, replyID: replyID, attemptID: attemptID,
            payloadDigest: try text("payloadDigest"), secret: try text("secret"))
        // The root is resolved because Vignette created it and the path in the ticket is whatever
        // `Application Support` spells; everything below it must be real. Resolving both sides
        // instead would match through a symbolic link put in place of `submissions/<replyId>`,
        // and the bundle would then be read from wherever that link led.
        let expected = attemptURL(root: URL(fileURLWithPath: Commands.realPath(root)),
                                  requestID: requestID, replyID: replyID, attemptID: attemptID)
        guard Commands.realPath(url) == expected.path else {
            throw Problem(.badEnvelope, "an envelope for \(attemptID) must be at \(expected.path)")
        }
        guard attempt.protocolVersion == version else {
            throw Problem(.protocolMismatch, "helper protocol \(attempt.protocolVersion), app \(version)")
        }
        guard attempt.payloadDigest.hasPrefix("sha256:"), attempt.payloadDigest.count == 71 else {
            throw Problem(.badEnvelope, "payloadDigest is not a sha256 hex digest")
        }
        return attempt
    }

    /// The bundle the attempt refers to, its image when it has one, and the digest of both. The
    /// digest is recomputed here rather than trusted, so a bundle changed after it was prepared is
    /// a mismatch rather than a silently different reply.
    static func readBundle(for attempt: Attempt, root: URL) throws -> (bundle: Bundle, image: Data?, digest: String) {
        let url = bundleURL(root: root, requestID: attempt.requestID, replyID: attempt.replyID)
        let data = try read(url, limit: maxBundleBytes, what: "the bundle")
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Problem(.badPayload, "the bundle is not a JSON object")
        }
        guard object["requestId"] as? String == attempt.requestID, object["replyId"] as? String == attempt.replyID else {
            throw Problem(.badPayload, "the bundle names another request or reply")
        }
        let bundleVersion = object["protocolVersion"] as? Int ?? 0
        guard bundleVersion == version else {
            throw Problem(.protocolMismatch, "bundle protocol \(bundleVersion), app \(version)")
        }
        let hasImage = object["hasImage"] as? Bool ?? false
        var marks: [AgentMark] = []
        if let list = object["marks"] as? [[String: Any]], !list.isEmpty {
            guard let json = try? JSONSerialization.data(withJSONObject: list),
                  let text = String(data: json, encoding: .utf8) else {
                throw Problem(.badPayload, "the bundle's marks are not readable")
            }
            do { marks = try AgentMark.parse(text) }
            catch { throw Problem(.badPayload, "\(error)") }
        }
        var image: Data?
        if hasImage {
            let imageURL = bundleImageURL(root: root, requestID: attempt.requestID, replyID: attempt.replyID)
            image = try read(imageURL, limit: maxImageBytes, what: "the reply image")
            guard Commands.isReadableImage(imageURL) else {
                throw Problem(.badPayload, "the reply image is not an image this app can read")
            }
        }
        guard hasImage || !marks.isEmpty else {
            throw Problem(.badPayload, "the reply carries neither an image nor marks")
        }
        let bundle = Bundle(requestID: attempt.requestID, replyID: attempt.replyID, hasImage: hasImage, marks: marks)
        return (bundle, image, payloadDigest(bundle: data, image: image))
    }

    /// Reads a regular file, refusing a directory, a device, a symbolic link, or one too big to
    /// read on the main thread. A link is refused rather than resolved: the helper writes real
    /// files, and following one would make the path check answer about a different file than the
    /// one that is read. `readAttempt` refuses a link above this one for the same reason, so no
    /// part of the path below the request root is a link by the time anything here is read.
    private static func read(_ url: URL, limit: Int, what: String) throws -> Data {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard let size = values?.fileSize, values?.isRegularFile == true, values?.isSymbolicLink != true else {
            throw Problem(.badEnvelope, "cannot read \(what) at \(url.path)")
        }
        guard size <= limit else { throw Problem(.tooLarge, "\(what) is \(size) bytes; at most \(limit)") }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw Problem(.badEnvelope, "cannot read \(what) at \(url.path)")
        }
        return Data(data)
    }

    // MARK: The acknowledgement

    /// What Vignette wrote back for one attempt. The helper waits for this file and for nothing else:
    /// `open` exiting zero is a dispatch result, not an application answer.
    struct Receipt: Codable, Equatable {
        enum Acceptance: String, Codable { case accepted, rejected }
        /// Where an accepted reply's import has reached. Absent on a rejection.
        enum Publication: String, Codable { case pending, ready, failed, cancelled, removed }

        var protocolVersion = ReplyProtocol.version
        let requestID: String
        let replyID: String
        let attemptID: String
        let payloadDigest: String
        let acceptance: Acceptance
        var publication: Publication?
        var errorCode: String?

        enum CodingKeys: String, CodingKey {
            case protocolVersion, requestID = "requestId", replyID = "replyId", attemptID = "attemptId"
            case payloadDigest, acceptance, publication, errorCode
        }
    }
}
