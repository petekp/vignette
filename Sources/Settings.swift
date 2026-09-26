import AppKit
import SwiftUI
import Combine
@preconcurrency import CoreFoundation

struct Screenshot: Sendable {
    let url: URL

    /// A still image, or a screen recording from Cmd+Shift+5.
    enum Kind: Sendable { case image, recording }

    /// Read from the extension alone. The name says nothing: macOS names screenshots and recordings
    /// from the same `com.apple.screencapture name` default, which is the user's to change.
    var kind: Kind { Screenshot.recordingExtensions.contains(url.pathExtension.lowercased()) ? .recording : .image }

    /// What Cmd+Shift+5 writes (docs/replacing-apple-capture-2026-09-22.md).
    static let recordingExtensions: Set<String> = ["mov"]
}

/// Whether the app has offered the agent skill yet. Whether the skill is installed is read from
/// disk, so the key only records that the offer was made. `on` is what older files hold; it is
/// read as `off` (`validated()`).
enum AgentSkill: String {
    case unasked
    case on
    case off
}

/// Whether the first-run setup window has had its turn. Recorded when the window closes, so a
/// launch that is quit part way through asks again.
enum SetupState: String {
    case unasked
    case done
}

/// Everything a user changes per machine. Lives in ~/.config/vignette/settings.json.
/// Missing keys fall back to defaults, so a partial file is fine.
struct SettingsData: Codable, Equatable {
    var version = Settings.currentVersion    // file format version; `Settings.migrate` brings older files up
    var screenshotsFolder = "~/Desktop"      // where Cmd+Shift+3/4/5 saves and what Vignette watches; follows Apple's location
    var appleThumbnail = true                // Apple's floating thumbnail; off means the file lands immediately
    var windowShadow = true                  // Apple's window-capture shadow
    var format = "png"                       // png or jpg
    var recentCount = 30                      // cards in the recent stack
    var recentHotkey = "double-rshift"       // opens the recent stack; needs Accessibility, which setup asks for
    var hideMenuBarIcon = false              // vignette://settings still opens the window
    var launchAtLogin = false                // registers the app as a login item (System Settings > Login Items)
    var quickAnnotate = false                // Done copies the result and closes the annotator and the stack at once
    var sendWithReturn = false               // Return in the message field beside Send sends; ⌘Return always does
    var annotateOnCapture = false            // a new capture opens in the annotator instead of showing a thumbnail
    var copyOnCapture = true                 // a new capture goes to the clipboard as it lands
    var debug = false                        // unlocks tweaks, install-skill root=, and file= outside the watch folder
    var agentSkill = AgentSkill.unasked.rawValue  // whether the skill was offered: unasked, then off
    var setup = SetupState.unasked.rawValue  // whether the setup window has run: unasked, then done
    var ui = UITweaks()                      // visual and timing knobs; the debug panel edits these live
    var appleOriginal: AppleOriginal?        // Apple's screencapture values before Vignette changed them

    var folderURL: URL { URL(fileURLWithPath: (screenshotsFolder as NSString).expandingTildeInPath) }

    /// `agentSkill` as the states it holds. An unknown word reads as `unasked`, which
    /// `validated()` then writes back.
    var agentSkillChoice: AgentSkill { AgentSkill(rawValue: agentSkill) ?? .unasked }

    /// `setup` as the states it holds. An unknown word reads as `unasked`.
    var setupChoice: SetupState { SetupState(rawValue: setup) ?? .unasked }

    /// Whether the shortcut is a modifier double tap rather than a key combination. Three places
    /// ask, and each one parsing the string itself is how they drift apart.
    var usesDoubleTap: Bool {
        if case .doubleTap = HotKeySpec.parse(recentHotkey) { return true }
        return false
    }

    /// What picking "Key combination" writes. The default shortcut is the double tap, so this
    /// cannot be read off a fresh `SettingsData`.
    static let defaultKeyCombination = "cmd+shift+6"

