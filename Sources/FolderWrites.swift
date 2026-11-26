import Foundation

/// What Vignette itself puts into the screenshots folder and takes out of it: an agent's push
/// (`add`), a stitch, a published reply, and the trash. It holds back removals the watcher reports
/// from a listing older than the app's last write, and tells the cards, the drawings and the
/// requests when a file has left.
@MainActor
final class FolderWrites {
    typealias Rename = (from: ScreenshotKey, to: ScreenshotKey)

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

    /// A file `trash` moved to the Trash: where it was, and where the Trash put it.
    struct Trashed {
        let shot: Screenshot
        let inTrash: URL
    }

    var callbacks = Callbacks()
    private var pendingAdds: [ScreenshotKey: PendingAdd] = [:]
    /// Files `putBack` returned to the folder whose watcher report is still to come. Their cards are
    /// already back in place, so the report is neither a capture nor a new card.
    private var pendingPutBacks: Set<ScreenshotKey> = []
    /// When the app last put a file in the folder. A listing observed before it may not hold that
    /// file yet, so the removals it reports wait for a newer one.
    private var writtenAt: TimeInterval = 0
    private var deferredRemovals: Set<ScreenshotKey> = []
    private var deferredRenames: [Rename] = []
    /// Moves a file to the Trash and answers where it went; a test passes its own, so it never
    /// reaches the person's Trash.
    private let trashItem: (URL) throws -> URL
    let now: () -> TimeInterval

    init(trash: @escaping (URL) throws -> URL = FolderWrites.moveToTrash,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.trashItem = trash
        self.now = now
    }

    // MARK: Writes

