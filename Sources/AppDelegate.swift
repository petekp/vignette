import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, Actions {
    static func main() {
        let app = NSApplication.shared
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
        /// The page is still turning the push's marks into a draft. The presentation waits for it,
        /// so the card's first image carries the marks and the annotator opens with them.
        var buildingDraft = false
        /// The file, once there is something to present: the watcher's report, or the file itself
        /// when it was already in the folder and no report is coming.
        var waiting: Screenshot?
    }
    private var pendingAdds: [String: PendingAdd] = [:]
    /// Sending drawings to agent sessions and taking their drawings back. See ScreenshotRequests.
    private let requests = ScreenshotRequests(root: Identity.applicationSupportURL.appendingPathComponent("requests"))

    func applicationDidFinishLaunching(_ notification: Notification) {
        replaceOlderInstances()
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = AppDelegate.makeMainMenu()
        let settingsSource = Settings.isOverridden ? " (VIGNETTE_SETTINGS)" : ""
        Log.writeLaunch("[app] launched \(BuildInfo.current.description) watching \(watchFolder.path) settings \(Settings.fileURL.path)\(settingsSource)")
        if let type = AppleScreencapture.string("type"), !ScreenshotWatcher.isCandidate("screenshot.\(type)") {
            Log.write("[settings] warning Apple screencapture type=\(type) is a format the watcher ignores")
        }
        updateStatusItem()
        annotator.preload()
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
        thumbnail.onAnnotatorHide = { [weak self] hidden in self?.annotator.hide { hidden() } }
        thumbnail.onAnnotatorAbandon = { [weak self] in self?.annotator.abandon() }
        annotator.onFinished = { [weak self] shot, pngData in self?.finishAnnotation(shot, pngData) }
        annotator.onClosed = { [weak self] in self?.thumbnail.annotationEnded() }
        annotator.onLoaded = { [weak self] key in self?.thumbnail.pageLoaded(key) }
        annotator.onProblem = { [weak self] text in self?.thumbnail.showFeedback(text) }
        annotator.fileAccess.update(folder: watchFolder, unrestricted: settings.data.debug)
        annotator.onDraftPreview = { [weak self] path, png in self?.storeDonePreview(path, png) }
        annotator.draftSnapshot = { [weak self] key in self?.drafts.snapshot(for: key) }
        annotator.onDraft = { [weak self] key, snapshot in self?.storeDraft(key, snapshot: snapshot) }
        annotator.onParked = { [weak self] key, parked in
            self?.storeDraft(key, snapshot: parked.snapshot, reason: "parked")
            if let png = parked.preview { self?.storePreview(key, png) }
        }
        annotator.onPageReady = { [weak self] in
            guard let self else { return }
            self.renderMissingPreviews(self.drafts.keysWithoutPreview())
        }
        // A reply's marks need the page's canvas, and every owner of it releases at its own moment:
        // a session ending, an export answering, a push finishing, the page coming back.
        annotator.onCanvasFree = { [weak self] in self?.requests.canvasBecameAvailable() }
        annotator.onSend = { [weak self] destination in self?.sendDrawing(to: destination) }
        settingsWindow.callbacks = SettingsWindowController.Callbacks(
            restoreAppleDefaults: { [weak self] in self?.restoreAppleDefaults() },
            openTweaks: { [weak self] in self?.debugPanel.toggle() },
            installAgentSkill: { [weak self] root in self?.installAgentSkill(into: [root]) },
            removeAgentSkill: { [weak self] root in self?.removeAgentSkill(from: [root]) })
        // Before the watcher, so a capture taken during launch already lands the way Vignette needs.
        settings.reconcileApple()
        loadDrafts()
        startRequests()
        startWatching()
        registerHotKey()
        settings.onChange = { [weak self] old, new in self?.settingsChanged(old, new) }
        if let notice = settings.startupNotice { thumbnail.showFeedback(notice) }
        // The setup window says the watch folder and offers launch at login, so the toast that used
        // to say both is only for a launch that is not showing it.
        else if settings.firstLaunch, !setupWindow.isUnasked {
            thumbnail.showFeedback("\(Identity.name) is watching \(settings.data.screenshotsFolder). Launch at login is off; turn it on in Settings.")
        }
        // The setting is the user's wish; macOS may have lost the registration (the app moved) or kept one the file no longer asks for.
        LoginItem.apply(settings.data.launchAtLogin)
        // Setup comes first and has the launch to itself: two windows competing for a first-time
        // user is worse than the skill offer waiting until the next launch.
        if setupWindow.isUnasked {
            setupWindow.show(hasScreenshots: { [weak self] in self?.hasScreenshots ?? false })
        } else {
            startAgentSkill()
        }
        // The contract for agents: after this line every command answers. The page reports `[web] ready` on its own.
        Log.write("[app] ready pid=\(ProcessInfo.processInfo.processIdentifier) build=\(BuildInfo.current.build) port=\(annotator.port) watching=\(watchFolder.path)")
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        if new.ui != old.ui { thumbnail.applyTweaks(); warmThumbnails() }
        if new.recentCount != old.recentCount { warmThumbnails() }
        if new.screenshotsFolder != old.screenshotsFolder { startWatching() }
        if new.screenshotsFolder != old.screenshotsFolder || new.debug != old.debug {
            annotator.fileAccess.update(folder: new.folderURL, unrestricted: new.debug)
        }
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

    func stitch(_ shots: [Screenshot]) {
        guard shots.count >= 2 else { Commands.error("stitch", .notEnoughFiles, "needs 2, got \(shots.count)"); return }
        guard let composed = Stitch.compose(shots.map(\.url), longSideLimit: Settings.shared.data.ui.stitchLongSide) else {
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

    // MARK: Drafts

    private lazy var drafts = DraftStore(
        directory: Identity.applicationSupportURL.appendingPathComponent("drafts"),
        previewDirectory: Identity.cachesURL.appendingPathComponent("drafts"))

    /// Drops drafts whose screenshot is gone, then shows the rest on their cards.
    private func loadDrafts() {
        let swept = drafts.sweep { FileManager.default.fileExists(atPath: $0) }
        for key in swept { Log.write("[draft] swept \((key as NSString).lastPathComponent)") }
        thumbnail.setDrafts(drafts.keys)
        for key in drafts.keys { if let png = drafts.preview(for: key) { thumbnail.setPreview(key, png) } }
        Log.write("[drafts] \(drafts.keys.count) dir=\(drafts.directory.path)")
    }

    /// A nil snapshot means the annotations were all removed. A draft for a file that no longer
    /// exists is dropped: the page can report one after the file was trashed.
    private func storeDraft(_ key: String, snapshot: Any?, reason: String = "saved") {
        let name = (key as NSString).lastPathComponent
        if let snapshot, FileManager.default.fileExists(atPath: key) {
            do { try drafts.save(key: key, snapshot: snapshot); Log.write("[draft] \(reason) \(name)") }
            catch { Log.write("[draft] error write-failed \(key): \(error.localizedDescription)") }
        } else if drafts.keys.contains(key) {
            drafts.forget([key])
            Log.write("[draft] forgot \(name)")
        }
        draftsChanged()
    }

    /// Pushes the draft set to the cards and logs its size, after every change.
    private func draftsChanged() {
        thumbnail.setDrafts(drafts.keys)
        Log.write("[drafts] \(drafts.keys.count)")
    }

    /// The Done rendering is full resolution; the card keeps a copy no larger than a park preview.
    private func storeDonePreview(_ key: String, _ png: Data) {
        DispatchQueue.global(qos: .userInitiated).async {
            let small = Thumbnailer.downsampled(png: png, maxPixel: Config.previewMaxPixel)
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let small else { Log.write("[draft] error preview downsample failed \((key as NSString).lastPathComponent)"); return }
                self.storePreview(key, small)
            } }
        }
    }

    /// A parked draft shows on its card as the preview PNG beside it, and macOS can clear the
    /// folder those live in. Each draft that lost its preview is rendered again from the stored
    /// annotations, one at a time, once the page is up. Nothing is shown and nothing is logged when
    /// there is nothing to render. The canvas is the annotator's the moment it takes an image, so a
    /// refusal leaves the rest for the next launch rather than queueing behind a drawing session.
    private func renderMissingPreviews(_ keys: [String]) {
        guard let key = keys.first, annotator.canvasRefusal == nil else { return }
        let rest = Array(keys.dropFirst())
        guard let snapshot = drafts.snapshot(for: key) else { renderMissingPreviews(rest); return }
        let name = (key as NSString).lastPathComponent
        annotator.exportDrafts([(key: key, snapshot: snapshot)]) { [weak self] pngs, error in
            guard let self else { return }
            if let png = pngs[key] {
                Log.write("[draft] preview \(name)")
                self.storeDonePreview(key, png)
            } else {
                Log.write("[draft] error preview-failed \(name): \(error ?? "no rendering")")
            }
            self.renderMissingPreviews(rest)
        }
    }

    private func storePreview(_ key: String, _ png: Data) {
        guard drafts.keys.contains(key) else { return }
        do { try drafts.savePreview(key: key, png: png) } catch { Log.write("[draft] error write-failed preview \(key): \(error.localizedDescription)") }
        thumbnail.setPreview(key, png)
    }

    private func forgetDrafts(_ shots: [Screenshot]) {
        let had = shots.filter { drafts.keys.contains($0.url.path) }
        guard !had.isEmpty else { return }
        drafts.forget(had.map(\.url.path))
        Log.write("[draft] forgot \(had.map(\.url.lastPathComponent).joined(separator: ", "))")
        draftsChanged()
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
        forgetDrafts(shots)
        if failed.isEmpty { Commands.ok("trash", trashed.joined(separator: ", ")) }
        else { Commands.error("trash", .writeFailed, "\(failed.joined(separator: "; ")); trashed \(trashed.count) of \(shots.count)") }
    }

    func copyAnnotated(_ shots: [Screenshot]) {
        let items = shots.compactMap { shot in drafts.snapshot(for: shot.url.path).map { (key: shot.url.path, snapshot: $0) } }
        guard !items.isEmpty else { finishCopyAnnotated(shots, pngs: [:]); return }
        annotator.exportDrafts(items) { [weak self] pngs, error in
            guard let self else { return }
            if let error {
                Commands.error("copy-annotated", error.hasPrefix("timeout") ? .exportTimeout : .exportFailed, error)
                self.thumbnail.showFeedback("Could not render the drawing; see the log")
                return
            }
            self.finishCopyAnnotated(shots, pngs: pngs)
        }
    }


    private func finishCopyAnnotated(_ shots: [Screenshot], pngs: [String: Data]) {
        var urls: [URL] = []
        var annotated = 0
        for shot in shots {
            if let png = pngs[shot.url.path], let out = writeAnnotated(shot, png) { urls.append(out); annotated += 1 }
            else { urls.append(shot.url) }
        }
        Clipboard.copyFiles(urls)
        Commands.ok("copy-annotated", "\(urls.map(\.lastPathComponent).joined(separator: ", ")); \(annotated) with annotations")
        thumbnail.showCopied(shots)
    }

    /// Done: the annotated file goes on the clipboard as a file, an image, and its path as text,
    /// so a terminal pastes the path and a chat app pastes the image.
    private func finishAnnotation(_ shot: Screenshot, _ png: Data?) {
        if let png {
            if let out = writeAnnotated(shot, png) {
                Clipboard.copyFiles([out])
                Log.write("[annotate] done \(out.lastPathComponent) \(png.count) bytes, copied")
            } else {
                Clipboard.copyPNG(png)
            }
        } else {
            Clipboard.copyFiles([shot.url])
            Log.write("[annotate] done \(shot.url.lastPathComponent) nothing drawn, original copied")
        }
        // Quick annotate: the drawing was the point; nothing comes back.
        if settings.data.quickAnnotate { Log.write("[annotate] quick close") }
        thumbnail.annotationFinished(quick: settings.data.quickAnnotate)
    }

    /// Writes `<name>-annotated.png` next to the screenshot.
    private func writeAnnotated(_ shot: Screenshot, _ png: Data) -> URL? {
        let base = shot.url.deletingPathExtension().lastPathComponent
        let out = shot.url.deletingLastPathComponent().appendingPathComponent("\(base)\(Config.annotatedSuffix).png")
        do { try png.write(to: out); return out } catch {
            Log.write("[annotate] save failed: \(error.localizedDescription)")
            return nil
        }
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
        // Only these three need the editor page. A loading page queues annotate one deep; the others wait for [web] ready.
        switch (cmd, annotator.pageState) {
        case ("annotate", .unavailable), ("copy-annotated", .unavailable), ("eval", .unavailable):
            Commands.error(cmd, .pageNotReady, "the editor page is unavailable; see the [web] lines"); return
        case ("copy-annotated", .loading), ("eval", .loading):
            Commands.error(cmd, .pageNotReady, "the editor page is still loading; wait for [web] ready"); return
        default: break
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
        case "send": sendToAgent(request)
        case "tweaks": debugPanel.toggle(); Commands.ok("tweaks")
        case "show-editor": annotator.presentEmpty(); Commands.ok("show-editor")
        case "dismiss": thumbnail.dismiss(); Commands.ok("dismiss")
        case "cancel": Commands.ok("cancel", annotator.cancelForDebug() ? "" : "nothing was open")
        case "eval": annotator.evalForDebug(request.query ?? "")   // answers when the page does
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
                // A reserved reply is Vignette's own until its import commits: opening it would take
                // the canvas the import is waiting for, and trashing it would delete the file the
                // import is about to draw on. The listings hide it; so does naming it.
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

    /// One `[state] {json}` line, written once the page has answered or after a second without it.
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
        report.sections["drafts"] = drafts.keys.sorted()
        report.sections["requests"] = requests.stateJSON
        report.sections["memory"] = ["rss": residentBytes(), "thumbnails": Thumbnailer.cacheBytes]
        annotator.queryPage(timeout: 1) { page in
            report.sections["page"] = page ?? "unavailable"
            Log.write("[state] \(report.rendered())")
        }
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

    /// `add?file=<path>[&annotate][&agent=<name>][&marks=<json>]`: a copy of an image from anywhere
    /// lands in the watch folder, where the watcher reports it like a capture; `pendingAdds` makes
    /// that report skip the capture toggles. `agent=` is recorded on the copy, which is what puts
    /// the badge on its card. `marks=` becomes a draft before the card appears, so the user opens
    /// the agent's drawing and edits it like their own.
    private func addImage(_ request: CommandRequest) {
        guard let source = request.files.first else { Commands.error("add", .missingFile, "no file given"); return }
        guard Commands.isReadableImage(source) else { Commands.error("add", .unreadableImage, source.path); return }
        var marks: [Mark] = []
        if let value = request.marks {
            // Checked before anything is copied: a push with bad marks is one error line and no file.
            do { marks = try Commands.marks(from: value) } catch { Commands.error("add", .invalidMarks, "\(error)"); return }
            // Before the color check: the colors come from the page, so without one the answer is
            // that the page is not ready, not that the color is wrong.
            if let refused = annotator.canvasRefusal {
                Commands.error("add", .pageNotReady, "\(refused); marks need the editor free"); return
            }
            if let unknown = marks.compactMap(\.color).first(where: { !annotator.colorIDs.contains($0) }) {
                Commands.error("add", .invalidMarks, "unknown color \"\(unknown)\"; the editor has \(annotator.colorIDs.joined(separator: ", "))"); return
            }
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
        pendingAdds[name] = PendingAdd(annotate: request.annotate, buildingDraft: !marks.isEmpty,
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
        guard !marks.isEmpty else {
            presentAdd(name)
            Commands.ok("add", "\(name)\(inFolder ? " already in the watch folder" : "")\(detail(request))")
            return
        }
        annotator.buildDraft(Screenshot(url: destination), marks: marks) { [weak self] parked, error in
            guard let self else { return }
            // A build that answers without a snapshot built nothing; storing that nil would forget
            // the image's existing draft, so it is a failure and not "the annotations were removed".
            if let snapshot = error == nil ? parked?.snapshot : nil {
                self.storeDraft(destination.path, snapshot: snapshot, reason: "built")
                if let png = parked?.preview { self.storePreview(destination.path, png) }
                Commands.ok("add", "\(name)\(self.detail(request)) marks=\(marks.count)")
            } else {
                let why = error ?? "the page built no snapshot"
                Commands.error("add", why.hasPrefix("timeout") ? .exportTimeout : .exportFailed,
                               "\(name): the image is in the folder, its marks are not: \(why)")
            }
            self.pendingAdds[name]?.buildingDraft = false
            self.presentAdd(name)
        }
    }

    /// Shows the added file once nothing is owed on it: the watcher has reported it and its marks,
    /// if any, are a stored draft.
    private func presentAdd(_ name: String) {
        guard let pending = pendingAdds[name], !pending.buildingDraft, let shot = pending.waiting else { return }
        pendingAdds[name] = nil
        present(shot, annotate: pending.annotate)
    }

    /// What an `[add] ok` line says about the request beyond the file name.
    private func detail(_ request: CommandRequest) -> String {
        (request.annotate ? " annotate" : "") + (request.agent.map { " agent=\($0)" } ?? "")
    }

    /// Hands one screenshot to a coding agent in a herdr pane. The herdr calls are socket round
    /// trips, so they run off the main thread and the `[send]` line arrives when herdr answers.
    private func sendToAgent(_ request: CommandRequest) {
        guard let file = request.files.first ?? newestShot() else {
            Commands.error("send", .missingFile, "no file given and no screenshot in \(watchFolder.path)"); return
        }
        guard FileManager.default.fileExists(atPath: file.path) else { Commands.error("send", .missingFile, file.path); return }
        guard let herdr = Send.binary() else {
            Commands.error("send", .noAgent, "no herdr at \(Send.binaryPaths.joined(separator: " "))"); return
        }
        let message = Send.message(text: request.text, file: file)
        DispatchQueue.global(qos: .userInitiated).async {
            let list = Send.run(herdr, ["agent", "list"])
            guard let list, list.status == 0 else {
                Commands.error("send", .noAgent, "herdr agent list: \(Send.detail(list?.output) ?? "did not run")"); return
            }
            let targets = Send.targets(fromAgentList: Data(list.output.utf8))
            guard let target = Send.choose(targets, to: request.to) else {
                let known = targets.map { "\($0.id)(\($0.kind))" }.joined(separator: " ")
                Commands.error("send", .noAgent, request.to.map { "no agent \"\($0)\"; herdr has: \(known)" }
                    ?? (targets.isEmpty ? "herdr is running no agents" : "no focused agent; name one with to=: \(known)"))
                return
            }
            guard target.status != "blocked" else {
                Commands.error("send", .sendFailed, "\(target.id) is waiting on a prompt of its own; answer it first"); return
            }
            let sent = Send.run(herdr, ["agent", "prompt", target.id, message])
            guard let sent, sent.status == 0 else {
                Commands.error("send", .sendFailed, "\(target.id): \(Send.detail(sent?.output) ?? "herdr did not run")"); return
            }
            Commands.ok("send", "\(target.id) kind=\(target.kind) pane=\(target.pane) file=\(file.lastPathComponent)")
        }
    }

    // MARK: Screenshot requests: Send, replies, and which files a reply owns. See ScreenshotRequests.

    /// Wires the coordinator and reads what is already on disk. Runs before the watcher starts and
    /// before anything warms the stack: until the reply records are loaded nothing knows which
    /// managed files are unfinished, and an unfinished one must never read as an ordinary capture.
    private func startRequests() {
        requests.connections = [.claude: ClaudeCodeConnection(),
                                .codex: CodexConnection()]
        requests.callbacks = ScreenshotRequests.Callbacks(
            // Not `self?.annotator.canvasRefusal ?? …`: optional chaining on an already-optional
            // property flattens, so a free canvas (nil) would read as the fallback and every
            // import would wait forever.
            canvasRefusal: { [weak self] in
                guard let self else { return "the app is gone" }
                return self.annotator.canvasRefusal
            },
            buildDraft: { [weak self] shot, marks, done in
                guard let self else { return done(nil, "the app is gone") }
                self.annotator.buildDraft(shot, marks: marks, completion: done)
            },
            saveDraft: { [weak self] key, snapshot, preview in
                guard let self else { throw ReplyProtocol.Problem(.storeFailed, "the app is gone") }
                // The throwing store, not `storeDraft`: publication may only commit once the draft
                // is really on disk, and a logged failure is not an acknowledgement.
                try self.drafts.save(key: key, snapshot: snapshot)
                if let preview { try self.drafts.savePreview(key: key, png: preview) }
                self.draftsChanged()
                if let preview { self.thumbnail.setPreview(key, preview) }
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

    /// What the Send menu offers while this image is open, and the session a reply belongs back to.
    /// Reading the sessions runs subprocesses, so it answers later; the bar shows no button until it does.
    private func refreshDestinations(for shot: Screenshot) {
        let replyTo = requests.origin(of: shot.url)
        annotator.setDestinations([], replyTo: replyTo)
        requests.destinations { [weak self] found in
            guard let self else { return }
            // Listing the sessions runs subprocesses that can take seconds, so two images' answers
            // can arrive out of order. An answer for an image the editor has left would label the
            // one that replaced it, and a reply would go to a session it was never about.
            guard self.annotator.currentKey == shot.url.path else { return }
            self.annotator.setDestinations(found, replyTo: replyTo)
        }
    }

    /// Send, from the annotator's toolbar. The drawing is rendered without closing anything; the
    /// image leaves the editor only once that rendering and the request are stored, so a failure
    /// anywhere before then leaves the drawing exactly where the hand left it.
    private func sendDrawing(to destination: AgentDestination) {
        guard !annotator.sending else { return }
        annotator.sending = true
        annotator.snapshotCurrent { [weak self] key, png, error in
            guard let self else { return }
            self.annotator.sending = false
            guard !key.isEmpty else {
                Commands.error("send", .pageNotReady, error ?? "no image in the editor"); return
            }
            // A rendering that answers after the person moved to another image belongs to neither
            // of them: it is dropped, and nothing is sent and nothing closed.
            guard self.annotator.currentKey == key else {
                Log.write("[send] dropped \((key as NSString).lastPathComponent); the editor moved on"); return
            }
            let source = URL(fileURLWithPath: key)
            if let error {
                Commands.error("send", error.hasPrefix("timeout") ? .exportTimeout : .exportFailed, "\(source.lastPathComponent): \(error)")
                self.thumbnail.showFeedback("Could not render the drawing; see the log")
                return
            }
            // Nothing drawn is a send of the screenshot itself, which is what the person is looking at.
            // Through PNG whatever the capture format is: a reply copies these bytes to a `.png`
            // name, and an agent opening a file whose name and content disagree may not cope.
            guard let bytes = png ?? Thumbnailer.png(from: source) else {
                Commands.error("send", .unreadableImage, source.path)
                self.thumbnail.showFeedback("Could not read \(source.lastPathComponent)")
                return
            }
            guard self.requests.send(png: bytes, source: source, to: destination) != nil else {
                self.thumbnail.showFeedback("Could not store the request; see the log"); return
            }
            // Stored, so the request survives whatever the client does next. The image goes home
            // and takes no copied mark: copying is Done's contract. A queued run carries on.
            self.thumbnail.annotationSent()
        }
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
                self.presentAdd(name)   // waits when the push's marks are still becoming a draft
                return
            }
            // An agent's reply is shown once by its own import, when every byte and its draft are
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
            self?.forgetDrafts(urls.map(Screenshot.init))
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