    /// Clamps values that would crash or break layout math and reports each correction.
    /// Design limits live in the debug panel; these are only the bounds the code cannot survive.
    func validated() -> (data: SettingsData, corrections: [String]) {
        var d = self
        var notes: [String] = []
        if d.recentCount < 0 || d.recentCount > 1000 {
            let fixed = min(max(d.recentCount, 0), 1000)
            notes.append("recentCount \(d.recentCount) -> \(fixed)"); d.recentCount = fixed
        }
        if d.screenshotsFolder.trimmingCharacters(in: .whitespaces).isEmpty {
            notes.append("screenshotsFolder \"\" -> \"~/Desktop\""); d.screenshotsFolder = "~/Desktop"
        }
        if AgentSkill(rawValue: d.agentSkill) == nil {
            notes.append("agentSkill \"\(d.agentSkill)\" -> \"\(AgentSkill.unasked.rawValue)\""); d.agentSkill = AgentSkill.unasked.rawValue
        }
        // `on` used to install at every launch. The Agents tab installs per agent now and disk says
        // what is there, so the key only records that the offer was made.
        if d.agentSkillChoice == .on {
            notes.append("agentSkill \"on\" -> \"off\""); d.agentSkill = AgentSkill.off.rawValue
        }
        if SetupState(rawValue: d.setup) == nil {
            notes.append("setup \"\(d.setup)\" -> \"\(SetupState.unasked.rawValue)\""); d.setup = SetupState.unasked.rawValue
        }
        if !["spring", "easeOut", "easeInOut", "linear"].contains(d.ui.slideInCurve) {
            notes.append("ui.slideInCurve \"\(d.ui.slideInCurve)\" -> \"spring\""); d.ui.slideInCurve = "spring"
        }
        if d.ui.backdropBands < 1 || d.ui.backdropBands > 64 {
            let fixed = min(max(d.ui.backdropBands, 1), 64)
            notes.append("ui.backdropBands \(d.ui.backdropBands) -> \(fixed)"); d.ui.backdropBands = fixed
        }
        for bound in UITweaks.bounds {
            let value = d.ui[keyPath: bound.path]
            let fixed = value.isFinite ? min(max(value, bound.range.lowerBound), bound.range.upperBound) : UITweaks()[keyPath: bound.path]
            if fixed != value { notes.append("ui.\(bound.name) \(value) -> \(fixed)"); d.ui[keyPath: bound.path] = fixed }
        }
        return (d, notes)
    }

    /// First run: mirror what macOS is already doing so nothing changes until the user asks.
    static func fromSystem() -> SettingsData {
        var d = SettingsData()
        d.screenshotsFolder = AppleScreencapture.location
        d.appleThumbnail = AppleScreencapture.bool("show-thumbnail") ?? true
        d.windowShadow = !(AppleScreencapture.bool("disable-shadow") ?? false)
        d.format = AppleScreencapture.string("type") ?? "png"
        return d
    }
}

/// Layout, styling, timing, and backdrop parameters. All in points and seconds.
struct UITweaks: Codable, Equatable {
    // Cards
    var cardMaxWidth = 208.0
    var cardMaxHeight = 86.0
    var cardMinSide = 114.0
    var cardSpacing = 10.0
    var panelInset = 19.0            // room for shadows inside the panel
    var screenMargin = 17.0          // distance from the screen corner
    var stackMinScale = 0.5          // how narrow the stack goes to make room for the annotator
    var stackGap = 24.0              // the stack keeps this much between itself and the annotator
    var cardCornerRadius = 12.0
    var cardBorderWidth = 2.0
    var cardBorderOpacity = 0.35
    var cardShadowRadius = 4.0
    var cardShadowOpacity = 0.5
    var cardShadowY = 6.0
    var hoverScale = 1.06
    var pressScale = 0.96
    var hoverDim = 0.35             // darkening of a hovered card behind its buttons
    // Hover buttons and selection
    var buttonSize = 27.0
    var buttonIconSize = 11.0
    var buttonSpacing = 4.0
    var selectionCircleSize = 19.0
    var selectionBarHeight = 44.0    // the toast row under the column
    var selectionStripGap = 16.0     // the widest selected card to the control strip beside it
    var autoScrollZone = 44.0        // band at each end of the column where a drag-select scrolls it
    var autoScrollSpeed = 600.0      // points a second at the very edge of that band
    // Timings
    var thumbnailSeconds = 5.0       // how long a fresh thumbnail stays
    var toastSeconds = 1.7
    var slideInDuration = 0.75
    var slideInCurve = "spring"      // spring, easeOut, easeInOut, linear
    var slideOutDuration = 0.3
    var staggerDelay = 0.05
    var staggerTotalMax = 0.3        // the last card never starts later than this
    var relayoutDuration = 0.2
    var insertDuration = 0.5         // one card joining a visible stack: its slide and the room the others make
    var expandDuration = 0.25
    var hoverRevealDuration = 0.15
    // A flight between a stack slot and the annotator, bowed and swelled by FlightCurve
    var flightArc = 0.08             // how far the path bows, as a fraction of its length
    var flightArcMax = 64.0          // the bow never exceeds this many points
    var flightDepth = 0.05           // how much larger the card is in the middle of the path
    var motion = 1.0                 // multiplier on every animation, 0 to 1; Reduce Motion forces 0
    // Backdrop
    var backdropWidth = 290.0
    var backdropTint = 0.0           // darkness at the right edge, 0 to 1
    var backdropTintStart = 0.0      // where the tint begins, 0 = left edge, 1 = right edge
    var backdropBlurRadius = 13.0    // at the right edge
    var backdropBands = 3            // effect views in the blur ramp
    var backdropRampPower = 2.0      // 1 = linear radius growth, higher keeps the left sharper
    var backdropFadeIn = 0.35
    var backdropFadeOut = 0.35
    var backdropSlideIn = 0.5           // the strip slides in from the screen edge while it fades
    var backdropSlideOut = 0.3
    var dimOpacity = 0.5             // screen darkening behind the annotator
    var dimBlurRadius = 12.0
    var dimFade = 0.4                // the spring settles within this
    // Annotator window
    var annotationMinWidth = 770.0
    var annotationMinHeight = 320.0
    var annotationCornerRadius = 10.0
    var annotationToolbarGap = 12.0
    var annotationScreenInset = 65.0
    var zoomEdgeBandPoints = 120.0   // how far from each edge of the picture a zoom holds that edge
    var zoomEdgePull = 0.5           // the part of that band in which the edge is held exactly
    // The editor (`EditorMetrics`): screen pt, the same size at any zoom, unless it says otherwise
    var dragDistance = 4.0           // how far a press travels before it is a drag
    var hitMargin = 4.0              // added to a stroke's half-width to make its hit band
    var cornerHitSize = 13.5         // a corner handle's hit area, a square centred on the corner
    var edgeHitSize = 9.0            // an edge handle's hit area, a strip along the whole side
    var smallSide = 16.0             // a mark shorter than this keeps its handles' hit areas outside it
    var handleSize = 8.0             // the corner square drawn
    var dotRadius = 4.0              // an arrow dot's drawn radius
    var dotHitRadius = 12.0          // an arrow dot's hit radius, and its halo's
    var smallestRectangle = 4.0      // a new rectangle's shortest side
    var shortestArrow = 8.0          // a new arrow's shortest length
    var textDragDelay = 0.15         // seconds a Text tool press waits before a sideways drag sets a wrap width; a threshold, not motion
    var textDragDistance = 24.0      // and the sideways travel it needs
    var newTextSize = 24.0           // pt of the drawing, not of the screen
    var selectionOutlineWidth = 3.5  // the whole outline, light edge included; it runs this far outside a mark
    // Marks
    var textWeight = 500.0           // 100 Ultralight to 900 Black, as the nearest of the system font's nine weights
    var textLineHeight = 1.35        // a multiple of the text's size
    var arrowheadLength = 4.5        // multiples of the stroke width
    var arrowheadWidth = 4.0
    // Stitch
    var stitchLongSide = 4096.0      // a composition longer than this is scaled down to it

