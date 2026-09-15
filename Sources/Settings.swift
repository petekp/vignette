import AppKit
import SwiftUI
import Combine

struct Screenshot {
    let url: URL
}

/// Everything a user changes per machine. Lives in ~/.config/shotnote/settings.json.
/// Missing keys fall back to defaults, so a partial file is fine.
struct SettingsData: Codable, Equatable {
    var screenshotsFolder = "~/Desktop"      // where Cmd+Shift+3/4/5 saves and what Shotnote watches
    var syncAppleSaveLocation = true         // write screenshotsFolder to Apple's screencapture location
    var appleThumbnail = true                // Apple's floating thumbnail; off means the file lands immediately
    var windowShadow = true                  // Apple's window-capture shadow
    var format = "png"                       // png or jpg
    var recentCount = 5                      // cards in the recent stack
    var recentHotkey = "cmd+shift+6"         // opens the recent stack
    var hideMenuBarIcon = false              // shotnote://settings still opens the window
    var ui = UITweaks()                      // visual and timing knobs; the debug panel edits these live

    var folderURL: URL { URL(fileURLWithPath: (screenshotsFolder as NSString).expandingTildeInPath) }

    /// First run: mirror what macOS is already doing so nothing changes until the user asks.
    static func fromSystem() -> SettingsData {
        var d = SettingsData()
        if let loc = AppleScreencapture.string("location") { d.screenshotsFolder = loc }
        d.appleThumbnail = AppleScreencapture.bool("show-thumbnail") ?? true
        d.windowShadow = !(AppleScreencapture.bool("disable-shadow") ?? false)
        d.format = AppleScreencapture.string("type") ?? "png"
        return d
    }
}

/// Layout, styling, timing, and backdrop parameters. All in points and seconds.
struct UITweaks: Codable, Equatable {
    // Cards
    var cardMaxWidth = 220.0
    var cardMaxHeight = 150.0
    var cardMinSide = 56.0
    var cardSpacing = 10.0
    var panelInset = 24.0            // room for shadows inside the panel
    var screenMargin = 16.0          // distance from the screen corner
    var cardCornerRadius = 8.0
    var cardBorderWidth = 1.0
    var cardBorderOpacity = 0.7
    var cardShadowRadius = 14.0
    var cardShadowOpacity = 0.35
    var cardShadowY = 6.0
    var hoverScale = 1.03
    // Hover buttons and selection
    var buttonSize = 28.0
    var buttonIconSize = 12.0
    var buttonSpacing = 8.0
    var buttonBottomPadding = 8.0
    var buttonOpacity = 0.6
    var buttonHoverOpacity = 0.85
    var selectionCircleSize = 22.0
    var selectionBarHeight = 36.0
    // Timings
    var thumbnailSeconds = 5.0       // how long a fresh thumbnail stays
    var toastSeconds = 1.4
    var slideInDuration = 0.4
    var slideInCurve = "spring"      // spring, easeOut, easeInOut, linear
    var slideOutDuration = 0.3
    var staggerDelay = 0.05
    var relayoutDuration = 0.2
    var expandDuration = 0.38
    var hoverRevealDuration = 0.15
    // Backdrop
    var backdropWidth = 440.0
    var backdropTint = 0.3           // darkness at the right edge, 0 to 1
    var backdropTintStart = 0.0      // where the tint begins, 0 = left edge, 1 = right edge
    var backdropBlurRadius = 40.0    // at the right edge
    var backdropBands = 6            // effect views in the blur ramp
    var backdropRampPower = 2.0      // 1 = linear radius growth, higher keeps the left sharper
    var backdropFadeIn = 0.35
    var backdropFadeOut = 0.3
    // Annotator window
    var annotationMinWidth = 480.0
    var annotationMinHeight = 140.0
    var annotationCornerRadius = 10.0
    var annotationScreenInset = 60.0
}

/// The settings file is the source of truth. The Settings window, the debug panel, agents, and
/// dotfiles all edit it; the app reloads it when it changes on disk and pushes the relevant keys to
/// Apple's defaults.
final class Settings: ObservableObject {
    static let shared = Settings()
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/shotnote")
    static let fileURL = directory.appendingPathComponent("settings.json")

    @Published private(set) var data: SettingsData
    var onChange: ((SettingsData, SettingsData) -> Void)?

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var lastWritten: Data?
    private var reloadWork: DispatchWorkItem?
    private var writeWork: DispatchWorkItem?

    private init() {
        if let loaded = Settings.read() {
            data = loaded
            // Fill in any keys the file lacks so every knob is visible to whoever edits it next.
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let full = try? enc.encode(loaded), full != (try? Data(contentsOf: Settings.fileURL)) { writeNow(loaded) }
        } else {
            data = SettingsData.fromSystem()
            writeNow(data)
            Log.write("[settings] created \(Settings.fileURL.path)")
        }
        watch()
    }

