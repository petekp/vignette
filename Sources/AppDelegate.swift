import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private var statusItem: NSStatusItem!
    private var watcher: ScreenshotWatcher?
    private let thumbnail = ThumbnailController()
    private let annotator = AnnotationController()
    private let settings = Settings()
    private var hotKey: HotKey?
    private let recentCount = 5

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        annotator.preload()
        thumbnail.onCopy = { [weak self] shot in self?.copyToClipboard(shot) }
        thumbnail.onDelete = { [weak self] shot in self?.trash(shot) }
        thumbnail.onAnnotate = { [weak self] shot, fromFrame in self?.annotator.present(shot, from: fromFrame) }
        annotator.onFinished = { [weak self] shot, pngData in self?.finishAnnotation(shot, pngData) }
        startWatching()
        hotKey = HotKey(keyCode: HotKey.cmdShift6.keyCode, modifiers: HotKey.cmdShift6.modifiers) { [weak self] in self?.toggleRecent() }
    }

    @objc private func toggleRecent() {
        let shots = ScreenshotWatcher.recentScreenshots(in: settings.watchFolder, limit: recentCount).map(Screenshot.init)
        thumbnail.toggleRecent(shots)
    }

    /// shotnote://last, shotnote://recent, shotnote://annotate-last. Lets Shortcuts and scripts drive the app.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host {
            case "last": openLast()
            case "recent": toggleRecent()
            case "debug": annotator.dumpState()
            case "show-editor": annotator.presentEmpty()
            case "annotate-last":
                guard let file = ScreenshotWatcher.newestScreenshot(in: settings.watchFolder) else { return }
                thumbnail.show(Screenshot(url: file))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.thumbnail.annotateFirst() }
            default: break
            }
        }
    }

    // MARK: Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Shotnote")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Open Last Screenshot", action: #selector(openLast), keyEquivalent: "")
        let recent = NSMenuItem(title: "Show Recent Screenshots", action: #selector(toggleRecent), keyEquivalent: "6")
        recent.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(recent)
        menu.addItem(.separator())
        let folderItem = NSMenuItem(title: "Watching: \(settings.watchFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))", action: nil, keyEquivalent: "")
        folderItem.isEnabled = false
        menu.addItem(folderItem)
        menu.addItem(withTitle: "Change Folder…", action: #selector(changeFolder), keyEquivalent: "")
        let replace = NSMenuItem(title: "Replace Apple's Thumbnail", action: #selector(toggleReplaceApple), keyEquivalent: "")
        replace.state = Settings.appleThumbnailEnabled ? .off : .on
        menu.addItem(replace)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Shotnote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
    }

    @objc private func openLast() {
        guard let url = ScreenshotWatcher.newestScreenshot(in: settings.watchFolder) else { return }
        thumbnail.show(Screenshot(url: url))
    }

    @objc private func changeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = settings.watchFolder
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            settings.watchFolder = url
            startWatching()
        }
    }

    @objc private func toggleReplaceApple() {
        Settings.appleThumbnailEnabled.toggle()
    }

    // MARK: Watching

    private func startWatching() {
        watcher = ScreenshotWatcher(folder: settings.watchFolder) { [weak self] url in
            self?.thumbnail.show(Screenshot(url: url))
        }
    }

    // MARK: Actions

    private func copyToClipboard(_ shot: Screenshot) {
        guard let data = try? Data(contentsOf: shot.url) else { return }
        Clipboard.copyPNG(data)
    }

    private func trash(_ shot: Screenshot) {
        try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
    }

    private func finishAnnotation(_ shot: Screenshot, _ png: Data) {
        let base = shot.url.deletingPathExtension().lastPathComponent
        let out = shot.url.deletingLastPathComponent().appendingPathComponent("\(base)-annotated.png")
        try? png.write(to: out)
        Clipboard.copyPNG(png)
        thumbnail.showFeedback("Copied to clipboard")
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }
}