    /// One entry of `bounds`. A plain struct, not a tuple, so the array can be `Sendable`.
    /// `@unchecked`: `WritableKeyPath` isn't marked `Sendable` in the standard library, but key
    /// paths are immutable value descriptors and safe to share across threads.
    struct Bound: @unchecked Sendable {
        let name: String
        let path: WritableKeyPath<UITweaks, Double>
        let range: ClosedRange<Double>
        init(_ name: String, _ path: WritableKeyPath<UITweaks, Double>, _ range: ClosedRange<Double>) {
            self.name = name; self.path = path; self.range = range
        }
    }

    /// The same tweaks with every animation scaled: the durations, and how far a flight bows and
    /// swells. Dwell times (`thumbnailSeconds`, `toastSeconds`) are not motion and stay as they
    /// are, and `flightArcMax` is a limit on the bow rather than an amount of it.
    func scaledForMotion(_ scale: Double) -> UITweaks {
        var u = self
        u.slideInDuration *= scale; u.slideOutDuration *= scale
        u.staggerDelay *= scale; u.staggerTotalMax *= scale
        u.relayoutDuration *= scale; u.insertDuration *= scale; u.expandDuration *= scale; u.hoverRevealDuration *= scale
        u.backdropFadeIn *= scale; u.backdropFadeOut *= scale; u.dimFade *= scale
        u.backdropSlideIn *= scale; u.backdropSlideOut *= scale
        u.flightArc *= scale; u.flightDepth *= scale
        return u
    }

