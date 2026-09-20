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
        thumbnail.onAnnotatorPrepare = { [weak self] shot, frame, room in self?.annotator.prepare(shot, in: frame, room: room) }
        annotator.onFrame = { [weak self] frame in self?.thumbnail.annotatorFrameMoved(frame) }
        thumbnail.onAnnotatorShow = { [weak self] in self?.annotator.show() }
        thumbnail.onAnnotatorLanded = { [weak self] in self?.annotator.landed() }
        thumbnail.annotatorBelow = { [weak self] in self?.annotator.spaceBelow ?? 0 }
        thumbnail.onAnnotatorHide = { [weak self] hidden in self?.annotator.hide(then: hidden) }
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
        loadDrafts()
        startWatching()
        registerHotKey()
        settings.onChange = { [weak self] old, new in self?.settingsChanged(old, new) }
        if let notice = settings.startupNotice { thumbnail.showFeedback(notice) }
        else if settings.firstLaunch { thumbnail.showFeedback("\(Identity.name) is watching \(settings.data.screenshotsFolder). Launch at login is off; turn it on in Settings.") }
        // The setting is the user's wish; macOS may have lost the registration (the app moved) or kept one the file no longer asks for.
        LoginItem.apply(settings.data.launchAtLogin)
        applyAgentSkill()
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
        if new.agentSkill != old.agentSkill, !agentSkillApplied {
            // Turning it on installs; turning it off removes. The offer's unasked -> off writes nothing.
            if new.agentSkillChoice == .on { applyAgentSkill(.on) }
            else if old.agentSkillChoice == .on { applyAgentSkill(.off) }
        }
    }

    // MARK: The agent skill

    /// Set while `installSkill` records an install it has already run, so writing the setting does
    /// not run the same install a second time.
    private var agentSkillApplied = false

    /// Keeps the bundled skill in step with the setting: installed and current for this build while
    /// it is on, gone when it goes off. `roots` is for `install-skill?root=`, which points a check
    /// at one directory instead of the agent directories.
    @discardableResult
    private func applyAgentSkill(_ choice: AgentSkill? = nil, roots: [URL]? = nil) -> [SkillInstaller.Result] {
        let choice = choice ?? settings.data.agentSkillChoice
        let roots = roots ?? SkillInstaller.roots(home: FileManager.default.homeDirectoryForCurrentUser)
        var results: [SkillInstaller.Result] = []
        switch choice {
        case .on:
            guard let source = SkillInstaller.bundled else {
                Log.write("[skill] error missing-file \(SkillInstaller.skillName) is not in the bundle"); return []
            }
            results = SkillInstaller.install(source: source, into: roots, stamp: .current)
        case .off:
            results = SkillInstaller.remove(from: roots)
        case .unasked:
            offerAgentSkill()
        }
        // Only what changed something: a launch with the skill already current says nothing. A
        // root refused for its link, or holding a copy this installer did not write, is worth one
        // line when the user asked for an install and did not get one, and nothing at all on the
        // removal every later launch runs.
        let quiet: [SkillInstaller.Outcome] = choice == .off
            ? [.unchanged, .absent, .linkedRoot, .notOurs] : [.unchanged, .absent]
        for result in results where !quiet.contains(result.outcome) {
            Log.write("[skill] \(result.outcome.rawValue) \(result.path.path)\(result.detail.isEmpty ? "" : " \(result.detail)")")
        }
        return results
    }

    /// The offer, once: the app has never asked and this Mac has an agent directory. The offer is
    /// the Settings window, since the toast carries no button, and the answer is the toggle in it.
    /// Recorded as `off` as it is made, so the question is asked once whatever the user does.
    private func offerAgentSkill() {
        let roots = SkillInstaller.roots(home: FileManager.default.homeDirectoryForCurrentUser)
        guard !roots.isEmpty else { return }
        settings.update { $0.agentSkill = AgentSkill.off.rawValue }
        Log.write("[skill] offered \(roots.map(\.lastPathComponent).joined(separator: " "))")
        settingsWindow.show(scrollTo: SettingsView.agentsSection, activating: false)
    }

    /// Where a copy this installer made is sitting right now, for the state report.
    private func installedSkillPaths() -> [String] {
        SkillInstaller.roots(home: FileManager.default.homeDirectoryForCurrentUser)
            .filter { SkillInstaller.state(of: $0).state == .ours }
            .map { SkillInstaller.folder(in: $0).path }
    }

    /// Agent directories the installer will not write to, and why, for the state report: a root is
    /// listed as usual, so silence would be the only sign it was skipped.
    private func linkedSkillRoots() -> [String] {
        SkillInstaller.roots(home: FileManager.default.homeDirectoryForCurrentUser)
            .compactMap { SkillInstaller.linkedPath(in: $0)?.path }
    }

    /// `vignette://install-skill`, for a script. With `root=` it installs there and leaves the
    /// setting alone; without one it installs for every agent on this Mac and turns the setting on,
    /// so later launches keep the copy current.
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
        let results = applyAgentSkill(.on, roots: roots)
        let detail = results.map { "\($0.path.path)=\($0.outcome.rawValue)" }.joined(separator: " ")
        if let bad = results.first(where: { [.notOurs, .linkedRoot, .failed].contains($0.outcome) }) {
            let code: CommandError = bad.outcome == .notOurs ? .notOurs : (bad.outcome == .linkedRoot ? .linkedRoot : .writeFailed)
            Commands.error("install-skill", code, bad.detail.isEmpty ? detail : "\(detail) \(bad.detail)")
            return
        }
        if request.root == nil, settings.data.agentSkillChoice != .on {
            agentSkillApplied = true
            settings.update { $0.agentSkill = AgentSkill.on.rawValue }
            agentSkillApplied = false
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
            let focused = thumbnail.focusedShot
            pressDismissed = pressRecent() == .dismissed
            holdTarget = pressDismissed ? focused : nil
        }
        let hold = { [weak self] in
            guard let self else { return }
            Log.write("[hotkey] hold")
            if pressDismissed { _ = pressRecent() }
            if let shot = holdTarget { annotate([shot]) } else { annotateLast() }
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
        thumbnail.showFeedback(shots.count == 1 ? "Copied path" : "Copied \(shots.count) paths")
    }

    func annotate(_ shots: [Screenshot]) {
        guard let shot = shots.first else { Commands.error("annotate", .missingFile, "nothing selected"); return }
        Commands.ok("annotate", shots.count > 1 ? "\(shot.url.lastPathComponent) 1 of \(shots.count)" : shot.url.lastPathComponent)
        thumbnail.annotate(shots)
    }

    /// The newest screenshot in the watch folder goes into the annotator, on screen or not.
    @objc private func annotateLast() {
        guard let url = watcher?.newest() else {
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
                guard let newest = watcher?.newest() else {
                    Commands.error(cmd, .missingFile, "no file given and no screenshot in \(watchFolder.path)"); return
                }
                targets = [newest]
            }
            for file in targets {
                if let code = Commands.policyError(for: file, watchFolder: watchFolder, debug: settings.data.debug) {
                    Commands.error(cmd, code, file.path); return
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
            "appleThumbnail": settings.data.appleThumbnail, "recentCount": settings.data.recentCount, "hotkey": settings.data.recentHotkey, "debug": settings.data.debug,
            "launchAtLogin": settings.data.launchAtLogin, "loginItem": LoginItem.status,
            "agentSkill": ["setting": settings.data.agentSkill, "installed": installedSkillPaths(),
                           "linkedRoots": linkedSkillRoots()] as [String: Any],
        ] as [String: Any]
        report.sections["annotator"] = annotator.stateJSON
        report.sections["drafts"] = drafts.keys.sorted()
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
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: Identity.name)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Open Last Screenshot", action: #selector(openLast), keyEquivalent: "")
        menu.addItem(withTitle: "Show Recent Screenshots  (\(settings.data.recentHotkey))", action: #selector(toggleRecent), keyEquivalent: "")
        menu.addItem(withTitle: "Draw on Last Screenshot  (hold \(settings.data.recentHotkey))", action: #selector(annotateLast), keyEquivalent: "")
        let copyItem = NSMenuItem(title: "Copy New Captures", action: #selector(toggleCopyOnCapture), keyEquivalent: "")
        copyItem.state = settings.data.copyOnCapture ? .on : .off
        menu.addItem(copyItem)
        let captureItem = NSMenuItem(title: "Draw on New Captures", action: #selector(toggleAnnotateOnCapture), keyEquivalent: "")
        captureItem.state = settings.data.annotateOnCapture ? .on : .off
        menu.addItem(captureItem)
        menu.addItem(.separator())
        let folderItem = NSMenuItem(title: "Watching: \(settings.data.screenshotsFolder)", action: nil, keyEquivalent: "")
        folderItem.isEnabled = false
        menu.addItem(folderItem)
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Restore Apple Screenshot Defaults", action: #selector(restoreAppleDefaults), keyEquivalent: "")
        menu.addItem(withTitle: "Tweak UI…", action: #selector(openTweaks), keyEquivalent: "")
        menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Vignette", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func restoreAppleDefaults() {
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

    @objc private func toggleCopyOnCapture() {
        settings.update { $0.copyOnCapture.toggle() }
        Log.write("[settings] copyOnCapture=\(settings.data.copyOnCapture)")
    }

    @objc private func toggleAnnotateOnCapture() {
        settings.update { $0.annotateOnCapture.toggle() }
        Log.write("[settings] annotateOnCapture=\(settings.data.annotateOnCapture)")
    }

    @objc private func openLast() {
        guard let url = watcher?.newest() else {
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
        guard let file = request.files.first ?? watcher?.newest() else {
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

    private func present(_ shot: Screenshot, annotate: Bool) {
        if annotate { self.annotate([shot]) } else { thumbnail.show(shot) }
    }

    @objc private func toggleRecent() { _ = pressRecent() }

    @discardableResult
    private func pressRecent() -> ThumbnailController.StackToggle {
        if thumbnail.stackShowing { thumbnail.dismiss(); Commands.ok("recent", "dismissed"); return .dismissed }
        let index = watcher?.recent(limit: settings.data.recentCount) ?? (recent: [], files: 0)
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
            if self.settings.data.copyOnCapture {
                Clipboard.copyFiles([url])
                Log.write("[watcher] copied \(url.lastPathComponent)")
            }
            self.present(shot, annotate: self.settings.data.annotateOnCapture)
        }, onRemoved: { [weak self] urls in
            Log.write("[watcher] removed \(urls.map(\.lastPathComponent).joined(separator: ", "))")
            self?.thumbnail.remove(urls.map(Screenshot.init))
            self?.forgetDrafts(urls.map(Screenshot.init))
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
        thumbnail.warm((watcher?.recent(limit: settings.data.recentCount).recent ?? []).map(Screenshot.init))
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }
}
