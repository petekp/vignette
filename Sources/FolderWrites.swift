import Foundation

/// What Vignette itself puts into the screenshots folder and takes out of it: an agent's push
/// (`add`), a stitch, a published reply, and the trash. It holds back removals the watcher reports
/// from a listing older than the app's last write, and tells the cards, the drawings and the
/// requests when a file has left.
@MainActor
final class FolderWrites {
    typealias Rename = (from: ScreenshotKey, to: ScreenshotKey)

    struct Callbacks {
        /// The watch folder, as AppDelegate reads it from the settings.
        var folder: () -> URL = { FileManager.default.temporaryDirectory }
        /// Shows an added file's card, or opens it in the editor when `annotate` (AppDelegate.present).
        var present: (Screenshot, _ annotate: Bool) -> Void = { _, _ in }
        /// Shows a published reply's card. A reply never goes through `present`, which treats a file as a capture.
        var showCard: (Screenshot) -> Void = { _ in }
        /// Agents' marks joining the screenshot's drawing; answers with how many joined.
        var joinMarks: ([AgentMark], _ agent: String?, ScreenshotKey, @escaping (Result<Int, Drawings.Failure>) -> Void) -> Void = { _, _, _, done in
            done(.failure(Drawings.Failure(code: .writeFailed, description: "nothing stores drawings")))
        }
        var removeCards: ([Screenshot]) -> Void = { _ in }
        var removeDrawings: ([ScreenshotKey], _ observedAt: TimeInterval) -> Void = { _, _ in }
        var removeReply: (URL) -> Void = { _ in }
        /// Files renamed inside the folder: their cards keep their place and selection and take the new file.
        var renameCards: ([Rename]) -> Void = { _ in }
        /// Files renamed inside the folder: their stored drawings, and the one open in the editor, follow.
        var renameDrawings: ([Rename]) -> Void = { _ in }
        /// Files renamed inside the folder: the request and reply records that name them follow.
        var renameRequests: ([Rename]) -> Void = { _ in }
        /// ScreenshotRequests.isVisible: whether every listing shows a file by that name.
        var isVisible: (URL) -> Bool = { _ in true }
        /// Drawings.sweep: removes the drawings of files a listing confirms absent.
        var sweepDrawings: (ScreenshotWatcher.Inventory) -> Void = { _ in }
        /// ScreenshotRequests.reconcile: marks published replies a listing confirms absent as removed.
        var reconcileRequests: (ScreenshotWatcher.Inventory) -> Void = { _ in }
        var rescan: (_ reason: String) -> Void = { _ in }
    }