    /// Bounds outside which a value crashes, divides by zero, or makes NaN. Not design limits.
    static let bounds: [Bound] = [
        Bound("cardMaxWidth", \.cardMaxWidth, 1...10_000), Bound("cardMaxHeight", \.cardMaxHeight, 1...10_000),
        Bound("cardMinSide", \.cardMinSide, 1...10_000), Bound("cardSpacing", \.cardSpacing, 0...1000),
        Bound("panelInset", \.panelInset, 0...1000), Bound("screenMargin", \.screenMargin, 0...10_000),
        Bound("stackMinScale", \.stackMinScale, 0.3...1), Bound("stackGap", \.stackGap, 0...1000),
        Bound("cardCornerRadius", \.cardCornerRadius, 0...1000), Bound("cardBorderWidth", \.cardBorderWidth, 0...100),
        Bound("cardBorderOpacity", \.cardBorderOpacity, 0...1), Bound("cardShadowRadius", \.cardShadowRadius, 0...1000),
        Bound("cardShadowOpacity", \.cardShadowOpacity, 0...1), Bound("cardShadowY", \.cardShadowY, -1000...1000),
        Bound("hoverScale", \.hoverScale, 0.1...10), Bound("pressScale", \.pressScale, 0.1...10), Bound("hoverDim", \.hoverDim, 0...1),
        Bound("buttonSize", \.buttonSize, 1...1000), Bound("buttonIconSize", \.buttonIconSize, 1...1000),
        Bound("buttonSpacing", \.buttonSpacing, 0...1000), Bound("selectionCircleSize", \.selectionCircleSize, 1...1000),
        Bound("selectionBarHeight", \.selectionBarHeight, 1...1000),
        Bound("selectionStripGap", \.selectionStripGap, 0...1000),
        Bound("autoScrollZone", \.autoScrollZone, 0...10_000), Bound("autoScrollSpeed", \.autoScrollSpeed, 0...10_000),
        Bound("thumbnailSeconds", \.thumbnailSeconds, 0...3600), Bound("toastSeconds", \.toastSeconds, 0...3600),
        Bound("slideInDuration", \.slideInDuration, 0...60), Bound("slideOutDuration", \.slideOutDuration, 0...60),
        Bound("staggerDelay", \.staggerDelay, 0...60), Bound("staggerTotalMax", \.staggerTotalMax, 0...60),
        Bound("relayoutDuration", \.relayoutDuration, 0...60), Bound("insertDuration", \.insertDuration, 0...60),
        Bound("expandDuration", \.expandDuration, 0...60),
        Bound("hoverRevealDuration", \.hoverRevealDuration, 0...60), Bound("motion", \.motion, 0...1),
        Bound("flightArc", \.flightArc, 0...1), Bound("flightArcMax", \.flightArcMax, 0...2000),
        Bound("flightDepth", \.flightDepth, 0...1),
        Bound("backdropWidth", \.backdropWidth, 1...10_000), Bound("backdropTint", \.backdropTint, 0...1),
        Bound("backdropTintStart", \.backdropTintStart, 0...1), Bound("backdropBlurRadius", \.backdropBlurRadius, 0...1000),
        Bound("backdropRampPower", \.backdropRampPower, 0.01...100), Bound("backdropFadeIn", \.backdropFadeIn, 0...60),
        Bound("backdropSlideIn", \.backdropSlideIn, 0...60), Bound("backdropSlideOut", \.backdropSlideOut, 0...60),
        Bound("backdropFadeOut", \.backdropFadeOut, 0...60), Bound("dimOpacity", \.dimOpacity, 0...1), Bound("dimBlurRadius", \.dimBlurRadius, 0...1000), Bound("dimFade", \.dimFade, 0...60),
        Bound("annotationMinWidth", \.annotationMinWidth, 1...100_000), Bound("annotationMinHeight", \.annotationMinHeight, 1...100_000),
        Bound("annotationCornerRadius", \.annotationCornerRadius, 0...1000), Bound("annotationToolbarGap", \.annotationToolbarGap, 0...1000),
        Bound("annotationScreenInset", \.annotationScreenInset, 0...10_000),
        // `Zoom.pulledToEdges` caps the band at half a side, so any value past a frame's own size
        // behaves the same; this is that, not a design limit. 0...400 is the slider's range.
        Bound("zoomEdgeBandPoints", \.zoomEdgeBandPoints, 0...2000), Bound("zoomEdgePull", \.zoomEdgePull, 0...1),
        Bound("dragDistance", \.dragDistance, 0...1000), Bound("hitMargin", \.hitMargin, 0...1000),
        Bound("cornerHitSize", \.cornerHitSize, 0...1000), Bound("edgeHitSize", \.edgeHitSize, 0...1000),
        Bound("smallSide", \.smallSide, 0...10_000), Bound("handleSize", \.handleSize, 0...1000),
        Bound("dotRadius", \.dotRadius, 0...1000), Bound("dotHitRadius", \.dotHitRadius, 0...1000),
        Bound("smallestRectangle", \.smallestRectangle, 0...10_000), Bound("shortestArrow", \.shortestArrow, 0...10_000),
        Bound("textDragDelay", \.textDragDelay, 0...60), Bound("textDragDistance", \.textDragDistance, 0...10_000),
        // A drawing file refuses a text larger than `Mark.Text.maxSize`, so a new one past it would be
        // dropped when the drawing is read again.
        Bound("newTextSize", \.newTextSize, 1...Double(Mark.Text.maxSize)),
        Bound("selectionOutlineWidth", \.selectionOutlineWidth, 0...1000),
        Bound("textWeight", \.textWeight, 100...900), Bound("textLineHeight", \.textLineHeight, 0.1...10),
        Bound("arrowheadLength", \.arrowheadLength, 0...100), Bound("arrowheadWidth", \.arrowheadWidth, 0...100),
        // The floor is the slider's, because below it a stitch is not a smaller picture but a
        // useless one: four wide captures at 64 come out a 64 x 1 PNG the app still reports as ok.
        Bound("stitchLongSide", \.stitchLongSide, 512...20_000),
    ]
}