    /// Applies immediately; the file write is coalesced so slider drags do not thrash the disk.
    func update(_ change: (inout SettingsData) -> Void) {
        var next = data
        change(&next)
        apply(next, source: "app")
        writeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in guard let self else { return }; self.writeNow(self.data) }
        writeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func apply(_ next: SettingsData, source: String) {
        let old = data
        guard next != old else { return }
        data = next
        if next.ui == old.ui { Log.write("[settings] changed via \(source)") }
        pushToApple(old: old, new: next)
        onChange?(old, next)
    }

    /// Keep macOS's screenshot behavior in line with the file. Only touched keys are written.
    private func pushToApple(old: SettingsData, new: SettingsData) {
        if new.syncAppleSaveLocation && (new.screenshotsFolder != old.screenshotsFolder || !old.syncAppleSaveLocation) {
            AppleScreencapture.set("location", new.screenshotsFolder)
        }
        if new.appleThumbnail != old.appleThumbnail { AppleScreencapture.set("show-thumbnail", new.appleThumbnail) }
        if new.windowShadow != old.windowShadow { AppleScreencapture.set("disable-shadow", !new.windowShadow) }
        if new.format != old.format { AppleScreencapture.set("type", new.format) }
    }

    // MARK: File

    /// Reads the file over the defaults, so missing keys (including whole sections) keep their defaults.
    private static func read() -> SettingsData? {
        guard let raw = try? Data(contentsOf: fileURL) else { return nil }
        do {
            guard let fromFile = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else { throw CocoaError(.coderInvalidValue) }
            let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SettingsData())) as! [String: Any]
            let merged = try JSONSerialization.data(withJSONObject: deepMerge(defaults, fromFile))
            return try JSONDecoder().decode(SettingsData.self, from: merged)
        } catch {
            Log.write("[settings] could not parse \(fileURL.path): \(error)")
            return nil
        }
    }

    private static func deepMerge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var out = base
        for (k, v) in over {
            if let b = base[k] as? [String: Any], let o = v as? [String: Any] { out[k] = deepMerge(b, o) } else { out[k] = v }
        }
        return out
    }

    private func writeNow(_ d: SettingsData) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? enc.encode(d) else { return }
        try? FileManager.default.createDirectory(at: Settings.directory, withIntermediateDirectories: true)
        lastWritten = raw
        try? raw.write(to: Settings.fileURL, options: .atomic)
        watchFile()   // atomic write replaced the inode
    }

    /// Editors save atomically (write temp, rename) which only the directory sees; scripts often write
    /// in place, which only the file sees. Watch both, and re-arm the file watch after a rename.
    private func watch() {
        try? FileManager.default.createDirectory(at: Settings.directory, withIntermediateDirectories: true)
        directorySource = makeSource(path: Settings.directory.path, mask: .write) { [weak self] in
            self?.scheduleReload()
            self?.watchFile()
        }
        watchFile()
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = makeSource(path: Settings.fileURL.path, mask: [.write, .extend, .delete, .rename]) { [weak self] in
            self?.scheduleReload()
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

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reloadFromDisk() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func reloadFromDisk() {
        guard let raw = try? Data(contentsOf: Settings.fileURL), raw != lastWritten else { return }
        guard let parsed = Settings.read() else {
            Log.write("[settings] file changed but does not parse; keeping current settings")
            return
        }
        apply(parsed, source: "file")
    }
}

/// Apple's screenshot defaults (`defaults read com.apple.screencapture`).
enum AppleScreencapture {
    private static let domain = "com.apple.screencapture" as CFString

    static func string(_ key: String) -> String? { CFPreferencesCopyAppValue(key as CFString, domain) as? String }
    static func bool(_ key: String) -> Bool? { CFPreferencesCopyAppValue(key as CFString, domain) as? Bool }

    static func set(_ key: String, _ value: Any) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList, domain)
        CFPreferencesAppSynchronize(domain)
        Log.write("[settings] apple \(key)=\(value)")
    }
}

/// Animation helper honoring the tweakable curves.
enum Anim {
    static func timing(_ curve: String) -> CAMediaTimingFunction {
        switch curve {
        case "easeOut": return CAMediaTimingFunction(name: .easeOut)
        case "easeInOut": return CAMediaTimingFunction(name: .easeInEaseOut)
        case "linear": return CAMediaTimingFunction(name: .linear)
        default: return CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)   // "spring"
        }
    }

    static func swiftUI(_ curve: String, duration: Double) -> Animation {
        switch curve {
        case "easeOut": return .easeOut(duration: duration)
        case "easeInOut": return .easeInOut(duration: duration)
        case "linear": return .linear(duration: duration)
        default: return .timingCurve(0.2, 0.9, 0.3, 1.0, duration: duration)   // "spring"
        }
    }

    static func run(_ duration: Double, curve: String = "easeOut", _ body: () -> Void, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = timing(curve)
            body()
        }, completionHandler: completion)
    }
}
