import AppKit
import SwiftUI
import Combine
@preconcurrency import CoreFoundation

/// The settings file is the source of truth. The Settings window, the debug panel, agents, and
/// dotfiles all edit it; the app reloads it when it changes on disk and pushes the relevant keys to
/// Apple's defaults. `VIGNETTE_SETTINGS=<path>` in the environment points the app at another file,
/// so a test run never touches the real one.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    nonisolated static let currentVersion = 2
    static let fileURL: URL = {
        if let path = Launch.settingsPath {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        // A test process never writes the user's file, whoever launched it. The scheme in
        // project.yml sets `VIGNETTE_SETTINGS`, but `xcrun xctest`, a hand-written `.xctestrun`,
        // and CI running the bundle do not go through a scheme, and reading `Settings.shared` from
        // a test bootstraps whatever path this returns. The pid keeps parallel runs apart.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("vignette-test-\(ProcessInfo.processInfo.processIdentifier)/settings.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/\(Identity.urlScheme)/settings.json")
    }()
    static var directory: URL { fileURL.deletingLastPathComponent() }

    @Published private(set) var data: SettingsData { didSet { updateMotion() } }
    var onChange: ((SettingsData, SettingsData) -> Void)?
    /// The system's Reduce Motion switch, kept current by the workspace notification.
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { didSet { updateMotion() } }
    /// Where macOS sends a capture (`AppleScreencapture.target`), kept current by an observer.
    /// Anything but `file` leaves the watch folder with no new screenshots.
    @Published private(set) var appleTarget = AppleScreencapture.target
    private var motionObserver: Any?

    /// 0 to 1: what every animation duration is multiplied by. Reduce Motion makes it 0.
    private(set) var motionScale: Double = 1
    /// The tweaks every animation reads: layout as in `data.ui`, durations scaled by `motionScale`.
    private(set) var motionUI = UITweaks()
    /// What the Settings window says when this launch had to set the file aside. nil when all was well.
    let startupNotice: Notice?

    /// What went wrong with the file, as the General tab says it.
    struct Notice {
        var title: String
        var detail: String
    }

    /// What the General tab says while `lastWriteFailed`.
    static var notSavedNotice: Notice {
        let file = (fileURL.path as NSString).abbreviatingWithTildeInPath
        return Notice(title: "Settings not saved",
                      detail: "Vignette couldn't write to \(file). It tries again with your next change.")
    }
    private var sync: SettingsSync
    private let hold = EventHold<SettingsSync.Event>()
    /// True when nothing is written to the file (`SettingsSync.readOnly`).
    var readOnly: Bool { sync.readOnly }
    /// `SettingsSync.lastWriteFailed`, published for the General tab's warning.
    @Published private(set) var lastWriteFailed = false

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var reloadWork: DispatchWorkItem?
    private var writeWork: DispatchWorkItem?
    private var appleLocation: AppleScreencapture.Observer?
    private var appleTargetObserver: AppleScreencapture.Observer?

    private init() {
        let boot = Settings.bootstrap(at: Settings.fileURL)
        data = boot.data
        startupNotice = boot.notice
        for line in boot.log { Log.write("[settings] \(line)") }
        sync = SettingsSync(bytes: boot.written ?? (try? Data(contentsOf: Settings.fileURL)), data: boot.data,
                            readOnly: boot.readOnly, readOnlyReason: boot.readOnlyReason)
        updateMotion()
        watch()
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Registered with queue: .main, so the notification arrives there.
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                if now != self.reduceMotion { self.reduceMotion = now; Log.write("[settings] reduce motion \(now ? "on" : "off")") }
            }
        }
    }

    private func updateMotion() {
        motionScale = Motion.scale(reduceMotion: reduceMotion, multiplier: data.ui.motion)
        motionUI = data.ui.scaledForMotion(motionScale)
    }

    /// Applies immediately; the file write is coalesced so slider drags do not thrash the disk.
    func update(_ change: (inout SettingsData) -> Void) {
        var next = data
        change(&next)
        apply(next, source: "app")
        send(.appChanged)
    }

    /// Puts Apple's screencapture defaults back to the recorded originals and mirrors them in the
    /// settings so the two do not disagree. Returns what changed, or nil when nothing was recorded.
    func restoreAppleDefaults() -> [String]? {
        guard let original = data.appleOriginal else { return nil }
        var restored: [String] = []
        func put(_ key: String, _ value: Any?) {
            if let value { AppleScreencapture.set(key, value) } else { AppleScreencapture.remove(key) }
            restored.append("\(key)=\(value.map { "\($0)" } ?? "unset")")
        }
        put("location", original.location)
        put("show-thumbnail", original.showThumbnail)
        put("disable-shadow", original.disableShadow)
        put("type", original.type)
        var next = data
        next.screenshotsFolder = AppleScreencapture.location
        next.appleThumbnail = original.showThumbnail ?? true
        next.windowShadow = !(original.disableShadow ?? false)
        next.format = original.type ?? "png"
        apply(next, source: "restore", pushApple: false)
        send(.appChanged)
        return restored
    }

    /// Writes a pending change now. Called on quit so a slider drag's last value is not lost.
    func flush() {
        send(.quit)
    }

    private func apply(_ next: SettingsData, source: String, pushApple: Bool = true) {
        let old = data
        guard next != old else { return }
        data = next
        if next.ui == old.ui { Log.write("[settings] changed via \(source)") }
        if pushApple { pushToApple(old: old, new: next) }
        onChange?(old, next)
    }

    /// Launch: put back Apple's thumbnail if something outside the app turned it on, since it holds
    /// the file past the clipboard fill. Then take macOS's save location as the watch folder, and
    /// keep taking it while the app runs, so a folder picked in ⌘⇧5's Options menu is the one
    /// Vignette watches. `type` and `disable-shadow` are left alone, since both of their values work.
    /// Vignette replaces Apple's thumbnail only while it runs. Quitting puts it back, when Apple
    /// showed it before Vignette, and the next launch's `reconcileApple` takes it away again. So a
    /// person who quits, turns off Open at login, or removes the app is never left with captures
    /// that show nothing.
    func handBackAppleThumbnail() {
        guard !data.appleThumbnail, data.appleOriginal?.showThumbnail ?? true else { return }
        AppleScreencapture.set("show-thumbnail", true)
    }

    func reconcileApple() {
        if (AppleScreencapture.bool("show-thumbnail") ?? true) != data.appleThumbnail {
            AppleScreencapture.set("show-thumbnail", data.appleThumbnail)
            Log.write("[settings] reconciled apple show-thumbnail=\(data.appleThumbnail)")
        }
        followAppleLocation()
        appleLocation = AppleScreencapture.observe("location") { [weak self] in self?.followAppleLocation() }
        appleTargetObserver = AppleScreencapture.observe("target") { [weak self] in
            guard let self, appleTarget != AppleScreencapture.target else { return }
            appleTarget = AppleScreencapture.target
            Log.write("[settings] apple target=\(appleTarget)")
        }
        if appleTarget != "file" { Log.write("[settings] apple target=\(appleTarget): no screenshot reaches the folder") }
    }

    /// Asks macOS to save captures as files again, for someone whose ⌘⇧5 Options sends them to the
    /// Clipboard, Mail or Preview. With Copy to Clipboard on, Vignette still puts each one there.
    func saveCapturesAsFiles() {
        AppleScreencapture.set("target", "file")
        appleTarget = AppleScreencapture.target
    }

    /// Takes Apple's save location as the watch folder when the two differ. Compared expanded,
    /// because Vignette writes the tilde form and Apple's own UI writes a full path. Not written
    /// back to Apple, since that is where it came from.
    private func followAppleLocation() {
        let location = AppleScreencapture.location
        guard !AppleScreencapture.samePath(location, data.screenshotsFolder) else { return }
        var next = data
        next.screenshotsFolder = (URL(fileURLWithPath: (location as NSString).expandingTildeInPath)
            .standardizedFileURL.path as NSString).abbreviatingWithTildeInPath
        Log.write("[settings] following apple location=\(next.screenshotsFolder)")
        apply(next, source: "apple", pushApple: false)
        send(.appChanged)
    }

    /// Keep macOS's screenshot behavior in line with the file. Only touched keys are written.
    private func pushToApple(old: SettingsData, new: SettingsData) {
        if !AppleScreencapture.samePath(new.screenshotsFolder, old.screenshotsFolder) {
            AppleScreencapture.set("location", new.screenshotsFolder)
        }
        if new.appleThumbnail != old.appleThumbnail { AppleScreencapture.set("show-thumbnail", new.appleThumbnail) }
        if new.windowShadow != old.windowShadow { AppleScreencapture.set("disable-shadow", !new.windowShadow) }
        if new.format != old.format { AppleScreencapture.set("type", new.format) }
    }

    private func send(_ event: SettingsSync.Event) {
        // An event sent while effects run (an `onChange` handler's `update`, or the answer to
        // `.writeAppData` or `.readFileAndFlush`) is reduced after the current event's effects.
        hold.send(event) { event in
            let effects = sync.reduce(event)
            if lastWriteFailed != sync.lastWriteFailed { lastWriteFailed = sync.lastWriteFailed }
            for effect in effects { run(effect) }
        }
    }

    /// Reads the file when a timer fires or at quit, not when the timer is set.
    private func sendReadingFile(_ event: (Data?, SettingsData) -> SettingsSync.Event) {
        send(event(try? Data(contentsOf: Settings.fileURL), data))
    }

    private func run(_ effect: SettingsSync.Effect) {
        switch effect {
        case .log(let line):
            Log.write("[settings] \(line)")
        case .apply(let next, let source):
            apply(next, source: source)
        case .write(let raw):
            let failure = Settings.failure(writing: raw, to: Settings.fileURL)
            watchFile()   // atomic write replaced the inode
            send(.wrote(raw, failure: failure))
        case .writeAppData:
            send(.appData(data))
        case .readFileAndFlush:
            sendReadingFile(SettingsSync.Event.flush(file:app:))
        case .scheduleWrite(let delay):
            writeWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.sendReadingFile(SettingsSync.Event.writeDue(file:app:)) }
            writeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        case .cancelWrite:
            writeWork?.cancel()
        case .scheduleReload(let delay):
            reloadWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.sendReadingFile(SettingsSync.Event.reloadDue(file:app:)) }
            reloadWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    /// Editors save atomically (write temp, rename) which only the directory sees; scripts often write
    /// in place, which only the file sees. Watch both, and re-arm the file watch after a rename.
    private func watch() {
        try? FileManager.default.createDirectory(at: Settings.directory, withIntermediateDirectories: true)
        directorySource = makeSource(path: Settings.directory.path, mask: .write) { [weak self] in
            self?.send(.fileChanged)
            self?.watchFile()
        }
        watchFile()
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = makeSource(path: Settings.fileURL.path, mask: [.write, .extend, .delete, .rename]) { [weak self] in
            self?.send(.fileChanged)
        }
    }

    private func makeSource(path: String, mask: DispatchSource.FileSystemEvent, handler: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        src.setEventHandler(handler: handler)
        src.setCancelHandler { close(fd) }
        src.resume()
        return src
    }
}