    /// `add?file=<path>[&annotate][&agent=<name>][&session=<id>][&marks=<json>][&title=…][&description=…]`: a copy of an image
    /// from anywhere lands in the watch folder, where the watcher reports it like a capture;
    /// `pendingAdds` makes that report skip the capture toggles. `agent=` is recorded on the copy,
    /// which is what puts the badge on its card, and `session=` beside it, which is where Reply goes, and `title=` and `description=` beside them. `marks=` joins the screenshot's drawing before the card appears, so the
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
        guard !inFolder || Agent.of(source) != nil else {
            Commands.error("add", .unsupportedType, "\(source.lastPathComponent) is the user's own screenshot; vignette://show points them at it"); return
        }
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
        let origin = Agent.pushOrigin(agent: request.agent, session: request.session)
        let title = recordAgent(of: request, origin: origin, on: key, at: destination)
        // The agent saw the drawing only when the file had none before this push.
        let agentsDrawing = origin != nil && (callbacks.storedDrawing(key)?.isEmpty ?? true)
        guard !marks.isEmpty else {
            recordSentDrawing(of: key, at: destination, agentsDrawing)
            presentAdd(key)
            Commands.ok("add", "\(name)\(inFolder ? " already in the watch folder" : "")\(detail(request, origin, titled: title.value != nil))")
            return
        }
        callbacks.joinMarks(marks, request.agent, key) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let joined):
                recordSentDrawing(of: key, at: destination, agentsDrawing)
                Commands.ok("add", "\(name)\(detail(request, origin, titled: title.value != nil)) marks=\(joined)")
            case .failure(let failure):
                Agent.forgetSentDrawing(on: destination)
                Commands.error("add", failure.code, "\(name): the image is in the folder, its marks are not: \(failure)")
            }
            pendingAdds[key]?.addingMarks = false
            presentAdd(key)
        }
    }

    /// Records the drawing a push that names its session sent, so Reply can tell the person changed
    /// nothing. Not for a file already drawn on, whose marks, the agent's included, the person may
    /// have moved since.
    private func recordSentDrawing(of key: ScreenshotKey, at url: URL, _ agentsDrawing: Bool) {
        if agentsDrawing { Agent.record(sentDrawing: callbacks.storedDrawing(key), on: url) } else { Agent.forgetSentDrawing(on: url) }
    }

    /// The watcher reported `key`. True when it is a file `add` is waiting for or one `putBack`
    /// returned, so it is not a capture.
    func arrived(_ key: ScreenshotKey) -> Bool {
        if pendingPutBacks.remove(key) != nil { return true }
        guard pendingAdds[key] != nil else { return false }
        pendingAdds[key]?.waiting = Screenshot(key: key)
        presentAdd(key)   // waits when the push's marks are still joining its drawing
        return true
    }

    /// Writes a stitch without reserving its name, so the watcher reports it as a capture, which is
    /// how annotateOnCapture opens it. It records no write time. A name already taken gets a counter,
    /// as an `add` does, and answers the file it wrote.
    func writeStitch(_ png: Data, in folder: URL, as name: String) throws -> ScreenshotKey {
        let named = Commands.destination(for: URL(fileURLWithPath: name), in: folder) { FileManager.default.fileExists(atPath: $0.path) }
        try png.write(to: named, options: .withoutOverwriting)
        return ScreenshotKey(folder: folder, name: named.lastPathComponent)
    }

    /// Writes a live ink card as `<prefix> <date> at <time>.png`, its PNG made and written off the
    /// main thread, and answers its screenshot on the main thread, or nil when it could not be
    /// written. The name is reserved from the start, so the watcher's report skips the capture
    /// switches as an `add`'s does, and the card waits for `ready`. `from` is recorded on it as an
    /// `add`'s agent and session are, so it wears the agent's tab and Reply on it goes back to that session.
    func writeCard(named prefix: String, png: @escaping @Sendable () -> Data?, from destination: AgentDestination?,
                   done: @escaping (Screenshot?) -> Void) {
        let folder = callbacks.folder()
        let named = Commands.destination(for: URL(fileURLWithPath: "\(prefix) \(Self.cardTime.string(from: Date())).png"), in: folder) {
            FileManager.default.fileExists(atPath: $0.path) || self.pendingAdds[ScreenshotKey(folder: folder, name: $0.lastPathComponent)] != nil
        }
        let shot = Screenshot(key: ScreenshotKey(folder: folder, name: named.lastPathComponent))
        let (key, url) = (shot.key, shot.url)
        pendingAdds[key] = PendingAdd(annotate: false, addingMarks: true, waiting: nil)
        DispatchQueue.global(qos: .userInitiated).async {
            let written = png().map { (try? $0.write(to: url, options: .atomic)) != nil } ?? false
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard written else {
                        self.pendingAdds[key] = nil
                        Log.write("[live-ink] error write-failed \(key.name)")
                        return done(nil)
                    }
                    self.writtenAt = self.now()
                    if let destination { Agent.record(agent: destination.address.client.rawValue, origin: destination.address, on: url) }
                    done(shot)
                }
            }
        }
    }

    /// A card from `writeCard` owes nothing more: it is shown once the watcher has reported it.
    func ready(_ shot: Screenshot) {
        pendingAdds[shot.key]?.addingMarks = false
        presentAdd(shot.key)
    }

    /// Takes back a card from `writeCard` that will not be shown: its file and its drawing.
    func takeBack(_ shot: Screenshot) {
        pendingAdds[shot.key] = nil
        try? FileManager.default.removeItem(at: shot.url)
        callbacks.removeDrawings([shot.key], .infinity)
    }

    /// A card from `writeCard` that was shown and is taken back: its file, its drawing and its card
    /// go now. `takeBack` is for a card not shown yet.
    func discard(_ shot: Screenshot) {
        pendingAdds[shot.key] = nil
        try? FileManager.default.removeItem(at: shot.url)
        left([shot], observedAt: .infinity)
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
    private func presentAdd(_ key: ScreenshotKey) {
        guard let pending = pendingAdds[key], !pending.addingMarks, let shot = pending.waiting else { return }
        pendingAdds[key] = nil
        callbacks.present(shot, pending.annotate)
    }

    /// What an `[add] ok` line says about the request beyond the file name.
    private func detail(_ request: CommandRequest, _ origin: AgentAddress?, titled: Bool) -> String {
        (request.annotate ? " annotate" : "") + (request.agent.map { " agent=\($0)" } ?? "") + (titled ? " title" : "")
            + (request.from != nil && request.agent != nil ? " from" : "") + (origin.map { " session=\($0.id)" } ?? "")
    }

    // MARK: Removals

    nonisolated static func moveToTrash(_ url: URL) throws -> URL {
        var inTrash: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &inTrash)
        guard let inTrash else { throw CocoaError(.fileNoSuchFile) }
        return inTrash as URL
    }

    /// Moves the files to the Trash, and answers the ones that went with where each went.
    @discardableResult
    func trash(_ shots: [Screenshot]) -> [Trashed] {
        var trashed: [Trashed] = []
        var failed: [String] = []
        for shot in shots {
            do {
                trashed.append(Trashed(shot: shot, inTrash: try trashItem(shot.url)))
            } catch {
                failed.append("\(shot.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !trashed.isEmpty { left(trashed.map(\.shot), observedAt: .infinity) }
        if failed.isEmpty { Commands.ok("trash", trashed.map(\.shot.url.lastPathComponent).joined(separator: ", ")) }
        else { Commands.error("trash", .writeFailed, "\(failed.joined(separator: "; ")); trashed \(trashed.count) of \(shots.count)") }
        return trashed
    }

    /// Moves files `trash` moved to the Trash back to where they were. A file
    /// no longer in the Trash, or whose name in the folder is taken, stays where it is. Answers the
    /// files that came back, and why each other one did not.
    func putBack(_ trashed: [Trashed]) -> (back: [Screenshot], failed: [String]) {
        var back: [Screenshot] = []
        var failed: [String] = []
        for item in trashed {
            let name = item.shot.url.lastPathComponent
            guard !FileManager.default.fileExists(atPath: item.shot.url.path) else {
                failed.append("\(name): a file by that name is in the folder"); continue
            }
            do {
                try FileManager.default.moveItem(at: item.inTrash, to: item.shot.url)
            } catch {
                failed.append("\(name): \(error.localizedDescription)"); continue
            }
            pendingPutBacks.insert(item.shot.key)
            writtenAt = now()
            back.append(item.shot)
        }
        return (back, failed)
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
        let deferred = deferredRemovals.filter { inventory.confirmsAbsence(of: $0.url) }
        if !deferred.isEmpty { left(deferred.map(Screenshot.init(key:)), observedAt: inventory.observedAt) }
        let folder = inventory.folder.standardizedFileURL
        deferredRemovals = deferredRemovals.filter {
            $0.url.deletingLastPathComponent().standardizedFileURL != folder
                || (!inventory.names.contains($0.name) && !deferred.contains($0))
        }
    }

    /// Files gone from the folder: their cards, their drawings and any reply records go with them.
    private func left(_ shots: [Screenshot], observedAt: TimeInterval) {
        for shot in shots { pendingPutBacks.remove(shot.key) }
        callbacks.removeCards(shots)
        callbacks.removeDrawings(shots.map(\.key), observedAt)
        for shot in shots { callbacks.fileRemoved(shot) }
    }
}
