import XCTest

final class ReplyProtocolTests: XCTestCase {
    private var root: URL!
    private let requestID = "11111111-1111-4111-8111-111111111111"
    private let replyID = "22222222-2222-4222-8222-222222222222"
    private let attemptID = "33333333-3333-4333-8333-333333333333"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-reply-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    /// Writes a bundle and an attempt where they belong, as the helper does.
    @discardableResult
    private func stage(marks: String = #"[{"type":"ellipse","x":0.1,"y":0.1,"w":0.2,"h":0.2}]"#,
                       secret: String = "s3cret", digest: String? = nil, replyID: String? = nil) throws -> URL {
        let replyID = replyID ?? self.replyID
        let directory = ReplyProtocol.submissionDirectory(root: root, requestID: requestID, replyID: replyID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bundle = Data(#"{"protocolVersion":1,"hasImage":false,"marks":\#(marks),"replyId":"\#(replyID)","requestId":"\#(requestID)"}"#.utf8)
        try bundle.write(to: directory.appendingPathComponent("bundle.json"))
        let url = ReplyProtocol.attemptURL(root: root, requestID: requestID, replyID: replyID, attemptID: attemptID)
        let attempt = #"{"protocolVersion":1,"requestId":"\#(requestID)","replyId":"\#(replyID)","attemptId":"\#(attemptID)","payloadDigest":"\#(digest ?? ReplyProtocol.payloadDigest(bundle: bundle, image: nil))","secret":"\#(secret)"}"#
        try Data(attempt.utf8).write(to: url)
        return url
    }

    // MARK: The reserved file name

    func testOnlyTheExactManagedNameIsAManagedReply() {
        XCTAssertEqual(ReplyProtocol.replyID(fromFileName: "Agent reply \(replyID).png"), replyID)
        // Ordinary screenshots that merely start with the same word stay ordinary captures.
        XCTAssertNil(ReplyProtocol.replyID(fromFileName: "Agent reply notes.png"))
        XCTAssertNil(ReplyProtocol.replyID(fromFileName: "Agent standup 3.png"))
        XCTAssertNil(ReplyProtocol.replyID(fromFileName: "Agent reply \(replyID).jpg"))
        XCTAssertNil(ReplyProtocol.replyID(fromFileName: "Screenshot 2026-09-20.png"))
    }

    func testAnIdIsALowercaseUuidAndNothingElse() {
        XCTAssertTrue(ReplyProtocol.isID(replyID))
        XCTAssertFalse(ReplyProtocol.isID("E011FFF1-C791-4934-9E61-9307D840A5EB"))
        XCTAssertTrue(ReplyProtocol.isID("e011fff1-c791-4934-9e61-9307d840a5eb"))
        XCTAssertFalse(ReplyProtocol.isID(".."))
        XCTAssertFalse(ReplyProtocol.isID("../../etc"))
        XCTAssertFalse(ReplyProtocol.isID(""))
    }

    // MARK: The digest

    func testTheDigestCoversTheBundleAndTheImageSeparately() {
        let a = ReplyProtocol.payloadDigest(bundle: Data("ab".utf8), image: Data("c".utf8))
        let b = ReplyProtocol.payloadDigest(bundle: Data("a".utf8), image: Data("bc".utf8))
        XCTAssertNotEqual(a, b, "the separator has to keep the two fields apart")
        XCTAssertEqual(a, ReplyProtocol.payloadDigest(bundle: Data("ab".utf8), image: Data("c".utf8)))
        XCTAssertNotEqual(ReplyProtocol.payloadDigest(bundle: Data("ab".utf8), image: nil), a)
    }

    func testSecretsCompareByValue() {
        XCTAssertTrue(ReplyProtocol.secretsMatch("abc", "abc"))
        XCTAssertFalse(ReplyProtocol.secretsMatch("abc", "abd"))
        XCTAssertFalse(ReplyProtocol.secretsMatch("abc", "abcd"))
    }

    // MARK: Where an envelope may be

    func testAnEnvelopeIsReadWhereItsOwnIdsSayItShouldBe() throws {
        let url = try stage()
        let attempt = try ReplyProtocol.readAttempt(at: url, root: root)
        XCTAssertEqual(attempt.replyID, replyID)
        XCTAssertEqual(attempt.secret, "s3cret")
    }

    func testAnEnvelopeSomewhereElseIsRefused() throws {
        let url = try stage()
        let elsewhere = root.appendingPathComponent("loose.json")
        try FileManager.default.copyItem(at: url, to: elsewhere)
        XCTAssertThrowsError(try ReplyProtocol.readAttempt(at: elsewhere, root: root)) { error in
            XCTAssertEqual((error as? ReplyProtocol.Problem)?.code, .badEnvelope)
        }
    }

    func testAnEnvelopeThatIsALinkIsRefusedRatherThanFollowed() throws {
        let url = try stage()
        let link = ReplyProtocol.attemptURL(root: root, requestID: requestID, replyID: replyID,
                                            attemptID: attemptID).deletingLastPathComponent()
            .appendingPathComponent("attempt-44444444-4444-4444-8444-444444444444.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        XCTAssertThrowsError(try ReplyProtocol.readAttempt(at: link, root: root)) { error in
            XCTAssertEqual((error as? ReplyProtocol.Problem)?.code, .badEnvelope)
        }
    }

    func testAHelperFromAnotherProtocolIsRefused() throws {
        let url = try stage()
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"protocolVersion\":1", with: "\"protocolVersion\":99")
        try Data(text.utf8).write(to: url)
        XCTAssertThrowsError(try ReplyProtocol.readAttempt(at: url, root: root)) { error in
            XCTAssertEqual((error as? ReplyProtocol.Problem)?.code, .protocolMismatch)
        }
    }

    // MARK: The bundle

    func testTheBundlesDigestIsRecomputedRatherThanTrusted() throws {
        let url = try stage(digest: "sha256:" + String(repeating: "0", count: 64))
        let attempt = try ReplyProtocol.readAttempt(at: url, root: root)
        let read = try ReplyProtocol.readBundle(for: attempt, root: root)
        XCTAssertNotEqual(read.digest, attempt.payloadDigest)
    }

    func testABundleChangedAfterItWasPreparedNoLongerMatchesItsAttempt() throws {
        let url = try stage()
        let attempt = try ReplyProtocol.readAttempt(at: url, root: root)
        let bundle = ReplyProtocol.bundleURL(root: root, requestID: requestID, replyID: replyID)
        var text = try String(contentsOf: bundle, encoding: .utf8)
        text = text.replacingOccurrences(of: "0.1", with: "0.9")
        try Data(text.utf8).write(to: bundle)
        XCTAssertNotEqual(try ReplyProtocol.readBundle(for: attempt, root: root).digest, attempt.payloadDigest)
    }

    func testMarksAreCheckedTheSameWayAPushedDrawingIs() throws {
        let url = try stage(marks: #"[{"type":"ellipse","x":9,"y":0.1,"w":0.2,"h":0.2}]"#)
        let attempt = try ReplyProtocol.readAttempt(at: url, root: root)
        XCTAssertThrowsError(try ReplyProtocol.readBundle(for: attempt, root: root)) { error in
            XCTAssertEqual((error as? ReplyProtocol.Problem)?.code, .badPayload)
        }
    }

    func testAReplyWithNeitherImageNorMarksSaysNothing() throws {
        let url = try stage(marks: "[]")
        let attempt = try ReplyProtocol.readAttempt(at: url, root: root)
        XCTAssertThrowsError(try ReplyProtocol.readBundle(for: attempt, root: root)) { error in
            XCTAssertEqual((error as? ReplyProtocol.Problem)?.code, .badPayload)
        }
    }

    func testABundleThatNamesAnotherReplyIsRefused() throws {
        let url = try stage()
        let attempt = try ReplyProtocol.readAttempt(at: url, root: root)
        let bundle = ReplyProtocol.bundleURL(root: root, requestID: requestID, replyID: replyID)
        let text = try String(contentsOf: bundle, encoding: .utf8).replacingOccurrences(of: replyID, with: attemptID)
        try Data(text.utf8).write(to: bundle)
        XCTAssertThrowsError(try ReplyProtocol.readBundle(for: attempt, root: root)) { error in
            XCTAssertEqual((error as? ReplyProtocol.Problem)?.code, .badPayload)
        }
    }
}
