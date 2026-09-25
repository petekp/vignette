import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, Actions {
    static func main() {
        let app = NSApplication.shared
        AppLocation.offerMove()
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private var statusItem: NSStatusItem?
    private var watcher: ScreenshotWatcher?
    private var wakeObserver: Any?
    private var screenObserver: Any?
    private var hotKey: HotKey?
    private var pressDismissed = false      // the last hotkey press closed the stack
    private var holdTarget: Screenshot?     // the card focused at that press
    private var modifierTap: ModifierTap?
    private let thumbnail = ThumbnailController()
    private let annotator = AnnotationController()
    private let settingsWindow = SettingsWindowController()
    private let setupWindow = SetupWindowController()
    private lazy var debugPanel = DebugPanelController(previews: .init(
        thumbnail: { [weak self] in self?.openLast() },
        stack: { [weak self] in self?.toggleRecent() },
        toast: { [weak self] in self?.thumbnail.showFeedback("Copied 3 images") },
        annotator: { [weak self] in self?.annotateLast() }))
    private let settings = Settings.shared
    private var watchFolder: URL { settings.data.folderURL }
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
    private var pendingAdds: [String: PendingAdd] = [:]
    /// Sending drawings to agent sessions and taking their drawings back. See ScreenshotRequests.
    private let requests = ScreenshotRequests(root: Identity.applicationSupportURL.appendingPathComponent("requests"))

    func applicationDidFinishLaunching(_ notification: Notification) {
        replaceOlderInstances()
        AppLocation.ejectDiskImageIfAsked()
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = AppDelegate.makeMainMenu()
        let settingsSource = Settings.isOverridden ? " (VIGNETTE_SETTINGS)" : ""
        Log.writeLaunch("[app] launched \(BuildInfo.current.description) watching \(watchFolder.path) settings \(Settings.fileURL.path)\(settingsSource)")
        if let type = AppleScreencapture.string("type"), !ScreenshotWatcher.isCandidate("screenshot.\(type)") {
            Log.write("[settings] warning Apple screencapture type=\(type) is a format the watcher ignores")
        }
        updateStatusItem()
        // It records the frontmost app from the moment it exists, which has to be before the first
        // window of ours can take the focus.
        _ = FocusReturn.shared
        thumbnail.actions = self
        thumbnail.onAnnotatorPrepare = { [weak self] shot, frame, room in
            guard let self else { return }
            self.annotator.prepare(shot, in: frame, room: room)
            self.refreshDestinations(for: shot)
        }
        annotator.onFrame = { [weak self] frame in self?.thumbnail.annotatorFrameMoved(frame) }
        thumbnail.onAnnotatorShow = { [weak self] in self?.annotator.show() }
        thumbnail.onAnnotatorLanded = { [weak self] in self?.annotator.landed() }
        thumbnail.annotatorBelow = { [weak self] in self?.annotator.spaceBelow ?? 0 }
        thumbnail.annotatorMarks = { [weak self] in self?.annotator.editor.marks }
        thumbnail.onAnnotatorHide = { [weak self] hidden in self?.annotator.hide { hidden() } }
        thumbnail.onAnnotatorAbandon = { [weak self] in self?.annotator.abandon() }
        thumbnail.onAnnotatorPress = { [weak self] event, key in self?.annotator.take(event, for: key) }
        annotator.onTakesEvents = { [weak self] key in self?.thumbnail.annotatorTakesEvents(key) }
        annotator.onFinished = { [weak self] shot, drawing in self?.finishAnnotation(shot, drawing) }
        annotator.onClosed = { [weak self] in self?.thumbnail.annotationEnded() }
        annotator.onLoaded = { [weak self] key in self?.thumbnail.editorLoaded(key) }
        annotator.storedDrawing = { [weak self] url, pixels in
            guard let self else { return nil }
            return drawings.read(url, pixels: pixels, style: settings.data.ui.textStyle)
        }
        annotator.onDrawing = { [weak self] drawing, reason in self?.drawings.write(drawing, reason: reason) }
        annotator.onSend = { [weak self] shot, drawing, destination in self?.sendDrawing(drawing, of: shot, to: destination) }
        annotator.onCopyDrawing = { [weak self] shot, drawing in self?.copyDrawing(drawing, of: shot) }
        thumbnail.dragItems = { [weak self] cards in self?.dragItems(cards) ?? [] }
        settingsWindow.callbacks = SettingsWindowController.Callbacks(
            restoreAppleDefaults: { [weak self] in self?.restoreAppleDefaults() },
            openTweaks: { [weak self] in self?.debugPanel.toggle() },
            installAgentSkill: { [weak self] root in self?.installAgentSkill(into: [root]) },
            removeAgentSkill: { [weak self] root in self?.removeAgentSkill(from: [root]) })
        // Before the watcher, so a capture taken during launch already lands the way Vignette needs.
        settings.reconcileApple()
        startDrawings()
        startRequests()
        startWatching()
        registerHotKey()
        settings.onChange = { [weak self] old, new in self?.settingsChanged(old, new) }
        if let notice = settings.startupNotice { thumbnail.showFeedback(notice) }
        // Setup comes first and has the launch to itself: two windows competing for a first-time
        // user is worse than the skill offer waiting until the next launch.
        if setupWindow.isUnasked {
            // The login item waits for the window to close, which applies the switch it shows.
            setupWindow.show(hasScreenshots: { [weak self] in self?.hasScreenshots ?? false },
                             folderDenied: { [weak self] in self?.watcher?.isDenied ?? false })
        } else {
            // The setting is the user's wish; macOS may have lost the registration (the app moved) or kept one the file no longer asks for.
            LoginItem.apply(settings.data.launchAtLogin)
            startAgentSkill()
        }
        // The contract for agents: after this line every command answers.
        Log.write("[app] ready pid=\(ProcessInfo.processInfo.processIdentifier) build=\(BuildInfo.current.build) watching=\(watchFolder.path)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        annotator.storeForQuit()
        settings.flush()
        Log.write("[app] terminating pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    /// The newer launch wins: any running copy of this bundle id is asked to quit, and forced after
    /// a grace period. Two copies would both watch the folder, write settings, and register the hotkey.
    private func replaceOlderInstances() {
        let me = ProcessInfo.processInfo.processIdentifier
        let older = NSRunningApplication.runningApplications(withBundleIdentifier: Identity.bundleID).filter { $0.processIdentifier != me }
        guard !older.isEmpty else { return }
        for app in older {
            Log.write("[app] replacing older instance pid=\(app.processIdentifier)")
            app.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            for app in older where !app.isTerminated {
                Log.write("[app] older instance pid=\(app.processIdentifier) did not quit; forcing")
                app.forceTerminate()
            }
        }
    }

    private func settingsChanged(_ old: SettingsData, _ new: SettingsData) {
        if new.ui != old.ui { thumbnail.applyTweaks(); annotator.applyTweaks(); warmThumbnails() }
        if new.recentCount != old.recentCount { warmThumbnails() }
        if new.screenshotsFolder != old.screenshotsFolder { startWatching() }
        if new.recentHotkey != old.recentHotkey { registerHotKey() }
        if new.hideMenuBarIcon != old.hideMenuBarIcon { updateStatusItem() }
        if new.launchAtLogin != old.launchAtLogin { LoginItem.apply(new.launchAtLogin) }
    }

    // MARK: The agent skill

    /// Launch: the offer if it has never been made, and a fresh copy of the skill for every agent
    /// that already has one. Nothing is installed where there is none and nothing is removed — disk
    /// is the truth, and putting the skill there or taking it away is the user's to ask for.
    private func startAgentSkill() {
        if settings.data.agentSkillChoice == .unasked { offerAgentSkill() }
        let existing = SkillInstaller.roots(home: FileManager.default.homeDirectoryForCurrentUser)
            .filter { SkillInstaller.state(of: $0) == .installed }
        if !existing.isEmpty { installAgentSkill(into: existing) }
    }

    /// The Agents tab's Install, and `install-skill`.
    @discardableResult
    func installAgentSkill(into roots: [URL]) -> [SkillInstaller.Result] {
        guard let source = SkillInstaller.bundled else {
            Log.write("[skill] error missing-file \(SkillInstaller.skillName) is not in the bundle"); return []
        }
        return report(SkillInstaller.install(source: source, into: roots), verb: "install")
    }

    /// The Agents tab's Remove.
    @discardableResult
    func removeAgentSkill(from roots: [URL]) -> [SkillInstaller.Result] {
        report(SkillInstaller.remove(from: roots), verb: "remove")
    }

    /// One line for everything that changed, and a toast for everything that failed. A launch with
    /// every copy already current says nothing.
    @discardableResult
    private func report(_ results: [SkillInstaller.Result], verb: String) -> [SkillInstaller.Result] {
        for result in results where ![.unchanged, .absent].contains(result.outcome) {
            Log.write("[skill] \(result.outcome.rawValue) \(result.path.path)\(result.detail.isEmpty ? "" : " \(result.detail)")")
        }
        for result in results where result.outcome == .failed {
            thumbnail.showFeedback("Couldn't \(verb) the skill for \(SkillInstaller.agentName(of: result.root))")
        }
        return results
    }

    /// The offer, once: the app has never asked and this Mac has an agent directory. The offer is
    /// the Settings window, since the toast carries no button, and the answer is the buttons in it.
    /// Recorded as `off` as it is made, so the question is asked once whatever the user does.
    private func offerAgentSkill() {
        let roots = SkillInstaller.roots(home: FileManager.default.homeDirectoryForCurrentUser)
        guard !roots.isEmpty else { return }
        settings.update { $0.agentSkill = AgentSkill.off.rawValue }
        Log.write("[skill] offered \(roots.map(\.lastPathComponent).joined(separator: " "))")
        settingsWindow.show(tab: .agents, activating: false)
    }

    /// Where the skill is sitting right now, for the state report. Two agents reaching one folder
    /// name it once.
    private func installedSkillPaths() -> [String] {
        var paths: [String] = []
        for root in SkillInstaller.roots(home: FileManager.default.homeDirectoryForCurrentUser)
        where SkillInstaller.state(of: root) == .installed {
            let path = SkillInstaller.destination(in: root).path
            if !paths.contains(path) { paths.append(path) }
        }
        return paths
    }

    /// `vignette://install-skill`, for a script: it installs for every agent on this Mac, or with
    /// `root=` into that one directory. It writes no setting; the skill's own presence on disk is
    /// what a later launch reads.
    private func installSkill(_ request: CommandRequest) {
        if let root = request.root, !settings.data.debug {
            Commands.error("install-skill", .debugDisabled, "root=\(root.path) needs \"debug\": true in settings.json"); return
        }
        guard SkillInstaller.bundled != nil else {
            Commands.error("install-skill", .missingFile, "\(SkillInstaller.skillName) is not in the bundle"); return
        }
        let roots = request.root.map { [$0] } ?? SkillInstaller.roots(home: FileManager.default.homeDirectoryForCurrentUser)
        guard !roots.isEmpty else {
            Commands.error("install-skill", .noAgent, "no \(SkillInstaller.agentDirectories.joined(separator: " or ")) in this home folder"); return
        }
        let results = installAgentSkill(into: roots)
        let detail = results.map { "\($0.path.path)=\($0.outcome.rawValue)" }.joined(separator: " ")
        if let bad = results.first(where: { $0.outcome == .failed }) {
            Commands.error("install-skill", .writeFailed, bad.detail.isEmpty ? detail : "\(detail) \(bad.detail)")
            return
        }
        Commands.ok("install-skill", detail)
    }

    private func registerHotKey() {
        hotKey = nil
        modifierTap = nil
        // The press toggles the stack. Holding on lifts a card out of it: the newest, or, when the
        // press closed an open stack, the focused one; the stack comes back first so it can leave from its slot.
        let fire = { [weak self] in
            guard let self else { return }
            Log.write("[hotkey] recent")
            NotificationCenter.default.post(name: .hotKeyFired, object: nil)
            let focused = thumbnail.focusedShot
            pressDismissed = pressRecent() == .dismissed
            holdTarget = pressDismissed ? focused : nil
        }
        let hold = { [weak self] in
            guard let self else { return }
            Log.write("[hotkey] hold")
            if pressDismissed { _ = pressRecent() }
            if let shot = holdTarget, shot.kind == .image { annotate([shot]) } else { annotateLast() }
        }
        switch HotKeySpec.parse(settings.data.recentHotkey) {
        case .key(let keyCode, let modifiers):
            hotKey = HotKey(keyCode: keyCode, modifiers: modifiers, action: fire, hold: hold)
        case .doubleTap(let keyCode):
            modifierTap = ModifierTap(keyCode: keyCode, action: fire, hold: hold)
        case nil:
            Log.write("[hotkey] cannot parse \"\(settings.data.recentHotkey)\"; no hotkey registered")
            return
        }
        Log.write("[hotkey] registered \(settings.data.recentHotkey)")
    }

    // MARK: Actions (see Config.actions). Lists arrive in selection order from the stack, else as the URL named them.

    func copyToClipboard(_ shots: [Screenshot]) {
        guard !shots.isEmpty else { Commands.error("copy", .missingFile, "nothing selected"); return }
        Clipboard.copyFiles(shots.map(\.url))
        Commands.ok("copy", shots.map(\.url.lastPathComponent).joined(separator: ", "))
        thumbnail.showCopied(shots)
    }

    func copyPaths(_ shots: [Screenshot]) {
        guard !shots.isEmpty else { Commands.error("paths", .missingFile, "nothing selected"); return }
        Clipboard.copyText(Clipboard.pathsText(shots.map(\.url)))
        Commands.ok("paths", shots.map(\.url.lastPathComponent).joined(separator: ", "))
        thumbnail.showCopied(shots, label: "Copied Path",
                             fallback: shots.count == 1 ? "Copied path" : "Copied \(shots.count) paths")
    }

    func annotate(_ shots: [Screenshot]) {
        guard let shot = shots.first else { Commands.error("annotate", .missingFile, "nothing selected"); return }
        if let recording = shots.first(where: { $0.kind == .recording }) {
            Commands.error("annotate", .unsupportedType, "\(recording.url.lastPathComponent) is a recording"); return
        }
        Commands.ok("annotate", shots.count > 1 ? "\(shot.url.lastPathComponent) 1 of \(shots.count)" : shot.url.lastPathComponent)
        thumbnail.annotate(shots)
    }

    /// The newest screenshot in the watch folder goes into the annotator, on screen or not. A newer
    /// recording is passed over: the hold and this menu item both promise drawing.
    @objc private func annotateLast() {
        guard let url = newestShot(where: { $0.kind == .image }) else {
            Commands.error("annotate", .missingFile, "no screenshot in \(watchFolder.path)"); return
        }
        annotate([Screenshot(url: url)])
    }

    /// Each piece carries its drawing into the stitch: the editor's own for the image open in it, as
    /// Copy Drawing does, else the stored one.
    func stitch(_ shots: [Screenshot]) {
        guard shots.count >= 2 else { Commands.error("stitch", .notEnoughFiles, "needs 2, got \(shots.count)"); return }
        let ui = settings.data.ui, style = ui.textStyle, arrowhead = ui.arrowhead, limit = ui.stitchLongSide
        let pieces = shots.map { shot in
            Stitch.Piece(url: shot.url, drawing: annotator.openDrawing(of: shot.url)
                ?? PixelSize(imageAt: shot.url).flatMap { drawings.read(shot.url, pixels: $0, style: style) })
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let composed = Stitch.compose(pieces, style: style, arrowhead: arrowhead, longSideLimit: limit)
            DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in self?.finishStitch(shots, composed) } }
        }
    }

    private func finishStitch(_ shots: [Screenshot], _ composed: Stitch.Composition?) {
        guard let composed else {
            Commands.error("stitch", .unreadableImage, shots.map(\.url.lastPathComponent).joined(separator: ", ")); return
        }
        // A file that would not decode is not in the picture, and one image is not a stitch.
        guard composed.pieces >= 2 else {
            Commands.error("stitch", .unreadableImage, "only \(composed.pieces) of \(shots.count) images could be read"); return
        }
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let out = watchFolder.appendingPathComponent("Stitch \(stamp.string(from: Date())).png")
        do { try composed.png.write(to: out) } catch { Commands.error("stitch", .writeFailed, "\(out.path): \(error.localizedDescription)"); return }
        Clipboard.copyFiles([out])
        // readerScale is what a vision model's resize leaves of the composition; see Stitch.swift.
        Commands.ok("stitch", "\(out.path) from \(composed.pieces) images, \(Int(composed.size.width))x\(Int(composed.size.height)) columns=\(composed.columns) readerScale=\(String(format: "%.2f", composed.readerScale)) \(composed.png.count) bytes, copied")
        // The cards conjoin into the new one when the stack is showing them; otherwise say so.
        if !thumbnail.stitched(shots, into: out) { thumbnail.showFeedback("Stitched \(composed.pieces) images, copied") }
    }

    // MARK: Drawings

    private lazy var drawings = Drawings(store: DrawingStore(directory: Identity.applicationSupportURL.appendingPathComponent("drawings")))

    /// Clears out what the web editor left, removes the drawings whose screenshot is gone, and gives
    /// the stack the drawings, so every card draws its own and a write reaches its card at once.
    private func startDrawings() {
        Drawings.removeWebEditorData([
            Identity.applicationSupportURL.appendingPathComponent("drafts"),
            Identity.cachesURL.appendingPathComponent("drafts"),
            Identity.cachesURL.appendingPathComponent("WebKit"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/WebKit/\(Identity.bundleID)"),
        ])
        thumbnail.drawings = drawings
        drawings.onChange = { [weak self] key, drawing in self?.thumbnail.setDrawing(drawing, for: key) }
        drawings.sweep(watchFolder: watchFolder) { FileManager.default.fileExists(atPath: $0) }
    }

    /// Agents' marks joining a screenshot's drawing: the one open in the editor, or the stored one.
    /// The colour pass's sample is made off the main thread first, and `done` answers once the
    /// drawing is written, with how many marks joined it. A new drawing takes the main screen's
    /// point scale, the best guess with no annotator open.
    private func addMarks(_ marks: [AgentMark], to url: URL, done: @escaping (Result<Int, Drawings.Failure>) -> Void) {
        Task {
            let sample = await Self.colorSample(of: url)
            do {
                done(.success(try drawings.add(marks, to: url, editor: annotator.editor, sample: sample, style: settings.data.ui.textStyle,
                                               newPointScale: (NSScreen.main ?? NSScreen.screens[0]).backingScaleFactor)))
            } catch let failure as Drawings.Failure {
                done(.failure(failure))
            } catch {
                done(.failure(Drawings.Failure(code: .writeFailed, description: "\(error)")))
            }
        }
    }

    private nonisolated static func colorSample(of url: URL) async -> ColorSample? {
        ColorSample(imageAt: url)
    }

    /// Where a screenshot's rendering is written: `<name>-annotated.png` beside it.
    private func annotatedURL(for shot: Screenshot) -> URL {
        let base = shot.url.deletingPathExtension().lastPathComponent
        return shot.url.deletingLastPathComponent().appendingPathComponent("\(base)\(Config.annotatedSuffix).png")
    }

    func open(_ shots: [Screenshot]) {
        guard !shots.isEmpty else { Commands.error("open", .missingFile, "nothing selected"); return }
        for shot in shots { NSWorkspace.shared.open(shot.url) }
        Commands.ok("open", shots.map(\.url.lastPathComponent).joined(separator: ", "))
    }

    func moveToTrash(_ shots: [Screenshot]) {
        var trashed: [String] = []
        var failed: [String] = []
        for shot in shots {
            do {
                try FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
                trashed.append(shot.url.lastPathComponent)
            } catch {
                failed.append("\(shot.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        thumbnail.remove(shots)
        drawings.remove(shots.map(\.url))
        if failed.isEmpty { Commands.ok("trash", trashed.joined(separator: ", ")) }
        else { Commands.error("trash", .writeFailed, "\(failed.joined(separator: "; ")); trashed \(trashed.count) of \(shots.count)") }
    }

    /// Copy Drawing: each card's drawing, rendered and written beside its screenshot, and the
    /// original file for a card without one. The card open in the editor renders the editor's own
    /// drawing, which is ahead of the stored one until the next hand-over. The queue renders these
    /// in the order asked, so once the last rendering is done every one is.
    func copyAnnotated(_ shots: [Screenshot]) {
        let ui = settings.data.ui, style = ui.textStyle
        let renderings = shots.map { shot -> (shot: Screenshot, rendering: PendingRendering?) in
            let drawing = annotator.openDrawing(of: shot.url)
                ?? PixelSize(imageAt: shot.url).flatMap { drawings.read(shot.url, pixels: $0, style: style) }
            guard let drawing, !drawing.marks.isEmpty else { return (shot, nil) }
            return (shot, RenderingQueue.shared.render(drawing, imageAt: shot.url, writingTo: annotatedURL(for: shot),
                                                       style: style, arrowhead: ui.arrowhead))
        }
        if let last = renderings.compactMap(\.rendering).last {
            last.whenDone { [weak self] _ in self?.finishCopyAnnotated(renderings) }
        } else {
            finishCopyAnnotated(renderings)
        }
    }

    private func finishCopyAnnotated(_ renderings: [(shot: Screenshot, rendering: PendingRendering?)]) {
        var urls: [URL] = []
        for (shot, rendering) in renderings {
            guard let rendering else { urls.append(shot.url); continue }
            let output = rendering.wait(timeout: 0)
            guard let file = output?.file else {
                let failure = output?.failure ?? .writeFailed("no rendering")
                Commands.error("copy-annotated", failure.code, "\(shot.url.lastPathComponent): \(failure)")
                thumbnail.showFeedback("Could not render the drawing; see the log")
                return
            }
            urls.append(file)
        }
        Clipboard.copyFiles(urls)
        let drawn = renderings.filter { $0.rendering != nil }.count
        Commands.ok("copy-annotated", "\(urls.map(\.lastPathComponent).joined(separator: ", ")); \(drawn) with annotations")
        thumbnail.showCopied(renderings.map(\.shot))
    }

    /// Done: the rendering goes on the clipboard at once as a promise and the card goes home; the
    /// file is written when the rendering finishes. With nothing drawn, the original file is copied.
    private func finishAnnotation(_ shot: Screenshot, _ drawing: Drawing) {
        copyRendering(of: drawing, shot: shot, verb: "done")
        // Quick annotate: the drawing was the point; nothing comes back.
        if settings.data.quickAnnotate { Log.write("[annotate] quick close") }
        thumbnail.annotationFinished(quick: settings.data.quickAnnotate)
    }

    /// Cmd+C in the editor with nothing selected: the same clipboard Done gives, and the editor stays open.
    private func copyDrawing(_ drawing: Drawing, of shot: Screenshot) {
        copyRendering(of: drawing, shot: shot, verb: "copied")
    }

    /// The annotated file on the clipboard as a file, an image, and its path as text, so a terminal
    /// pastes the path and a chat app pastes the image. The file is promised, so nothing waits for
    /// the rendering but a paste that comes before it, and the rendering goes ahead of any that has
    /// not started. `verb` names the moment in the log line.
    private func copyRendering(of drawing: Drawing, shot: Screenshot, verb: String) {
        let name = shot.url.lastPathComponent
        guard !drawing.marks.isEmpty else {
            Clipboard.copyFiles([shot.url])
            Log.write("[annotate] \(verb) \(name) nothing drawn, original copied")
            return
        }
        let file = annotatedURL(for: shot)
        let ui = settings.data.ui
        let rendering = RenderingQueue.shared.render(drawing, imageAt: shot.url, writingTo: file, style: ui.textStyle, arrowhead: ui.arrowhead,
                                                     order: .first)
        Clipboard.copyRendering(rendering, file: file)
        rendering.whenDone { [weak self] output in
            guard let self else { return }
            if let failure = output.failure {
                Log.write("[annotate] error \(failure.code.rawValue) \(name): \(failure)")
                // The clipboard took its promise back; the card must not say otherwise.
                let words = "Could not copy the drawing; see the log"
                thumbnail.takeBackCopied(shot)
                if !thumbnail.stackShowing, annotator.currentKey != nil { annotator.showToast(words) } else { thumbnail.showFeedback(words) }
            } else if let file = output.file, let png = output.png {
                Log.write("[annotate] \(verb) \(file.lastPathComponent) \(png.count) bytes, copied")
            }
        }
    }

    /// A drag out of the stack drops each card as it shows it: a card with a drawing drops the
    /// drawing, rendered from the moment the drag begins and written beside its screenshot, through
    /// the item Done's clipboard uses, and a card without one drops its file. The drawing is the
    /// editor's for the card open in it, which is ahead of the stored one until the next hand-over,
    /// and otherwise the card's own, which every write and removal reaches at once (`onChange`).
    /// In turn on the queue, so Done's promise keeps its bound: a drop comes after the pointer has
    /// travelled, which is time a paste does not have.
    private func dragItems(_ cards: [Card]) -> [NSPasteboardWriting] {
        let ui = settings.data.ui
        var drawn = 0
        let items = cards.map { card -> NSPasteboardWriting in
            let shot = card.shot, name = shot.url.lastPathComponent
            guard let drawing = annotator.openDrawing(of: shot.url) ?? card.marks?.drawing, !drawing.marks.isEmpty else {
                return shot.url as NSURL
            }
            drawn += 1
            let file = annotatedURL(for: shot)
            let rendering = RenderingQueue.shared.render(drawing, imageAt: shot.url, writingTo: file, style: ui.textStyle, arrowhead: ui.arrowhead)
            rendering.whenDone { output in
                if let failure = output.failure {
                    Log.write("[drag] error \(failure.code.rawValue) \(name): \(failure); the drop gets no image for it")
                } else if let file = output.file, let png = output.png {
                    Log.write("[drag] rendered \(file.lastPathComponent) \(png.count) bytes")
                }
            }
            return Clipboard.renderingItem(rendering, file: file)
        }
        Log.write("[drag] cards=\(cards.count) drawings=\(drawn)")
        return items
    }

    // MARK: URL commands: vignette://<command>[?file=/path&file=/other]. See Commands.swift.

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Log.write("[url] \(url.absoluteString)")
            run(Commands.parse(url))
        }
    }

    private func run(_ request: CommandRequest) {
        let cmd = request.name
        guard Commands.isKnown(cmd) else {
            Commands.error(cmd, .unknownCommand, "\"\(cmd)\"; open -g \(Identity.urlScheme)://help lists the commands"); return
        }
        if Commands.needsDebug(cmd) && !settings.data.debug {
            Commands.error(cmd, .debugDisabled, "set \"debug\": true in settings.json"); return
        }
        switch cmd {
        case "help":
            for line in Commands.helpLines() { Log.write("[help] \(line)") }
            Commands.ok("help", "\(Commands.fixed.count + Config.actions.count) commands; errors end with one of: \(CommandError.allCases.map(\.rawValue).joined(separator: " "))")
        case "last": openLast()
        case "add": addImage(request)
        case "recent": toggleRecent()
        case "state": dumpState(tag: request.tag)
        case "settings": settingsWindow.show(); Commands.ok("settings", "window opened")
        case "install-skill": installSkill(request)
        case "reply":
            guard let file = request.files.first else { Commands.error("reply", .missingFile, "no file given"); return }
            requests.receiveReply(envelope: file)
        case "requests": requests.run(clear: request.clear)
        case "restore-apple-defaults": restoreAppleDefaults()
        case "tweaks": debugPanel.toggle(); Commands.ok("tweaks")
        case "dismiss": thumbnail.dismiss(); Commands.ok("dismiss")
        case "cancel": Commands.ok("cancel", annotator.cancelForDebug() ? "" : "nothing was open")
        default:
            guard let action = Config.action(id: cmd) else { return }
            var targets = request.files
            if targets.isEmpty {
                // The newest file the action can take, so `annotate` passes over a newer recording
                // and `open` over newer screenshots.
                guard let newest = newestShot(where: { action.kinds.contains($0.kind) }) else {
                    Commands.error(cmd, .missingFile, "no file given and none it applies to in \(watchFolder.path)"); return
                }
                targets = [newest]
            }
            if !targets.allSatisfy({ action.kinds.contains(Screenshot(url: $0).kind) }),
               let reason = action.unavailableReason(for: targets.map(Screenshot.init)) {
                Commands.error(cmd, .unsupportedType, reason); return
            }
            for file in targets {
                if let code = Commands.policyError(for: file, watchFolder: watchFolder, debug: settings.data.debug) {
                    Commands.error(cmd, code, file.path); return
                }
                // A reserved reply is Vignette's own until its import commits: opening it would show
                // a drawing still missing its marks, and trashing it would delete the file the import
                // is about to draw on. The listings hide it; so does naming it.
                guard requests.isVisible(file) else {
                    Commands.error(cmd, .missingFile, "\(file.path): an agent reply that is not imported yet"); return
                }
            }
            guard targets.count >= action.minimumCount else {
                Commands.error(cmd, .notEnoughFiles, "needs \(action.minimumCount), got \(targets.count)"); return
            }
            if cmd == "annotate" {
                // Refused here, before any transition starts, so a dead file never opens an empty editor.
                if let bad = targets.first(where: { !Commands.isReadableImage($0) }) { Commands.error(cmd, .unreadableImage, bad.path); return }
            } else if let missing = targets.first(where: { !FileManager.default.fileExists(atPath: $0.path) }) {
                Commands.error(cmd, .missingFile, missing.path); return
            }
            action.run(targets.map(Screenshot.init), self)
        }
    }

    private func residentBytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }

    /// One `[state] {json}` line, written at once.
    private func dumpState(tag: String?) {
        var report = StateReport()
        report.sections = thumbnail.stateJSON
        report.sections["tag"] = tag as Any
        report.sections["app"] = [
            "pid": Int(ProcessInfo.processInfo.processIdentifier), "build": BuildInfo.current.build, "version": BuildInfo.current.version,
            "isActive": NSApp.isActive, "accessibility": ModifierTap.trusted(prompt: false),
            "watchFolder": watchFolder.path, "settingsFile": Settings.fileURL.path, "readOnly": settings.readOnly,
            "bundle": Bundle.main.bundlePath,
            "appleThumbnail": settings.data.appleThumbnail, "recentCount": settings.data.recentCount, "hotkey": settings.data.recentHotkey, "debug": settings.data.debug,
            "launchAtLogin": settings.data.launchAtLogin, "loginItem": LoginItem.status,
            "agentSkill": ["setting": settings.data.agentSkill, "installed": installedSkillPaths()] as [String: Any],
        ] as [String: Any]
        report.sections["annotator"] = annotator.stateJSON
        report.sections["editor"] = annotator.editor.core.inspection
        report.sections["drawings"] = drawings.keys.sorted()
        report.sections["requests"] = requests.stateJSON
        report.sections["memory"] = ["rss": residentBytes(), "thumbnails": Thumbnailer.cacheBytes]
        Log.write("[state] \(report.rendered())")
    }

    /// Accessory apps have no menu bar, but key equivalents like Cmd+W and Cmd+C in the Settings
    /// window still route through the main menu, so build a minimal one.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenuItem(); main.addItem(app)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Vignette", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = appMenu
        let file = NSMenuItem(); main.addItem(file)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.submenu = fileMenu
        let edit = NSMenuItem(); main.addItem(edit)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        return main
    }

    // MARK: Status item

    private func updateStatusItem() {
        if settings.data.hideMenuBarIcon {
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        // On a crowded menu bar macOS drops a new item into the space under the notch, where it is
        // invisible. Seed a spot near the right edge once; after that macOS remembers where the user drags it.
        let positionKey = "NSStatusItem Preferred Position \(Identity.statusItemAutosaveName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil { UserDefaults.standard.set(80, forKey: positionKey) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = NSStatusItem.AutosaveName(Identity.statusItemAutosaveName)
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        image?.accessibilityDescription = Identity.name
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let shortcut = HotKeySpec.parse(settings.data.recentHotkey)

        let recentItem = NSMenuItem(title: "Show Recent Screenshots", action: #selector(toggleRecent), keyEquivalent: "")
        // A status item's menu is not the main menu, so this key equivalent is live only while the
        // menu is open; the global press is the Carbon hotkey's.
        if let equivalent = shortcut?.menuKeyEquivalent {
            recentItem.keyEquivalent = equivalent.key
            recentItem.keyEquivalentModifierMask = equivalent.modifiers
        } else if let shortcut {
            recentItem.badge = NSMenuItemBadge(string: shortcut.label)
        }
        menu.addItem(recentItem)

        let drawItem = NSMenuItem(title: "Draw on Last Screenshot", action: #selector(annotateLast), keyEquivalent: "")
        if let shortcut { drawItem.badge = NSMenuItemBadge(string: "hold \(shortcut.label)") }
        menu.addItem(drawItem)

        menu.addItem(.separator())
        let copyItem = NSMenuItem(title: "Copy New Screenshots", action: #selector(toggleCopyOnCapture), keyEquivalent: "")
        copyItem.state = settings.data.copyOnCapture ? .on : .off
        menu.addItem(copyItem)
        let captureItem = NSMenuItem(title: "Draw on New Screenshots", action: #selector(toggleAnnotateOnCapture), keyEquivalent: "")
        captureItem.state = settings.data.annotateOnCapture ? .on : .off
        menu.addItem(captureItem)

        menu.addItem(.separator())
        let folderItem = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openScreenshotsFolder), keyEquivalent: "")
        folderItem.toolTip = (settings.data.folderURL.path as NSString).abbreviatingWithTildeInPath
        menu.addItem(folderItem)
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")

        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(openReleases), keyEquivalent: "")

        menu.addItem(.separator())
        if settings.data.debug {
            menu.addItem(.sectionHeader(title: "Developer"))
            menu.addItem(withTitle: "Tweak UI…", action: #selector(openTweaks), keyEquivalent: "")
            menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "")
            menu.addItem(withTitle: "Reveal settings.json", action: #selector(revealSettings), keyEquivalent: "")
            menu.addItem(.separator())
        }

        menu.addItem(withTitle: "Quit Vignette", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }

    /// Opens the releases page rather than comparing versions: the page names the latest version and
    /// carries the download, and the app has no updater to hand off to yet.
    @objc private func openReleases() {
        NSWorkspace.shared.open(Identity.releasesURL)
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc func restoreAppleDefaults() {
        guard let restored = settings.restoreAppleDefaults() else {
            Commands.error("restore-apple-defaults", .noAppleOriginal, "nothing was recorded, so nothing to restore")
            thumbnail.showFeedback("No Apple defaults were recorded")
            return
        }
        Commands.ok("restore-apple-defaults", restored.joined(separator: " "))
        thumbnail.showFeedback("Apple screenshot defaults restored")
    }

    @objc private func openTweaks() {
        debugPanel.toggle()
    }

    @objc private func openScreenshotsFolder() {
        NSWorkspace.shared.open(settings.data.folderURL)
    }

    @objc private func revealSettings() {
        NSWorkspace.shared.activateFileViewerSelecting([Settings.fileURL])
    }

    @objc private func toggleCopyOnCapture() {
        settings.update { $0.copyOnCapture.toggle() }
        Log.write("[settings] copyOnCapture=\(settings.data.copyOnCapture)")
    }

    @objc private func toggleAnnotateOnCapture() {
        settings.update { $0.annotateOnCapture.toggle() }
        Log.write("[settings] annotateOnCapture=\(settings.data.annotateOnCapture)")
    }

    @objc private func openLast() {
        guard let url = newestShot() else {
            Commands.error("last", .missingFile, "no screenshot in \(watchFolder.path)"); return
        }
        thumbnail.show(Screenshot(url: url))
        Commands.ok("last", url.lastPathComponent)
    }

    /// `add?file=<path>[&annotate][&agent=<name>][&session=<id>][&marks=<json>]`: a copy of an image
    /// from anywhere lands in the watch folder, where the watcher reports it like a capture;
    /// `pendingAdds` makes that report skip the capture toggles. `agent=` is recorded on the copy,
    /// which is what puts the badge on its card, and `session=` beside it, which is where Reply goes. `marks=` joins the screenshot's drawing before the card appears, so the
    /// user opens the agent's drawing and edits it like their own.
    private func addImage(_ request: CommandRequest) {
        guard let source = request.files.first else { Commands.error("add", .missingFile, "no file given"); return }
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
        addMarks(marks, to: destination) { [weak self] result in
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

    /// Shows the added file once nothing is owed on it: the watcher has reported it and its marks,
    /// if any, are in its stored drawing.
    private func presentAdd(_ name: String) {
        guard let pending = pendingAdds[name], !pending.addingMarks, let shot = pending.waiting else { return }
        pendingAdds[name] = nil
        present(shot, annotate: pending.annotate)
    }

    /// What an `[add] ok` line says about the request beyond the file name.
    private func detail(_ request: CommandRequest) -> String {
        (request.annotate ? " annotate" : "") + (request.agent.map { " agent=\($0)" } ?? "")
            + (Agent.cleanSession(request.session).map { " session=\($0)" } ?? "")
    }

    // MARK: Screenshot requests: Send, replies, and which files a reply owns. See ScreenshotRequests.

    /// Wires the coordinator and reads what is already on disk. Runs before the watcher starts and
    /// before anything warms the stack: until the reply records are loaded nothing knows which
    /// managed files are unfinished, and an unfinished one must never read as an ordinary capture.
    private func startRequests() {
        requests.connections = [.claude: ClaudeCodeConnection(),
                                .codex: CodexConnection()]
        requests.callbacks = ScreenshotRequests.Callbacks(
            addMarks: { [weak self] shot, marks, done in
                guard let self else { return done(Drawings.Failure(code: .writeFailed, description: "the app is gone")) }
                addMarks(marks, to: shot.url) { result in
                    if case .failure(let failure) = result { done(failure) } else { done(nil) }
                }
            },
            present: { [weak self] shot in self?.thumbnail.show(shot) },
            watchFolder: { [weak self] in self?.watchFolder ?? FileManager.default.temporaryDirectory },
            feedback: { [weak self] text in self?.thumbnail.showFeedback(text) })
        requests.load()
    }

    /// The newest screenshots a person may act on: the folder's, less any agent reply whose import
    /// has not committed. Every listing goes through here rather than through the index directly.
    private func recentShots(limit: Int, where fits: (Screenshot) -> Bool = { _ in true }) -> (recent: [URL], files: Int) {
        watcher?.recent(limit: limit, include: { [weak self] url in
            (self?.requests.isVisible(url) ?? true) && fits(Screenshot(url: url))
        }) ?? (recent: [], files: 0)
    }

    private func newestShot(where fits: (Screenshot) -> Bool = { _ in true }) -> URL? {
        recentShots(limit: 1, where: fits).recent.first
    }

    /// Whether anything is there to show. The count comes from the watcher's in-memory index, so
    /// this is cheap enough to ask every time the menu opens.
    private var hasScreenshots: Bool { recentShots(limit: 0).files > 0 }

    /// Where the bar can send while this image is open, and the session it came from: an agent's
    /// reply to a request, or a push that named its session. Reading the sessions runs
    /// subprocesses, so it answers later; the bar offers Send once it has a session to send to.
    private func refreshDestinations(for shot: Screenshot) {
        annotator.beginDestinations(replyTo: requests.origin(of: shot.url) ?? Agent.origin(of: shot.url))
        let asked = CACurrentMediaTime()
        requests.destinations { [weak self] found, complete in
            guard let self else { return }
            Log.write("[send] sessions \(found.count)\(complete ? " complete" : "") after=\(Int((CACurrentMediaTime() - asked) * 1000))ms \(shot.url.lastPathComponent)")
            // Listing the sessions runs subprocesses that can take seconds, so two images' answers
            // can arrive out of order. An answer for an image the editor has left would label the
            // one that replaced it, and a reply would go to a session it was never about.
            guard self.annotator.currentKey == shot.url.path else { return }
            self.annotator.destinationsAnswered(found, complete: complete)
        }
    }

    /// Send, from the annotator's toolbar. The drawing is rendered without closing anything; the
    /// image leaves the editor only once that rendering and the request are stored, so a failure
    /// anywhere before then leaves the drawing exactly where the hand left it.
    private func sendDrawing(_ drawing: Drawing, of shot: Screenshot, to destination: AgentDestination) {
        guard !annotator.sending, let session = annotator.session else { return }
        let name = shot.url.lastPathComponent
        // Nothing drawn is a send of the screenshot itself, which is what the person is looking at.
        // Through PNG whatever the capture format is: a reply copies these bytes to a `.png`
        // name, and an agent opening a file whose name and content disagree may not cope.
        guard !drawing.marks.isEmpty else {
            guard let bytes = Thumbnailer.png(from: shot.url) else {
                Commands.error("send", .unreadableImage, shot.url.path)
                thumbnail.showFeedback("Could not read \(name)")
                return
            }
            return submit(bytes, of: shot, to: destination)
        }
        annotator.sending = true
        let ui = settings.data.ui
        let rendering = RenderingQueue.shared.render(drawing, imageAt: shot.url, writingTo: nil, style: ui.textStyle, arrowhead: ui.arrowhead)
        rendering.whenDone { [weak self] output in
            guard let self else { return }
            // A rendering that answers after the session that pressed Send has ended belongs to no
            // image now, even the same one opened again: it is dropped, and nothing is sent and
            // nothing closed. The session open now has its own `sending`, which this leaves alone.
            guard annotator.session == session else {
                Log.write("[send] dropped \(name); the editor moved on"); return
            }
            annotator.sending = false
            guard let png = output.png, output.failure == nil else {
                let failure = output.failure ?? .writeFailed("the rendering made no image")
                Commands.error("send", failure.code, "\(name): \(failure)")
                thumbnail.showFeedback("Could not render the drawing; see the log")
                return
            }
            submit(png, of: shot, to: destination)
        }
    }

    private func submit(_ png: Data, of shot: Screenshot, to destination: AgentDestination) {
        guard requests.send(png: png, source: shot.url, to: destination) != nil else {
            thumbnail.showFeedback("Could not store the request; see the log"); return
        }
        // Stored, so the request survives whatever the client does next. The image goes home
        // and takes no copied mark: copying is Done's contract. A queued run carries on.
        thumbnail.annotationSent()
    }

    private func present(_ shot: Screenshot, annotate: Bool) {
        if annotate, shot.kind == .image { self.annotate([shot]) } else { thumbnail.show(shot) }
    }

    @objc private func toggleRecent() { _ = pressRecent() }

    @discardableResult
    private func pressRecent() -> ThumbnailController.StackToggle {
        if thumbnail.stackShowing { thumbnail.dismiss(); Commands.ok("recent", "dismissed"); return .dismissed }
        let index = recentShots(limit: settings.data.recentCount)
        watcher?.rescan(reason: "recent")   // keeps the index honest for the next open; nothing waits for it
        let result = thumbnail.toggleRecent(index.recent.map(Screenshot.init), detail: "files=\(index.files) ")
        switch result {
        case .shown(let count): Commands.ok("recent", "shown \(count) cards")
        case .dismissed: Commands.ok("recent", "dismissed")
        case .empty: Commands.error("recent", .missingFile, "no screenshots in \(watchFolder.path)")
        }
        return result
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }

    private func startWatching() {
        Log.write("[watcher] watching \(watchFolder.path)")
        watcher = ScreenshotWatcher(folder: watchFolder, onNew: { [weak self] url in
            Log.write("[watcher] new \(url.lastPathComponent)")
            guard let self else { return }
            let shot = Screenshot(url: url)
            let name = url.lastPathComponent
            if self.pendingAdds[name] != nil {
                self.pendingAdds[name]?.waiting = shot
                self.presentAdd(name)   // waits when the push's marks are still joining its drawing
                return
            }
            // An agent's reply is shown once by its own import, when every byte and its drawing are
            // stored. A watcher report for one — the copy that made it, or a later rescan — is
            // never a capture, so it neither goes to the clipboard nor opens the editor.
            guard self.requests.isCapture(url) else { return }
            if self.settings.data.copyOnCapture {
                Clipboard.copyFiles([url])
                Log.write("[watcher] copied \(url.lastPathComponent)")
            }
            self.present(shot, annotate: self.settings.data.annotateOnCapture)
        }, onRemoved: { [weak self] urls in
            Log.write("[watcher] removed \(urls.map(\.lastPathComponent).joined(separator: ", "))")
            self?.thumbnail.remove(urls.map(Screenshot.init))
            self?.drawings.remove(urls)
            for url in urls { self?.requests.fileRemoved(url) }
        })
        warmThumbnails()
        if wakeObserver == nil {
            // Both observers are registered with queue: .main, so the notification always arrives there.
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.watcher?.rescan(reason: "wake") } }
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.thumbnail.screensChanged() } }
        }
    }

    /// Decodes thumbnails for the recent stack ahead of time so the hotkey shows it at once.
    private func warmThumbnails() {
        thumbnail.warm(recentShots(limit: settings.data.recentCount).recent.map(Screenshot.init))
    }
}

extension AppDelegate: NSMenuDelegate, NSMenuItemValidation {
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }

    /// Both of these act on a screenshot, and with an empty folder they did nothing and said so
    /// only in the log. Greyed out is what a Mac user already reads as nothing to act on.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleRecent), #selector(annotateLast): return hasScreenshots
        default: return true
        }
    }
}