extension UITweaks {
    var editorMetrics: EditorMetrics {
        EditorMetrics(dragDistance: dragDistance, hitMargin: hitMargin, cornerHitSize: cornerHitSize, edgeHitSize: edgeHitSize,
                      smallSide: smallSide, handleSize: handleSize, dotRadius: dotRadius, dotHitRadius: dotHitRadius,
                      smallestRectangle: smallestRectangle, shortestArrow: shortestArrow, textDragDelay: textDragDelay,
                      textDragDistance: textDragDistance, newTextSize: newTextSize, selectionOutlineWidth: selectionOutlineWidth)
    }

    /// The style every text is set in. The system font draws only its nine named weights, whatever
    /// weight it is asked for (measured on macOS 15), so `textWeight` picks one: 100 is the first.
    var textStyle: TextStyle {
        let weights: [NSFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        let weight = textWeight.isFinite ? min(max(textWeight, 100), 900) : UITweaks().textWeight
        return TextStyle(weight: weights[Int((weight / 100).rounded()) - 1], lineHeight: textLineHeight)
    }

    var arrowhead: ArrowheadStyle { ArrowheadStyle(length: arrowheadLength, width: arrowheadWidth) }
}

/// The `com.apple.screencapture` values Vignette found before it wrote any of its own, so
/// `vignette://restore-apple-defaults` can put them back. nil means the key was not set.
struct AppleOriginal: Codable, Equatable {
    var location: String?
    var showThumbnail: Bool?
    var disableShadow: Bool?
    var type: String?

