import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate, Actions {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private var statusItem: NSStatusItem?
    private var watcher: ScreenshotWatcher?
    private var hotKey: HotKey?
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
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = AppDelegate.makeMainMenu()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        Log.write("[app] launched \(version) watching \(watchFolder.path) settings \(Settings.fileURL.path)")
        updateStatusItem()
        annotator.preload()
        thumbnail.actions = self
        thumbnail.onAnnotatorPrepare = { [weak self] shot, frame in self?.annotator.prepare(shot, in: frame) }
        thumbnail.onAnnotatorShow = { [weak self] in self?.annotator.show() }
        thumbnail.onAnnotatorHide = { [weak self] hidden in self?.annotator.hide(then: hidden) }
        annotator.onFinished = { [weak self] shot, pngData in self?.finishAnnotation(shot, pngData) }
        annotator.onClosed = { [weak self] in self?.thumbnail.annotationEnded() }
        annotator.onDraftsChanged = { [weak self] keys in self?.thumbnail.setDrafts(keys) }
        annotator.onDraftPreview = { [weak self] path, png in self?.thumbnail.setPreview(path, png) }
        startWatching()
        registerHotKey()
        settings.onChange = { [weak self] old, new in self?.settingsChanged(old, new) }
    }

    private func settingsChanged(_ old: SettingsData, _ new: SettingsData) {
        if new.ui != old.ui { thumbnail.applyTweaks() }
        if new.screenshotsFolder != old.screenshotsFolder { startWatching() }
        if new.recentHotkey != old.recentHotkey { registerHotKey() }
        if new.hideMenuBarIcon != old.hideMenuBarIcon { updateStatusItem() }
    }

    private func registerHotKey() {
        hotKey = nil
        guard let combo = HotKey.parse(settings.data.recentHotkey) else {
            Log.write("[hotkey] cannot parse \"\(settings.data.recentHotkey)\"; no hotkey registered")
            return
        }
        hotKey = HotKey(keyCode: combo.keyCode, modifiers: combo.modifiers) { [weak self] in
            Log.write("[hotkey] recent")
            self?.toggleRecent()
        }
        Log.write("[hotkey] registered \(settings.data.recentHotkey)")
    }

    // MARK: Actions (see Config.actions). Lists arrive oldest first.

    func copyToClipboard(_ shots: [Screenshot]) {
        guard !shots.isEmpty else { return }
        Clipboard.copyFiles(shots.map(\.url))
        Log.write("[copy] \(shots.map { $0.url.lastPathComponent })")
        thumbnail.showFeedback(shots.count == 1 ? "Copied to clipboard" : "Copied \(shots.count) images")
    }

    func copyPaths(_ shots: [Screenshot]) {
        guard !shots.isEmpty else { return }
        Clipboard.copyText(Clipboard.pathsText(shots.map(\.url)))
        Log.write("[paths] \(shots.map { $0.url.lastPathComponent })")
        thumbnail.showFeedback(shots.count == 1 ? "Copied path" : "Copied \(shots.count) paths")
    }

    func annotate(_ shot: Screenshot) {
        Log.write("[annotate] \(shot.url.lastPathComponent)")
        thumbnail.annotate(shot)
    }

    func stitch(_ shots: [Screenshot]) {
        guard shots.count >= 2, let png = Stitch.compose(shots.map(\.url)) else { return }
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let out = watchFolder.appendingPathComponent("Stitch \(stamp.string(from: Date())).png")
        do { try png.write(to: out) } catch { Log.write("[stitch] save failed: \(error.localizedDescription)"); return }
        Clipboard.copyFiles([out])
        Log.write("[stitch] \(shots.count) images -> \(out.lastPathComponent) \(png.count) bytes, copied")
        thumbnail.showFeedback("Stitched \(shots.count) images, copied")
    }

    func moveToTrash(_ shots: [Screenshot]) {
        for shot in shots {
            do {
                try FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
                Log.write("[trash] \(shot.url.lastPathComponent)")
            } catch {
                Log.write("[trash] failed \(shot.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        thumbnail.remove(shots)
        annotator.forgetDrafts(shots)
    }

    func copyAnnotated(_ shots: [Screenshot]) {
        annotator.exportDrafts(shots) { [weak self] pngs in
            guard let self else { return }
            var urls: [URL] = []
            var annotated = 0
            for shot in shots {
                if let png = pngs[shot.url.path], let out = self.writeAnnotated(shot, png) { urls.append(out); annotated += 1 }
                else { urls.append(shot.url) }
            }
            Clipboard.copyFiles(urls)
            Log.write("[copy-annotated] \(urls.count) files, \(annotated) with annotations")
            self.thumbnail.showFeedback(urls.count == 1 ? "Copied to clipboard" : "Copied \(urls.count) images")
        }
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

    // MARK: URL commands: shotnote://<command>[?file=/path&file=/other]

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Log.write("[url] \(url.absoluteString)")
            let command = url.host ?? ""
            let files = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .filter { $0.name == "file" }
                .compactMap(\.value)
                // `open` percent-encodes once more when the caller already encoded, so decode twice.
                .map { $0.removingPercentEncoding ?? $0 }
                .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            switch command {
            case "last": openLast()
            case "recent": toggleRecent()
            case "state": dumpState()
            case "settings": settingsWindow.show()
            case "tweaks": debugPanel.toggle()
            case "show-editor": annotator.presentEmpty()
            case "eval": annotator.evalForDebug(url.query?.removingPercentEncoding ?? "")
            default:
                guard let action = Config.action(id: command) else {
                    Log.write("[url] unknown command \"\(command)\"")
                    return
                }
                var targets = files
                if targets.isEmpty, let newest = ScreenshotWatcher.newestScreenshot(in: watchFolder) { targets = [newest] }
                guard targets.count >= action.minimumCount else {
                    Log.write("[url] \(command) needs at least \(action.minimumCount) file(s)")
                    return
                }
                action.run(targets.map(Screenshot.init), self)
            }
        }
    }

    private func dumpState() {
        Log.write("[state] watchFolder=\(watchFolder.path) appleThumbnail=\(settings.data.appleThumbnail) recentCount=\(settings.data.recentCount) hotkey=\(settings.data.recentHotkey)")
        Log.write("[state] thumbnail: \(thumbnail.stateDescription)")
        Log.write("[state] cardFrames(x,y,w,h bottom-left origin): \(thumbnail.cardFramesDescription) screen=\(Int(NSScreen.main?.frame.height ?? 0))")
        Log.write("[state] annotator: \(annotator.stateDescription)")
        Log.write("[state] backdrop: \(thumbnail.backdropDescription)")
        annotator.dumpPageState()
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
        let positionKey = "NSStatusItem Preferred Position shotnote"
        if UserDefaults.standard.object(forKey: positionKey) == nil { UserDefaults.standard.set(80, forKey: positionKey) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "shotnote"
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Shotnote")
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
        menu.addItem(withTitle: "Tweak UI…", action: #selector(openTweaks), keyEquivalent: "")
        menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Shotnote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func openTweaks() {
        debugPanel.toggle()
    }

    @objc private func openLast() {
        guard let url = ScreenshotWatcher.newestScreenshot(in: watchFolder) else { return }
        thumbnail.show(Screenshot(url: url))
    }

    @objc private func toggleRecent() {
        let shots = ScreenshotWatcher.recentScreenshots(in: watchFolder, limit: settings.data.recentCount).map(Screenshot.init)
        thumbnail.toggleRecent(shots)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }

    private func startWatching() {
        Log.write("[watcher] watching \(watchFolder.path)")
        watcher = ScreenshotWatcher(folder: watchFolder) { [weak self] url in
            Log.write("[watcher] new \(url.lastPathComponent)")
            self?.thumbnail.show(Screenshot(url: url))
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }
}
