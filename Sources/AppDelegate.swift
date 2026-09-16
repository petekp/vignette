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
    private var modifierTap: ModifierTap?
    private let thumbnail = ThumbnailController()
    private let annotator = AnnotationController()
    private let settingsWindow = SettingsWindowController()
    private lazy var debugPanel = DebugPanelController(previews: .init(
        thumbnail: { [weak self] in self?.openLast() },
        stack: { [weak self] in self?.toggleRecent() },
        toast: { [weak self] in self?.thumbnail.showFeedback("Copied 3 images") },
        annotator: { [weak self] in
            guard let self, let url = ScreenshotWatcher.newestScreenshot(in: self.watchFolder) else { return }
            self.annotate(Screenshot(url: url))
        }))
    private let settings = Settings.shared
    private var watchFolder: URL { settings.data.folderURL }

    func applicationDidFinishLaunching(_ notification: Notification) {
        replaceOlderInstances()
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = AppDelegate.makeMainMenu()
        let settingsSource = Settings.isOverridden ? " (SHOTNOTE_SETTINGS)" : ""
        Log.write("[app] launched \(BuildInfo.current.description) watching \(watchFolder.path) settings \(Settings.fileURL.path)\(settingsSource)")
        if let type = AppleScreencapture.string("type"), !ScreenshotWatcher.isCandidate("screenshot.\(type)") {
            Log.write("[settings] warning Apple screencapture type=\(type) is a format the watcher ignores")
        }
        updateStatusItem()
        annotator.preload()
        thumbnail.actions = self
        thumbnail.onAnnotatorPrepare = { [weak self] shot, frame in self?.annotator.prepare(shot, in: frame) }
        thumbnail.onAnnotatorShow = { [weak self] in self?.annotator.show() }
        thumbnail.annotatorBelow = { [weak self] in self?.annotator.spaceBelow ?? 0 }
        thumbnail.onAnnotatorHide = { [weak self] hidden in self?.annotator.hide(then: hidden) }
        annotator.onFinished = { [weak self] shot, pngData in self?.finishAnnotation(shot, pngData) }
        annotator.onClosed = { [weak self] in self?.thumbnail.annotationEnded() }
        annotator.onLoaded = { [weak self] key in self?.thumbnail.pageLoaded(key) }
        annotator.onProblem = { [weak self] text in self?.thumbnail.showFeedback(text) }
        annotator.fileAccess.update(folder: watchFolder, unrestricted: settings.data.debug)
        annotator.onDraftPreview = { [weak self] path, png in self?.storeDonePreview(path, png) }
        annotator.draftSnapshot = { [weak self] key in self?.drafts.snapshot(for: key) }
        annotator.onDraft = { [weak self] key, snapshot in self?.storeDraft(key, snapshot: snapshot) }
        annotator.onParked = { [weak self] key, parked in
            self?.storeDraft(key, snapshot: parked.snapshot)
            if let png = parked.preview { self?.storePreview(key, png) }
        }
        loadDrafts()
        startWatching()
        registerHotKey()
        settings.onChange = { [weak self] old, new in self?.settingsChanged(old, new) }
        if let notice = settings.startupNotice { thumbnail.showFeedback(notice) }
        else if settings.firstLaunch { thumbnail.showFeedback("\(Identity.name) is watching \(settings.data.screenshotsFolder)") }
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
    }

    private func registerHotKey() {
        hotKey = nil
        modifierTap = nil
        let fire = { [weak self] in
            Log.write("[hotkey] recent")
            self?.toggleRecent()
        }
        switch HotKeySpec.parse(settings.data.recentHotkey) {
        case .key(let keyCode, let modifiers):
            hotKey = HotKey(keyCode: keyCode, modifiers: modifiers, action: fire)
        case .doubleTap(let keyCode):
            modifierTap = ModifierTap(keyCode: keyCode, action: fire)
        case nil:
            Log.write("[hotkey] cannot parse \"\(settings.data.recentHotkey)\"; no hotkey registered")
            return
        }
        Log.write("[hotkey] registered \(settings.data.recentHotkey)")
    }

    // MARK: Actions (see Config.actions). Lists arrive oldest first.

    func copyToClipboard(_ shots: [Screenshot]) {
        guard !shots.isEmpty else { Commands.error("copy", .missingFile, "nothing selected"); return }
        Clipboard.copyFiles(shots.map(\.url))
        Commands.ok("copy", shots.map(\.url.lastPathComponent).joined(separator: ", "))
        thumbnail.showFeedback(shots.count == 1 ? "Copied to clipboard" : "Copied \(shots.count) images")
    }

    func copyPaths(_ shots: [Screenshot]) {
        guard !shots.isEmpty else { Commands.error("paths", .missingFile, "nothing selected"); return }
        Clipboard.copyText(Clipboard.pathsText(shots.map(\.url)))
        Commands.ok("paths", shots.map(\.url.lastPathComponent).joined(separator: ", "))
        thumbnail.showFeedback(shots.count == 1 ? "Copied path" : "Copied \(shots.count) paths")
    }

    func annotate(_ shot: Screenshot) {
        Commands.ok("annotate", shot.url.lastPathComponent)
        thumbnail.annotate(shot)
    }

    func stitch(_ shots: [Screenshot]) {
        guard shots.count >= 2 else { Commands.error("stitch", .notEnoughFiles, "needs 2, got \(shots.count)"); return }
        guard let png = Stitch.compose(shots.map(\.url)) else {
            Commands.error("stitch", .unreadableImage, shots.map(\.url.lastPathComponent).joined(separator: ", ")); return
        }
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let out = watchFolder.appendingPathComponent("Stitch \(stamp.string(from: Date())).png")
        do { try png.write(to: out) } catch { Commands.error("stitch", .writeFailed, "\(out.path): \(error.localizedDescription)"); return }
        Clipboard.copyFiles([out])
        Commands.ok("stitch", "\(out.path) from \(shots.count) images, \(png.count) bytes, copied")
        thumbnail.showFeedback("Stitched \(shots.count) images, copied")
    }

    // MARK: Drafts

    private lazy var drafts = DraftStore(
        directory: Identity.applicationSupportURL.appendingPathComponent("drafts"),
        previewDirectory: Identity.cachesURL.appendingPathComponent("drafts"))

    /// Drops drafts whose screenshot is gone, then shows the rest on their cards.
    private func loadDrafts() {
        let swept = drafts.sweep { FileManager.default.fileExists(atPath: $0) }
        if !swept.isEmpty { Log.write("[drafts] swept \(swept.count) without a file") }
        thumbnail.setDrafts(drafts.keys)
        for key in drafts.keys { if let png = drafts.preview(for: key) { thumbnail.setPreview(key, png) } }
        Log.write("[drafts] loaded \(drafts.keys.count) from \(drafts.directory.path)")
    }

    /// A nil snapshot means the annotations were all removed. A draft for a file that no longer
    /// exists is dropped: the page can report one after the file was trashed.
    private func storeDraft(_ key: String, snapshot: Any?) {
        let name = (key as NSString).lastPathComponent
        if let snapshot, FileManager.default.fileExists(atPath: key) {
            do { try drafts.save(key: key, snapshot: snapshot); Log.write("[drafts] saved \(name)") }
            catch { Log.write("[drafts] error write-failed \(key): \(error.localizedDescription)") }
        } else if drafts.keys.contains(key) {
            drafts.forget([key])
            Log.write("[drafts] forgot \(name)")
        }
        thumbnail.setDrafts(drafts.keys)
    }

    /// The Done rendering is full resolution; the card keeps a copy no larger than a park preview.
    private func storeDonePreview(_ key: String, _ png: Data) {
        DispatchQueue.global(qos: .userInitiated).async {
            let small = Thumbnailer.downsampled(png: png, maxPixel: Config.previewMaxPixel)
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let small else { Log.write("[drafts] error preview downsample failed \((key as NSString).lastPathComponent)"); return }
                self.storePreview(key, small)
            } }
        }
    }

    private func storePreview(_ key: String, _ png: Data) {
        guard drafts.keys.contains(key) else { return }
        do { try drafts.savePreview(key: key, png: png) } catch { Log.write("[drafts] error write-failed preview \(key): \(error.localizedDescription)") }
        thumbnail.setPreview(key, png)
    }

    private func forgetDrafts(_ shots: [Screenshot]) {
        let had = shots.filter { drafts.keys.contains($0.url.path) }
        guard !had.isEmpty else { return }
        drafts.forget(had.map(\.url.path))
        Log.write("[drafts] forgot \(had.map(\.url.lastPathComponent).joined(separator: ", "))")
        thumbnail.setDrafts(drafts.keys)
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
                self.thumbnail.showFeedback("Could not render the annotations; see the log")
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
        thumbnail.showFeedback(urls.count == 1 ? "Copied to clipboard" : "Copied \(urls.count) images")
    }

    /// Done: the annotated file goes on the clipboard as a file, an image, and its path as text,
    /// so a terminal pastes the path and a chat app pastes the image.
    private func finishAnnotation(_ shot: Screenshot, _ png: Data) {
        if let out = writeAnnotated(shot, png) {
            Clipboard.copyFiles([out])
            Log.write("[annotate] done \(out.lastPathComponent) \(png.count) bytes, copied")
        } else {
            Clipboard.copyPNG(png)
        }
        thumbnail.showFeedback("Copied to clipboard")
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

    // MARK: URL commands: shotnote://<command>[?file=/path&file=/other]. See Commands.swift.

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
        case "recent": toggleRecent()
        case "state": dumpState()
        case "settings": settingsWindow.show(); Commands.ok("settings", "window opened")
        case "restore-apple-defaults": restoreAppleDefaults()
        case "tweaks": debugPanel.toggle(); Commands.ok("tweaks")
        case "show-editor": annotator.presentEmpty(); Commands.ok("show-editor")
        case "dismiss": thumbnail.dismiss(); Commands.ok("dismiss")
        case "cancel": Commands.ok("cancel", annotator.cancelForDebug() ? "" : "nothing was open")
        case "eval": annotator.evalForDebug(request.query ?? "")   // answers when the page does
        default:
            guard let action = Config.action(id: cmd) else { return }
            var targets = request.files
            if targets.isEmpty {
                guard let newest = ScreenshotWatcher.newestScreenshot(in: watchFolder) else {
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

    private func dumpState() {
        Log.write("[state] watchFolder=\(watchFolder.path) appleThumbnail=\(settings.data.appleThumbnail) recentCount=\(settings.data.recentCount) hotkey=\(settings.data.recentHotkey)")
        Log.write("[state] thumbnail: \(thumbnail.stateDescription)")
        Log.write("[state] cardFrames(x,y,w,h bottom-left origin): \(thumbnail.cardFramesDescription) screen=\(Int(NSScreen.main?.frame.height ?? 0))")
        Log.write("[state] \(thumbnail.screenDescription)")
        Log.write("[state] annotator: \(annotator.stateDescription)")
        Log.write("[state] memory rss=\(residentBytes() >> 20)MB thumbnails=\(Thumbnailer.cacheBytes >> 20)MB webPid=\(annotator.webProcessID.map(String.init) ?? "unknown")")
        Log.write("[state] backdrop: \(thumbnail.backdropDescription)")
        annotator.dumpPageState()
        Commands.ok("state", "page state follows on its own [web] line")
    }

    /// Accessory apps have no menu bar, but key equivalents like Cmd+W and Cmd+C in the Settings
    /// window still route through the main menu, so build a minimal one.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenuItem(); main.addItem(app)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Shotnote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        menu.addItem(.separator())
        let folderItem = NSMenuItem(title: "Watching: \(settings.data.screenshotsFolder)", action: nil, keyEquivalent: "")
        folderItem.isEnabled = false
        menu.addItem(folderItem)
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Restore Apple Screenshot Defaults", action: #selector(restoreAppleDefaults), keyEquivalent: "")
        menu.addItem(withTitle: "Tweak UI…", action: #selector(openTweaks), keyEquivalent: "")
        menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Shotnote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    @objc private func openLast() {
        guard let url = ScreenshotWatcher.newestScreenshot(in: watchFolder) else {
            Commands.error("last", .missingFile, "no screenshot in \(watchFolder.path)"); return
        }
        thumbnail.show(Screenshot(url: url))
        Commands.ok("last", url.lastPathComponent)
    }

    @objc private func toggleRecent() {
        let shots = ScreenshotWatcher.recentScreenshots(in: watchFolder, limit: settings.data.recentCount).map(Screenshot.init)
        switch thumbnail.toggleRecent(shots) {
        case .shown(let count): Commands.ok("recent", "shown \(count) cards")
        case .dismissed: Commands.ok("recent", "dismissed")
        case .empty: Commands.error("recent", .missingFile, "no screenshots in \(watchFolder.path)")
        }
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }

    private func startWatching() {
        Log.write("[watcher] watching \(watchFolder.path)")
        watcher = ScreenshotWatcher(folder: watchFolder, onNew: { [weak self] url in
            Log.write("[watcher] new \(url.lastPathComponent)")
            self?.thumbnail.show(Screenshot(url: url))
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
        thumbnail.warm(ScreenshotWatcher.recentScreenshots(in: watchFolder, limit: settings.data.recentCount).map(Screenshot.init))
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }
}