    static func capture() -> AppleOriginal {
        AppleOriginal(location: AppleScreencapture.string("location"),
                      showThumbnail: AppleScreencapture.bool("show-thumbnail"),
                      disableShadow: AppleScreencapture.bool("disable-shadow"),
                      type: AppleScreencapture.string("type"))
    }
}

/// The settings file is the source of truth. The Settings window, the debug panel, agents, and
/// dotfiles all edit it; the app reloads it when it changes on disk and pushes the relevant keys to
/// Apple's defaults. `VIGNETTE_SETTINGS=<path>` in the environment points the app at another file,
/// so a test run never touches the real one.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    nonisolated static let currentVersion = 1
    static let isOverridden = ProcessInfo.processInfo.environment["VIGNETTE_SETTINGS"].map { !$0.isEmpty } ?? false
    static let fileURL: URL = {
        if let path = ProcessInfo.processInfo.environment["VIGNETTE_SETTINGS"], !path.isEmpty {
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
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/vignette/settings.json")
    }()
    static var directory: URL { fileURL.deletingLastPathComponent() }

    @Published private(set) var data: SettingsData
    var onChange: ((SettingsData, SettingsData) -> Void)?
    /// The system's Reduce Motion switch, kept current by the workspace notification.
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var motionObserver: Any?

    /// 0 to 1: what every animation duration is multiplied by. Reduce Motion makes it 0.
    var motionScale: Double { Motion.scale(reduceMotion: reduceMotion, multiplier: data.ui.motion) }
    /// The tweaks every animation reads: layout as in `data.ui`, durations scaled by `motionScale`.
    var motionUI: UITweaks { data.ui.scaledForMotion(motionScale) }
    /// One sentence for a toast at launch when the file had to be set aside. nil when all was well.
    let startupNotice: String?
    /// True when the file was written by a newer Vignette. Writes would drop its keys, so none happen.
    private(set) var readOnly = false

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var lastWritten: Data?
    private var lastWrittenData: SettingsData?
    private var reloadWork: DispatchWorkItem?
    private var writeWork: DispatchWorkItem?
    private var appleLocation: AppleScreencapture.Observer?

    private init() {
        let boot = Settings.bootstrap(at: Settings.fileURL)
        data = boot.data
        startupNotice = boot.notice
        readOnly = boot.readOnly
        for line in boot.log { Log.write("[settings] \(line)") }
        if let written = boot.written { lastWritten = written }
        lastWrittenData = boot.data
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

    /// What loading the file produced, before any of it reaches the app.
    struct Bootstrap {
        var data: SettingsData
        var log: [String] = []
        var notice: String?
        var readOnly = false
        var written: Data?
    }

    /// Reads, migrates, validates, and repairs the file at `url`. A missing file is created from
    /// Apple's current values. An invalid file is set aside as `<name>.invalid`, never overwritten,
    /// and replaced by the same first-run defaults. A file from a newer version is used read-only.
    static func bootstrap(at url: URL) -> Bootstrap {
        switch load(url) {
        case .loaded(var loaded):
            var boot = Bootstrap(data: loaded.data, log: loaded.log)
            if loaded.fileVersion > currentVersion {
                boot.readOnly = true
                boot.log.append("warning file version \(loaded.fileVersion) is newer than this build's \(currentVersion); not writing to it")
                let validated = loaded.data.validated()
                boot.data = validated.data
                boot.log += validated.corrections.map { "warning clamped \($0)" }
                return boot
            }
            if loaded.data.appleOriginal == nil {
                loaded.data.appleOriginal = AppleOriginal.capture()
                boot.log.append("recorded Apple's screencapture values as appleOriginal at this launch")
            }
            // Fill in any keys the file lacks so every knob is visible to whoever edits it next.
            if let full = try? encoder().encode(loaded.data), full != (try? Data(contentsOf: url)) {
                boot.written = write(full, to: url)
            }
            let validated = loaded.data.validated()
            boot.data = validated.data
            boot.log += validated.corrections.map { "warning clamped \($0)" }
            return boot
        case .missing:
            var d = SettingsData.fromSystem()
            d.appleOriginal = AppleOriginal.capture()
            // Installing Vignette is choosing what happens after a capture, so the one Apple
            // behavior it replaces goes off here. Apple's thumbnail withholds the file for about
            // 5.6 seconds (docs/replacing-apple-capture-2026-09-22.md), which makes copy on capture
            // paste what was on the clipboard before. `appleOriginal` above holds the way back.
            d.appleThumbnail = false
            // With Apple's thumbnail off, a restart that does not bring Vignette back leaves every
            // capture silent. The setup window shows this switch, and closing it registers the item.
            d.launchAtLogin = true
            var boot = Bootstrap(data: d)
            boot.written = (try? encoder().encode(d)).flatMap { write($0, to: url) }
            boot.log.append("created \(url.path)")
            return boot
        case .invalid(let reason):
            let aside = url.appendingPathExtension("invalid")
            try? FileManager.default.removeItem(at: aside)
            let moved = (try? FileManager.default.moveItem(at: url, to: aside)) != nil
            var d = SettingsData.fromSystem()
            d.appleOriginal = AppleOriginal.capture()
            var boot = Bootstrap(data: d)
            boot.log.append("error settings-invalid \(url.path): \(reason)")
            if moved {
                boot.log.append("moved the invalid file to \(aside.path) and replaced it with defaults")
                boot.written = (try? encoder().encode(d)).flatMap { write($0, to: url) }
                boot.notice = "settings.json did not parse; kept as settings.json.invalid, defaults in use"
            } else {
                boot.log.append("could not move the invalid file aside; running on defaults without writing")
                boot.readOnly = true
                boot.notice = "settings.json did not parse; running on defaults"
            }
            return boot
        }
    }

    enum Load {
        case missing
        case invalid(String)
        case loaded(Loaded)
    }

    struct Loaded {
        var data: SettingsData
        var fileVersion: Int
        var log: [String] = []
    }

    /// Reads the file over the defaults, so missing keys (including whole sections) keep their
    /// defaults. Distinguishes a missing file from one that does not parse.
    static func load(_ url: URL) -> Load {
        guard let raw = try? Data(contentsOf: url) else { return .missing }
        do {
            guard let fromFile = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
                return .invalid("top level is not an object")
            }
            if let version = fromFile["version"], !(version is NSNumber) { return .invalid("version is not a number") }
            let migrated = migrate(fromFile)
            let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SettingsData())) as! [String: Any]
            let merged = try JSONSerialization.data(withJSONObject: deepMerge(defaults, migrated.json))
            var loaded = Loaded(data: try JSONDecoder().decode(SettingsData.self, from: merged), fileVersion: migrated.from)
            if migrated.from < currentVersion { loaded.log.append("migrated from version \(migrated.from) to \(currentVersion)") }
            return .loaded(loaded)
        } catch {
            return .invalid(String(describing: error).replacingOccurrences(of: "\n", with: " "))
        }
    }

    /// Brings a file's raw JSON up to `currentVersion`. Files with no `version` are version 0.
    /// A file from a newer version is returned unchanged. Version 1 only introduced the version
    /// field, so there is nothing to rewrite yet; a bump that changes a key rewrites it here,
    /// between the guard and the stamp, one step per version.
    static func migrate(_ raw: [String: Any]) -> (json: [String: Any], from: Int) {
        var json = raw
        let from = (json["version"] as? NSNumber)?.intValue ?? 0
        guard from < currentVersion else { return (json, from) }
        json["version"] = currentVersion
        return (json, from)
    }

    /// Applies immediately; the file write is coalesced so slider drags do not thrash the disk.
    func update(_ change: (inout SettingsData) -> Void) {
        var next = data
        change(&next)
        apply(next, source: "app")
        scheduleWrite()
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
        scheduleWrite()
        return restored
    }

    /// Writes a pending change now. Called on quit so a slider drag's last value is not lost.
    func flush() {
        guard let work = writeWork, !work.isCancelled else { return }
        work.cancel()
        writeNow(data)
    }

    private func scheduleWrite() {
        writeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in guard let self else { return }; self.writeNow(self.data) }
        writeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
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
    func reconcileApple() {
        if (AppleScreencapture.bool("show-thumbnail") ?? true) != data.appleThumbnail {
            AppleScreencapture.set("show-thumbnail", data.appleThumbnail)
            Log.write("[settings] reconciled apple show-thumbnail=\(data.appleThumbnail)")
        }
        followAppleLocation()
        appleLocation = AppleScreencapture.observeLocation { [weak self] in self?.followAppleLocation() }
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
        scheduleWrite()
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

    // MARK: File

    private static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }

    @discardableResult
    private static func write(_ raw: Data, to url: URL) -> Data? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try raw.write(to: url, options: .atomic); return raw } catch { return nil }
    }

    private static func deepMerge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var out = base
        for (k, v) in over {
            if let b = base[k] as? [String: Any], let o = v as? [String: Any] { out[k] = deepMerge(b, o) } else { out[k] = v }
        }
        return out
    }

    private func writeNow(_ d: SettingsData) {
        if readOnly { Log.write("[settings] warning not written: the file is from a newer version"); return }
        guard let raw = try? Settings.encoder().encode(d) else { return }
        // Tweak-panel changes are not logged as they happen (a drag is many of them); the write is.
        if let previous = lastWrittenData {
            let changed = Settings.uiChanges(from: previous.ui, to: d.ui)
            if !changed.isEmpty { Log.write("[settings] wrote \(changed.joined(separator: " "))") }
        }
        lastWritten = raw
        lastWrittenData = d
        Settings.write(raw, to: Settings.fileURL)
        watchFile()   // atomic write replaced the inode
    }

    /// `ui.key=value` for every UI number that differs, in key order.
    static func uiChanges(from old: UITweaks, to new: UITweaks) -> [String] {
        func dict(_ u: UITweaks) -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(u))) as? [String: Any] ?? [:]
        }
        let a = dict(old), b = dict(new)
        return b.keys.sorted().compactMap { key in
            let value = b[key].map { "\($0)" } ?? "null"
            let before = a[key].map { "\($0)" } ?? "null"
            return value == before ? nil : "ui.\(key)=\(value)"
        }
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
        switch Settings.load(Settings.fileURL) {
        case .missing:
            return
        case .invalid(let reason):
            Log.write("[settings] error settings-invalid file changed but does not parse; keeping current settings: \(reason)")
        case .loaded(var loaded):
            for line in loaded.log { Log.write("[settings] \(line)") }
            if loaded.fileVersion > Settings.currentVersion, !readOnly {
                readOnly = true
                Log.write("[settings] warning file version \(loaded.fileVersion) is newer than this build's \(Settings.currentVersion); not writing to it")
            }
            // The app owns this record; a pasted or older file must not erase it.
            if loaded.data.appleOriginal == nil { loaded.data.appleOriginal = data.appleOriginal }
            let validated = loaded.data.validated()
            for note in validated.corrections { Log.write("[settings] warning clamped \(note)") }
            apply(validated.data, source: "file")
            lastWrittenData = validated.data   // the next tweak-panel write logs only what it changed
            // Stamp a pre-version file once so the migration does not repeat on every reload.
            if loaded.fileVersion < Settings.currentVersion { writeNow(loaded.data) }
        }
    }
}

