import Foundation

/// What Vignette itself puts into the screenshots folder and takes out of it: an agent's push
/// (`add`), a stitch, a published reply, and the trash. It holds back removals the watcher reports
/// from a listing older than the app's last write, and tells the cards, the drawings and the
/// requests when a file has left.
@MainActor
final class FolderWrites {
    struct Callbacks {
        /// The watch folder, as AppDelegate reads it from the settings.
        var folder: () -> URL = { FileManager.default.temporaryDirectory }
        /// Shows an added file's card, or opens it in the editor when `annotate` (AppDelegate.present).
        var present: (Screenshot, _ annotate: Bool) -> Void = { _, _ in }
        /// Shows a published reply's card. A reply never goes through `present`, which treats a file as a capture.
        var showCard: (Screenshot) -> Void = { _ in }
        /// Agents' marks joining the screenshot's drawing; answers with how many joined.
        var joinMarks: ([AgentMark], _ agent: String?, URL, @escaping (Result<Int, Drawings.Failure>) -> Void) -> Void = { _, _, _, done in
            done(.failure(Drawings.Failure(code: .writeFailed, description: "nothing stores drawings")))
        }
        var removeCards: ([Screenshot]) -> Void = { _ in }
        var removeDrawings: ([URL], _ observedAt: TimeInterval) -> Void = { _, _ in }
        var removeReply: (URL) -> Void = { _ in }
        /// Drawings.sweep: removes the drawings of files a listing confirms absent.
        var sweepDrawings: (ScreenshotWatcher.Inventory) -> Void = { _ in }
        /// ScreenshotRequests.reconcile: marks published replies a listing confirms absent as removed.
        var reconcileRequests: (ScreenshotWatcher.Inventory) -> Void = { _ in }
        var rescan: (_ reason: String) -> Void = { _ in }
    }

    /// What `add` still owes a file it put in the watch folder, by file name. The watcher reports
    /// the file like a capture; this is what makes that report skip the capture toggles.
    private struct PendingAdd {
        var annotate = false
        /// The push's marks are still joining the screenshot's drawing. The presentation waits for
        /// it, so the annotator opens with them.
        var addingMarks = false
        /// The file, once there is something to present: the watcher's report, or the file itself
        /// when it was already in the folder and no report is coming.
        var waiting: Screenshot?
    }

    var callbacks = Callbacks()
    private var pendingAdds: [String: PendingAdd] = [:]
    /// When the app last put a file in the folder. A listing observed before it may not hold that
    /// file yet, so the removals it reports wait for a newer one.
    private var writtenAt: TimeInterval = 0
    private var deferredRemovals: Set<URL> = []
    /// Moves a file to the Trash; a test passes its own, so it never reaches the person's Trash.
    private let trashItem: (URL) throws -> Void
    private let now: () -> TimeInterval

    init(trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.trashItem = trash
        self.now = now
    }

    // MARK: Writes