    /// What `add` still owes a file it put in the watch folder, by its key. The watcher reports
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
    private var pendingAdds: [ScreenshotKey: PendingAdd] = [:]
    /// When the app last put a file in the folder. A listing observed before it may not hold that
    /// file yet, so the removals it reports wait for a newer one.
    private var writtenAt: TimeInterval = 0
    private var deferredRemovals: Set<ScreenshotKey> = []
    private var deferredRenames: [Rename] = []
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
        // A file already in the folder may be in a subfolder of it, which its name alone would drop.
        let key = ScreenshotKey(resolving: destination, in: watchFolder) ?? ScreenshotKey(folder: watchFolder, name: name)
        // Already in the folder means no watcher report is coming, so the file itself waits here.
        pendingAdds[key] = PendingAdd(annotate: request.annotate, addingMarks: !marks.isEmpty,
                                       waiting: inFolder ? Screenshot(key: key) : nil)
        if !inFolder {
            do {
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                pendingAdds[key] = nil
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
            presentAdd(key)
            Commands.ok("add", "\(name)\(inFolder ? " already in the watch folder" : "")\(detail(request))")
            return
        }
        callbacks.joinMarks(marks, request.agent, key) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let joined):
                Commands.ok("add", "\(name)\(detail(request)) marks=\(joined)")
            case .failure(let failure):
                Commands.error("add", failure.code, "\(name): the image is in the folder, its marks are not: \(failure)")
            }
            pendingAdds[key]?.addingMarks = false
            presentAdd(key)
        }
    }

    /// The watcher reported `key`. True when it is a file `add` is waiting for, so it is not a capture.
    func arrived(_ key: ScreenshotKey) -> Bool {
        guard pendingAdds[key] != nil else { return false }
        pendingAdds[key]?.waiting = Screenshot(key: key)
        presentAdd(key)   // waits when the push's marks are still joining its drawing
        return true
    }

    /// Writes a stitch without reserving its name, so the watcher reports it as a capture, which is
    /// how annotateOnCapture opens it. It records no write time.
    func writeStitch(_ png: Data, to url: URL) throws {
        try png.write(to: url)
    }

    /// A reply ScreenshotRequests has written and published: its card comes up.
    func published(_ reply: Screenshot) {
        writtenAt = now()
        callbacks.showCard(reply)
    }

    /// Shows the added file once nothing is owed on it: the watcher has reported it and its marks,
    /// if any, are in its stored drawing.
    private func presentAdd(_ key: ScreenshotKey) {
        guard let pending = pendingAdds[key], !pending.addingMarks, let shot = pending.waiting else { return }
        pendingAdds[key] = nil
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

    /// The watcher's report that `keys` left the folder, from `inventory`.
    func removed(_ keys: [ScreenshotKey], in inventory: ScreenshotWatcher.Inventory) {
        guard writtenAt <= inventory.observedAt else {
            deferredRemovals.formUnion(keys)
            return
        }
        let removed = keys.filter { inventory.confirmsAbsence(of: $0.url) }
        if removed.count != keys.count {
            // The watcher already advanced its inventory. Keep suppressed removals until a
            // later listing observes their presence or confirms their absence.
            deferredRemovals.formUnion(Set(keys).subtracting(removed))
            callbacks.rescan("after an unconfirmed removal")
        }
        guard !removed.isEmpty else { return }
        Log.write("[watcher] removed \(removed.map(\.name).joined(separator: ", "))")
        left(removed.map(Screenshot.init(key:)), observedAt: inventory.observedAt)
    }

    /// The watcher's report that files in `pairs` changed name, from `inventory`. A listing older than
    /// the app's last write holds them back for a newer one, like removals. The watcher reports a
    /// renamed file as neither a removal nor an arrival, so nothing else tells its card and drawing.
    func renamed(_ renames: [Rename], in inventory: ScreenshotWatcher.Inventory) {
        guard writtenAt <= inventory.observedAt else {
            deferredRenames += renames
            return
        }
        rename(renames, observedAt: inventory.observedAt)
    }

    private func rename(_ renames: [Rename], observedAt: TimeInterval) {
        // A new name every listing hides, an agent reply's with no record, leaves as a removal would.
        let visible = Dictionary(grouping: renames) { callbacks.isVisible($0.to.url) }
        if let hidden = visible[false] {
            Log.write("[watcher] removed \(hidden.map { "\($0.from.name), renamed to \($0.to.name)" }.joined(separator: "; "))")
            left(hidden.map { Screenshot(key: $0.from) }, observedAt: observedAt)
        }
        guard let renames = visible[true] else { return }
        Log.write("[watcher] renamed \(renames.map { "\($0.from.name) to \($0.to.name)" }.joined(separator: ", "))")
        callbacks.renameCards(renames)
        callbacks.renameDrawings(renames)
        callbacks.renameRequests(renames)
    }

    /// A listing of the folder: it settles the renames and removals held back for one.
    func listed(_ inventory: ScreenshotWatcher.Inventory) {
        guard writtenAt <= inventory.observedAt else {
            callbacks.rescan("after an app write")
            return
        }
        // Before the sweep, which would take the old name's drawing as the drawing of a file that is gone.
        let renames = deferredRenames
        deferredRenames = []
        rename(renames, observedAt: inventory.observedAt)
        callbacks.sweepDrawings(inventory)
        callbacks.reconcileRequests(inventory)
        // The two calls above already removed the drawings and replies of the files this listing
        // confirms absent, so a held-back removal takes only its card.
        let deferred = deferredRemovals.filter { inventory.confirmsAbsence(of: $0.url) }
        if !deferred.isEmpty { callbacks.removeCards(deferred.map(Screenshot.init(key:))) }
        let folder = inventory.folder.standardizedFileURL
        deferredRemovals = deferredRemovals.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL != folder
                || (!inventory.names.contains($0.name) && !deferred.contains($0))
        }
    }

    /// Files gone from the folder: their cards, their drawings and any reply records go with them.
    private func left(_ shots: [Screenshot], observedAt: TimeInterval) {
        callbacks.removeCards(shots)
        callbacks.removeDrawings(shots.map(\.key), observedAt)
        for shot in shots { callbacks.removeReply(shot.url) }
    }
}