/// Apple's screenshot defaults (`defaults read com.apple.screencapture`). A launch with
/// `VIGNETTE_SETTINGS` reads and writes `<bundle id>.screencapture` instead, so a test copy never
/// takes or moves the user's save location. macOS itself never reads that domain.
enum AppleScreencapture {
    static let domainName = (ProcessInfo.processInfo.environment["VIGNETTE_SETTINGS"].map { !$0.isEmpty } ?? false) ? "\(Identity.bundleID).screencapture" : "com.apple.screencapture"
    private static let domain = domainName as CFString

    static func string(_ key: String) -> String? { CFPreferencesCopyAppValue(key as CFString, domain) as? String }
    static func bool(_ key: String) -> Bool? { CFPreferencesCopyAppValue(key as CFString, domain) as? Bool }

    /// Where macOS saves screenshots: the `location` key, or the Desktop when it is unset.
    static var location: String { string("location") ?? SettingsData().screenshotsFolder }

    /// Two folder paths name the same folder, whatever their tildes and trailing slashes.
    static func samePath(_ a: String, _ b: String) -> Bool {
        func standard(_ path: String) -> String {
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        }
        return standard(a) == standard(b)
    }

    /// Calls `changed` on the main thread whenever `location` changes, whoever changed it: the
    /// preferences daemon tells every process observing the key. Measured with a `defaults write`
    /// from another process: 10 to 35 ms.
    static func observeLocation(_ changed: @escaping @MainActor @Sendable () -> Void) -> Observer? {
        UserDefaults(suiteName: domainName).map { Observer(defaults: $0, changed: changed) }
    }