    /// `add?file=<path>[&annotate][&agent=<name>][&session=<id>][&marks=<json>]`: a copy of an image
    /// from anywhere lands in the watch folder, where the watcher reports it like a capture;
    /// `pendingAdds` makes that report skip the capture toggles. `agent=` is recorded on the copy,
    /// which is what puts the badge on its card, and `session=` beside it, which is where Reply goes. `marks=` joins the screenshot's drawing before the card appears, so the
    /// user opens the agent's drawing and edits it like their own.
    func add(_ request: CommandRequest) {
        let watchFolder = callbacks.folder()
        guard let source = request.files.first else { Commands.error("add", .missingFile, "no file given"); return }
        guard FileManager.default.fileExists(atPath: source.path) else { Commands.error("add", .missingFile, source.path); return }
        guard Commands.isReadableImage(source) else { Commands.error("add", .unreadableImage, source.path); return }
        var marks: [AgentMark] = []
        if let value = request.marks {
            // Checked before anything is copied: a push with bad marks is one error line and no file.
            do { marks = try AgentMark.parse(value) } catch { Commands.error("add", .invalidMarks, "\(error)"); return }
        }
        let inFolder = Commands.policyError(for: source, watchFolder: watchFolder, debug: false) == nil
        var destination = source
        if !inFolder {
            guard ScreenshotWatcher.isCandidate(source.lastPathComponent) else {
                Commands.error("add", .unsupportedType, "\(source.lastPathComponent): needs a png, jpg, jpeg, or heic name without \(Config.annotatedSuffix)"); return
            }
            // `Agent reply <uuid>.png` is the one name Vignette writes itself. A copy landing on it
            // would have no reply record, and `isVisible` fails closed, so it would never be shown.
            guard ReplyProtocol.replyID(fromFileName: source.lastPathComponent) == nil else {
                Commands.error("add", .unsupportedType, "\(source.lastPathComponent): that name belongs to an agent reply"); return
            }
            destination = Commands.destination(for: source, in: watchFolder) { FileManager.default.fileExists(atPath: $0.path) }
        }
        let name = destination.lastPathComponent
        // Already in the folder means no watcher report is coming, so the file itself waits here.
        pendingAdds[name] = PendingAdd(annotate: request.annotate, addingMarks: !marks.isEmpty,
                                       waiting: inFolder ? Screenshot(url: destination) : nil)
        if !inFolder {
            do {
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                pendingAdds[name] = nil
                Commands.error("add", .writeFailed, "\(destination.path): \(error.localizedDescription)"); return
            }
        }
        writtenAt = now()
        if let agent = request.agent { Agent.record(agent, on: destination) }
        if let session = Agent.cleanSession(request.session) {
            Agent.record(session: session, on: destination)
        } else if !(request.session ?? "").isEmpty {
            // Not quoted: the value is the caller's, and the log is not a place for it.
            Log.write("[add] warning \(name): session= is not a session id; Reply on its card will ask where to send")
        }
        guard !marks.isEmpty else {
            presentAdd(name)
            Commands.ok("add", "\(name)\(inFolder ? " already in the watch folder" : "")\(detail(request))")
            return
        }
        callbacks.joinMarks(marks, request.agent, destination) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let joined):
                Commands.ok("add", "\(name)\(detail(request)) marks=\(joined)")
            case .failure(let failure):
                Commands.error("add", failure.code, "\(name): the image is in the folder, its marks are not: \(failure)")
            }
            pendingAdds[name]?.addingMarks = false
            presentAdd(name)
        }
    }

    /// The watcher reported `url`. True when it is a file `add` is waiting for, so it is not a capture.
    func arrived(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard pendingAdds[name] != nil else { return false }
        pendingAdds[name]?.waiting = Screenshot(url: url)
        presentAdd(name)   // waits when the push's marks are still joining its drawing
        return true
    }

    /// Writes a stitch without reserving its name, so the watcher reports it as a capture, which is
    /// how annotateOnCapture opens it. It records no write time.
    func writeStitch(_ png: Data, to url: URL) throws {
        try png.write(to: url)
    }

    /// Writes a live ink card as `<prefix> <date> at <time>.png`, its PNG made and written off the
    /// main thread, and answers its URL on the main thread, or nil when it could not be written. The
    /// name is reserved from the start, so the watcher's report skips the capture switches as an
    /// `add`'s does, and the card waits for `ready`. `from` is recorded on it as an `add`'s agent
    /// and session are, so it wears the agent's tab and Reply on it goes back to that session.
    func writeCard(named prefix: String, png: @escaping @Sendable () -> Data?, from destination: AgentDestination?,
                   done: @escaping (URL?) -> Void) {
        let url = Commands.destination(for: URL(fileURLWithPath: "\(prefix) \(Self.cardTime.string(from: Date())).png"),
                                       in: callbacks.folder()) {
            FileManager.default.fileExists(atPath: $0.path) || self.pendingAdds[$0.lastPathComponent] != nil
        }
        let name = url.lastPathComponent
        pendingAdds[name] = PendingAdd(annotate: false, addingMarks: true, waiting: nil)
        DispatchQueue.global(qos: .userInitiated).async {
            let written = png().map { (try? $0.write(to: url, options: .atomic)) != nil } ?? false
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard written else {
                        self.pendingAdds[name] = nil
                        Log.write("[live-ink] error write-failed \(name)")
                        return done(nil)
                    }
                    self.writtenAt = self.now()
                    if let destination {
                        Agent.record(destination.client.rawValue, on: url)
                        switch destination.address {
                        case .claudeSession(let session): Agent.record(session: session, on: url)
                        case .codexThread(let uuid): Agent.record(thread: uuid, on: url)
                        }
                    }
                    done(url)
                }
            }
        }
    }

    /// A card from `writeCard` owes nothing more: it is shown once the watcher has reported it.
    func ready(_ url: URL) {
        let name = url.lastPathComponent
        pendingAdds[name]?.addingMarks = false
        presentAdd(name)
    }

    /// Takes back a card from `writeCard` that will not be shown: its file and its drawing.
    func takeBack(_ url: URL) {
        pendingAdds[url.lastPathComponent] = nil
        try? FileManager.default.removeItem(at: url)
        callbacks.removeDrawings([url], .infinity)
    }

    private static let cardTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    /// A reply ScreenshotRequests has written and published: its card comes up.
    func published(_ reply: Screenshot) {
        writtenAt = now()
        callbacks.showCard(reply)
    }

    /// Shows the added file once nothing is owed on it: the watcher has reported it and its marks,
    /// if any, are in its stored drawing.
    private func presentAdd(_ name: String) {
        guard let pending = pendingAdds[name], !pending.addingMarks, let shot = pending.waiting else { return }
        pendingAdds[name] = nil
        callbacks.present(shot, pending.annotate)
    }

    /// What an `[add] ok` line says about the request beyond the file name.
    private func detail(_ request: CommandRequest) -> String {
        (request.annotate ? " annotate" : "") + (request.agent.map { " agent=\($0)" } ?? "")
            + (Agent.cleanSession(request.session).map { " session=\($0)" } ?? "")
    }

    // MARK: Removals

    func trash(_ shots: [Screenshot]) {
        var trashed: [Screenshot] = []
        var failed: [String] = []
        for shot in shots {
            do {
                try trashItem(shot.url)
                trashed.append(shot)
            } catch {
                failed.append("\(shot.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !trashed.isEmpty { left(trashed, observedAt: .infinity) }
        if failed.isEmpty { Commands.ok("trash", trashed.map(\.url.lastPathComponent).joined(separator: ", ")) }
        else { Commands.error("trash", .writeFailed, "\(failed.joined(separator: "; ")); trashed \(trashed.count) of \(shots.count)") }
    }

    /// The watcher's report that `urls` left the folder, from `inventory`.
    func removed(_ urls: [URL], in inventory: ScreenshotWatcher.Inventory) {
        guard writtenAt <= inventory.observedAt else {
            deferredRemovals.formUnion(urls)
            return
        }
        let removed = urls.filter { inventory.confirmsAbsence(of: $0) }
        if removed.count != urls.count {
            // The watcher already advanced its inventory. Keep suppressed removals until a
            // later listing observes their presence or confirms their absence.
            deferredRemovals.formUnion(Set(urls).subtracting(removed))
            callbacks.rescan("after an unconfirmed removal")
        }
        guard !removed.isEmpty else { return }
        Log.write("[watcher] removed \(removed.map(\.lastPathComponent).joined(separator: ", "))")
        left(removed.map(Screenshot.init), observedAt: inventory.observedAt)
    }

    /// A listing of the folder: it settles the removals held back for one.
    func listed(_ inventory: ScreenshotWatcher.Inventory) {
        guard writtenAt <= inventory.observedAt else {
            callbacks.rescan("after an app write")
            return
        }
        callbacks.sweepDrawings(inventory)
        callbacks.reconcileRequests(inventory)
        // The two calls above already removed the drawings and replies of the files this listing
        // confirms absent, so a held-back removal takes only its card.
        let deferred = deferredRemovals.filter { inventory.confirmsAbsence(of: $0) }
        if !deferred.isEmpty { callbacks.removeCards(deferred.map(Screenshot.init)) }
        deferredRemovals = deferredRemovals.filter {
            $0.deletingLastPathComponent().standardizedFileURL != inventory.folder.standardizedFileURL
                || (!inventory.names.contains($0.lastPathComponent) && !deferred.contains($0))
        }
    }

    /// Files gone from the folder: their cards, their drawings and any reply records go with them.
    private func left(_ shots: [Screenshot], observedAt: TimeInterval) {
        callbacks.removeCards(shots)
        callbacks.removeDrawings(shots.map(\.url), observedAt)
        for shot in shots { callbacks.removeReply(shot.url) }
    }
}
