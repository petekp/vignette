import XCTest

final class ClearedRequestFoldersTests: XCTestCase {
    private var root: URL!
    private var folder: URL { root.appendingPathComponent("request") }
    private var submissions: URL { folder.appendingPathComponent("submissions") }
    private var later: Date { Date().addingTimeInterval(10) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-cleared-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: root)
    }

    func testASubmissionStagedAfterAFinishedPassIsRemovedByTheNext() throws {
        var folders = ClearedRequestFolders(root: root)
        folders.removePayloads(of: "request", now: later)
        try FileManager.default.createDirectory(at: submissions.appendingPathComponent("reply"), withIntermediateDirectories: true)

        folders.removePayloads(of: "request", now: later)

        XCTAssertFalse(FileManager.default.fileExists(atPath: submissions.path))
    }

    func testAClearedRequestLosesItsImageAndItsPinsWordsButKeepsItsTicket() throws {
        for name in ["image.png", "pins.json", "ticket.json"] { try Data("x".utf8).write(to: folder.appendingPathComponent(name)) }
        var folders = ClearedRequestFolders(root: root)

        folders.removePayloads(of: "request", now: later)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["ticket.json"])
    }

    func testAPassThatCouldNotLookIntoTheFolderIsNotCountedAsFinished() throws {
        try FileManager.default.createDirectory(at: submissions, withIntermediateDirectories: true)
        var folders = ClearedRequestFolders(root: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: folder.path)
        folders.removePayloads(of: "request", now: later)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)

        folders.removePayloads(of: "request", now: later)

        XCTAssertFalse(FileManager.default.fileExists(atPath: submissions.path))
    }
}