    final class Observer: NSObject {
        private let defaults: UserDefaults
        private let changed: @MainActor @Sendable () -> Void

        init(defaults: UserDefaults, changed: @escaping @MainActor @Sendable () -> Void) {
            self.defaults = defaults
            self.changed = changed
            super.init()
            defaults.addObserver(self, forKeyPath: "location", options: [], context: nil)
        }

        deinit { defaults.removeObserver(self, forKeyPath: "location") }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                   change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            // Delivered on whichever thread the change arrived on.
            DispatchQueue.main.async { [changed] in MainActor.assumeIsolated { changed() } }
        }
    }

    static func set(_ key: String, _ value: Any) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList, domain)
        CFPreferencesAppSynchronize(domain)
        Log.write("[settings] apple \(key)=\(value)")
    }

    static func remove(_ key: String) {
        CFPreferencesSetAppValue(key as CFString, nil, domain)
        CFPreferencesAppSynchronize(domain)
        Log.write("[settings] apple \(key) unset")
    }
}

/// Animation helper honoring the tweakable curves.
@MainActor
enum Anim {
    /// The bounce every card flight and the annotator's toolbar are carried by. One number: the
    /// toolbar slides to the next image's place over `passesTarget` of the flight's own spring, and
    /// the two are only in step while they agree.
    static let flightBounce = 0.15

    static func swiftUI(_ curve: String, duration: Double) -> Animation {
        switch curve {
        case "easeOut": return .easeOut(duration: duration)
        case "easeInOut": return .easeInOut(duration: duration)
        case "linear": return .linear(duration: duration)
        default: return spring(duration, bounce: flightBounce)   // "spring"
        }
    }

    /// A SwiftUI spring that settles in about `duration`. Springs are the curve for every SwiftUI
    /// motion here: when one is interrupted by another on the same property, SwiftUI keeps the
    /// velocity, so a card that turns around or changes place mid-flight blends instead of jumping.
    static func spring(_ duration: Double, bounce: Double = 0) -> Animation {
        duration > 0 ? .spring(duration: duration, bounce: bounce) : .linear(duration: 0)
    }

    /// When the same spring first reaches its target. From there until it settles it is on the far
    /// side of it, coming back, so a rect animated by it contains the target on every side and
    /// covers anything drawn there. A spring that does not overshoot never reaches its target;
    /// this is then its whole settling time, and a caller that takes the earlier of this and
    /// `settle` gets no early cover, which is the right answer for one.
    static func passesTarget(_ duration: Double, bounce: Double = 0) -> Double {
        guard duration > 0 else { return 0 }
        let spring = Spring(duration: duration, bounce: bounce)
        let step = duration / 64
        var t = 0.0
        while t <= spring.settlingDuration {
            if spring.value(target: 1.0, time: t) >= 1 { return t }
            t += step
        }
        return spring.settlingDuration
    }

    /// When the same spring is within `within` points of a target `distance` points away. Its tail
    /// runs well past its nominal duration: at 1.15 times it is still about 0.4% short, which is
    /// several points across a screen. Uses SwiftUI's own spring, so it matches what it animates.
    static func settle(_ duration: Double, bounce: Double = 0, distance: CGFloat, within: CGFloat) -> Double {
        guard duration > 0, distance > within else { return 0 }
        let spring = Spring(duration: duration, bounce: bounce)
        let tolerance = Double(within / distance)
        let step = duration / 32
        var t = spring.settlingDuration
        while t > step {
            if abs(1 - spring.value(target: 1.0, time: t - step)) > tolerance { return t }
            t -= step
        }
        return 0
    }
}

/// How much of every animation to play. One rule, so a script or a person can turn motion off.
enum Motion {
    static func scale(reduceMotion: Bool, multiplier: Double) -> Double {
        reduceMotion ? 0 : min(max(multiplier.isFinite ? multiplier : 1, 0), 1)
    }
}
