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

/// When live ink stops listening: as the chord is let go, or at a pause after it. An experiment;
/// one of the two stays (`docs/live-ink-speech-input-2026-10-06.md`).
enum ListenUntil: String {
    case release
    case pause
}

/// Everything a user changes per machine. Lives in ~/.config/<URL scheme>/settings.json, which is
/// ~/.config/vignette/settings.json for Vignette.
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
    var sendInstructions = SettingsData.defaultSendInstructions  // the words after the image in the line Send puts in a session
    var annotateOnCapture = false            // a new capture opens in the annotator instead of showing a thumbnail
    var copyOnCapture = true                 // a new capture goes to the clipboard as it lands
    var liveInk = false                      // holding Control and Option draws on the screen itself; needs Accessibility and, for now, `debug`
    var liveInkSpeech = false                // talking while drawing fills the note; needs the microphone and speech recognition
    var liveInkListenUntil = ListenUntil.pause.rawValue  // experiment: listening ends as the chord is let go, or at a pause after
    var liveInkSendWhenQuiet = true          // experiment: the ask goes once the person stops talking, or waits for Return
    var debug = false                        // unlocks tweaks, install-skill root=, live-ink-stroke, and file= outside the watch folder
    var agentSkill = AgentSkill.unasked.rawValue  // whether the skill was offered: unasked, then off
    var setup = SetupState.unasked.rawValue  // whether the setup window has run: unasked, then done
    var ui = UITweaks()                      // visual and timing knobs; the debug panel edits these live
    var appleOriginal: AppleOriginal?        // Apple's screencapture values before Vignette changed them

    var folderURL: URL { URL(fileURLWithPath: (screenshotsFolder as NSString).expandingTildeInPath) }

    /// `agentSkill` as the states it holds. An unknown word reads as `unasked`, which
    /// `validated()` then writes back.
    var agentSkillChoice: AgentSkill { AgentSkill(rawValue: agentSkill) ?? .unasked }

    /// `liveInkListenUntil` as the choices it holds. An unknown word reads as `pause`.
    var listenUntil: ListenUntil { ListenUntil(rawValue: liveInkListenUntil) ?? .pause }

    /// `setup` as the states it holds. An unknown word reads as `unasked`.
    var setupChoice: SetupState { SetupState(rawValue: setup) ?? .unasked }

    /// Whether the shortcut is a modifier double tap rather than a key combination. Three places
    /// ask, and each one parsing the string itself is how they drift apart.
    var usesDoubleTap: Bool {
        if case .doubleTap = HotKeySpec.parse(recentHotkey) { return true }
        return false
    }

    /// Live ink is internal until it ships: it runs, and the Settings window and the menu offer it,
    /// only while `debug` is on too.
    var usesLiveInk: Bool { liveInk && debug }

    /// What the line Send puts in a session says after the image (`ScreenshotRequests.requestLine`).
    static let defaultSendInstructions = "If a drawing would answer better than words, you can send one back."

    /// What picking "Key combination" writes. The default shortcut is the double tap, so this
    /// cannot be read off a fresh `SettingsData`.
    static let defaultKeyCombination = "cmd+shift+2"

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
        // The line Send puts in a session is one line, since the plugin's monitor makes each line one message.
        let instructions = String(d.sendInstructions.asOneLine.prefix(MarkFields.maxTextLength))
        if instructions != d.sendInstructions { notes.append("sendInstructions made one line of \(instructions.count) characters"); d.sendInstructions = instructions }
        if ListenUntil(rawValue: d.liveInkListenUntil) == nil {
            notes.append("liveInkListenUntil \"\(d.liveInkListenUntil)\" -> \"\(ListenUntil.pause.rawValue)\""); d.liveInkListenUntil = ListenUntil.pause.rawValue
        }
        if SetupState(rawValue: d.setup) == nil {
            notes.append("setup \"\(d.setup)\" -> \"\(SetupState.unasked.rawValue)\""); d.setup = SetupState.unasked.rawValue
        }
        if !["spring", "easeOut", "easeInOut", "linear"].contains(d.ui.slideInCurve) {
            notes.append("ui.slideInCurve \"\(d.ui.slideInCurve)\" -> \"spring\""); d.ui.slideInCurve = "spring"
        }
        for (name, path) in [("personColor", \UITweaks.personColor), ("agentColor", \.agentColor), ("edgeColor", \.edgeColor),
                             ("noteTextColor", \.noteTextColor), ("checkColor", \.checkColor), ("checkGlowColor", \.checkGlowColor), ("inkGelLight", \.inkGelLight), ("inkGelDeep", \.inkGelDeep)] where SRGB(hex: d.ui[keyPath: path]) == nil {
            let fixed = UITweaks()[keyPath: path]
            notes.append("ui.\(name) \"\(d.ui[keyPath: path])\" -> \"\(fixed)\": a colour is #rrggbb"); d.ui[keyPath: path] = fixed
        }
        for (name, path) in [("textFont", \UITweaks.textFont), ("agentTextFont", \.agentTextFont)] where !TextStyle.isInstalled(d.ui[keyPath: path]) {
            let fixed = UITweaks()[keyPath: path]
            notes.append("ui.\(name) \"\(d.ui[keyPath: path])\" -> \"\(fixed)\": no font family of that name is installed"); d.ui[keyPath: path] = fixed
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
    var cardMaxWidth = 188.0
    var cardMaxHeight = 153.0
    var cardMinSide = 120.0
    var cardSpacing = 10.0
    var panelInset = 19.0            // room for shadows inside the panel
    var screenMargin = 17.0          // distance from the screen corner
    var stackMinScale = 0.5          // how narrow the stack goes to make room for the annotator
    var stackGap = 24.0              // the stack keeps this much between itself and the annotator
    var cardCornerRadius = 16.0
    var cardBorderWidth = 0.5
    var cardBorderOpacity = 0.4
    var cardShadowRadius = 4.0
    var cardShadowOpacity = 0.85
    var cardShadowY = 4.0
    var hoverScale = 1.06
    var pressScale = 0.97
    var hoverDim = 0.35             // darkening of a hovered card behind its buttons
    // Hover buttons and selection
    var buttonSize = 27.0
    var buttonIconSize = 11.0
    var buttonSpacing = 4.0
    var selectionCircleSize = 19.0
    var selectionStripGap = 16.0     // the widest selected card to the control strip beside it
    var autoScrollZone = 44.0        // band at each end of the column where a drag-select scrolls it
    var autoScrollSpeed = 600.0      // points a second at the very edge of that band
    // Timings
    var thumbnailSeconds = 5.0       // how long a fresh thumbnail stays
    var markSeconds = 1.7            // how long a card's notice stays; the stored key keeps its older name
    var sendGraceSeconds = 3.0       // how long a Send waits before its session gets it; 0 sends at once
    // The success check on a copied or sent card (CheckCoin; docs/check-lab-2026-10-11.md): a coin
    // of tinted polymer with a glowing check mark inside it, which spins as it appears and settles
    // face on. Lengths are fractions of its diameter.
    var checkColor = "#00d2b2"       // the polymer's tint
    var checkGlowColor = "#8dffc4"   // the mark's glow
    var checkRoughness = 1.0         // 0 a mirror, 1 frosted: how soft every reflection is
    var checkThickness = 0.05
    var checkEdge = 0.2              // the rounding of the coin's rim
    var checkDome = 0.07             // how far each face rises at its centre
    var checkMarkSize = 0.43         // the mark's width
    var checkMarkWeight = 0.25       // its stroke's width
    var checkGlow = 0.54             // 0 to 3: how bright the mark glows
    var checkGlowSpread = 0.02       // how far its glow lights the polymer around it
    var checkClarity = 0.18          // 0 to 1: how much of what is behind the coin shows through it
    var checkLightAngle = -19.0      // where the key light is, degrees clockwise from the top
    var checkLightHeight = 50.0      // its height above the coin's face, in degrees
    var checkLight = 3.0             // 0 to 3: its strength
    var checkStudio = 0.8            // 0 to 1: how much brighter the studio's ceiling is than its floor
    var checkGlint = 2.4             // 0 to 3: the strip light the spin sweeps the coin past
    var checkGlintAngle = -63.0      // where the strip stands, degrees to the right of the viewer
    var checkSpinTurns = 1.0         // how many times the coin turns; 0 for no spin
    var checkSpinDuration = 0.65     // the spring's duration
    var checkSpinBounce = 0.22       // 0 to 1: how far it rocks past face on before it settles
    var checkSpinDelay = 0.05        // after the check appears
    var checkBloom = 0.73            // 0 to 2: the bloom; 0 turns it off
    var checkBloomRadius = 0.49
    var checkBloomThreshold = 0.24   // 0 to 1: how bright a reflection must be to bloom
    var slideInDuration = 0.3
    var slideInCurve = "spring"      // spring, easeOut, easeInOut, linear
    var slideOutDuration = 0.15
    var staggerDelay = 0.07
    var staggerTotalMax = 0.3        // the last card never starts later than this
    var relayoutDuration = 0.25
    var shiftUpDuration = 0.3        // one card joining a visible stack: how long the others take to shift up
    var expandDuration = 0.35
    var introDuration = 0.95         // setup's window flying into the menu bar icon, once per Mac
    var introFunnel = 1.0            // 0 flies that window as one piece, up to 1 pours it into the icon (docs/intro-funnel-2026-09-30.md)
    var introFunnelSmoothing = 1.0   // 0 starts and stops each row of the pour abruptly, 1 eases both, so its sides curve without corners
    var introFunnelCorner = 32.0     // the pour's corners, in points, grown from the window's own as its rows leave
    var introFunnelSmear = 1.0       // 0 to 1: how far a squeezed row is averaged, so squeezed text softens instead of breaking up
    var introFunnelRim = 0.9         // 0 to 1: the light along the pour's bent edges
    var introFunnelFade = 0.1        // the share of each row's travel over which it fades into the icon
    var hoverRevealDuration = 0.15
    // A flight between a stack slot and the annotator, bowed and swelled by FlightCurve
    var flightArc = 0.15             // how far the path bows, as a fraction of its length
    var flightArcMax = 240.0         // the bow never exceeds this many points
    var flightDepth = 0.07           // how much larger the card is in the middle of the path
    var motion = 1.0                 // multiplier on every animation, 0 to 1; Reduce Motion forces 0
    // Backdrop
    var backdropWidth = 180.0
    var backdropTint = 0.65          // darkness at the right edge, 0 to 1
    var backdropTintStart = 0.0      // where the tint begins, 0 = left edge, 1 = right edge
    var backdropBlurRadius = 25.0    // at the right edge
    var backdropBands = 7            // effect views in the blur ramp
    var backdropRampPower = 1.2      // 1 = linear radius growth, higher keeps the left sharper
    var backdropFadeIn = 0.25
    var backdropFadeOut = 0.25
    var backdropSlideIn = 0.3           // the strip slides in from the screen edge while it fades
    var backdropSlideOut = 0.2
    var dimOpacity = 0.3             // screen darkening behind the annotator
    var dimBlurRadius = 17.0
    var dimFade = 0.4                // the spring settles within this
    // Annotator window
    var annotationMinWidth = 770.0
    var annotationMinHeight = 320.0
    var annotationCornerRadius = 16.0
    var annotationToolbarGap = 9.0
    var annotationScreenInset = 60.0
    var zoomEdgeBandPoints = 250.0   // how far from each edge of the picture a zoom holds that edge
    var zoomEdgePull = 0.6           // the part of that band in which the edge is held exactly
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
    var newTextSize = 17.0           // pt of the drawing, not of the screen
    var selectionOutlineWidth = 3.5  // the whole outline, light edge included; it runs this far outside a mark
    var noteSettleDuration = 0.25    // seconds a note takes to move to its balanced lines when typing ends
    // Marks (`MarkStyle`, `TextStyle`, `docs/mark-style-settings-2026-09-29.md`)
    var personColor = "#e03131"      // a person's marks, as #rrggbb
    var agentColor = "#364fc7"       // every agent's marks
    var edgeColor = "#ffffff"        // the edge around every mark
    var noteTextColor = "#ffffff"    // the words on a note's tag
    var strokeWidth = 3.5            // pt of the drawing
    var edgeWidth = 1.5              // pt, outside a stroke on both sides and around a note's tag
    var shadowOpacity = 1.0          // multiplies the marks' shadows' darkness; 0 turns them off
    var textFont = "rounded"         // a person's notes: rounded, monospaced, serif, default, or an installed font family
    var agentTextFont = "monospaced" // an agent's notes
    var textWeight = 600.0           // 100 Ultralight to 900 Black, as the nearest of the font's weights
    var agentTextWeight = 600.0
    var agentTextSize = 1.33         // an agent's note, as a percentage of the image's width
    var textLineHeight = 1.32        // a multiple of the text's size
    var notePaddingTop = 0.42        // the tag around a note's words, in multiples of the text's size
    var notePaddingBottom = 0.47
    var notePaddingSide = 0.8
    var noteMaxWidth = 18.0          // a note without a wrap width wraps at this many times its size
    var badgeInset = 0.35            // an agent's badge from its tag's left edge, in multiples of the text's size
    var badgeOverlap = 0.2           // and how far it overlaps the tag's top edge
    var arrowheadLength = 4.5        // multiples of the stroke width
    var arrowheadWidth = 4.0
    // Stitch
    var stitchLongSide = 4096.0      // a composition longer than this is scaled down to it
    // The pointer field, which says the screen is taking ink while the chord is held: the ring round
    // the pointer.
    var liveInkFieldDelay = 0.25     // how long the chord is held before it shows, unless a press shows it sooner
    var liveInkFieldFade = 0.5       // how long it fades in and out, and the ring grows in
    var liveInkFieldOpacity = 1.0
    // The ring: it bends the screen under it and glows in the ink colour, with a still middle so what
    // the pointer is on stays put.
    var liveInkFieldSize = 23.0      // the ring's radius in points; 0 turns it off
    var liveInkFieldBend = 1.8       // 0 to 1.8: how far the ring moves what is under it
    var liveInkFieldSplit = 1.7      // 0 to 2: how far red and blue part where the ring moves the picture
    var liveInkFieldGlow = 1.0       // 0 to 1: the ink-coloured light on and round the ring
    var liveInkFieldFollow = 0.04    // how long the ring takes to catch up with the pointer; 0 holds it on it
    var liveInkFieldStretch = 0.6    // 0 to 1: how far the ring stretches along the way the pointer moves
    var liveInkFieldStyle = 4.0      // 0 Glass, 1 Lens, 2 Squircle, 3 Droplet, 4 Lamp, 5 Caustic
    var liveInkFieldZoom = 1.46      // Lens: magnifies its middle about the arrow's tip; 1 is none
    var liveInkFieldClear = 0.4      // Lens and Lamp: how much of the middle is left alone
    var liveInkFieldShine = 1.0      // Lens: its rim and highlight; Caustic: its glass edge
    var liveInkFieldShade = 1.0      // Lens and Caustic: the darker parts that let them read on white
    var liveInkFieldSquareness = 4.5 // Squircle: 2 is a circle, 4.5 Apple's continuous corners, 8 nearly square
    var liveInkFieldBreak = 0.0      // Squircle: 0 is a closed outline; raised, only its corners remain
    var liveInkFieldSpread = 1.7     // Lamp: how far its light reaches, in ring sizes
    var liveInkFieldDepth = 0.23     // Caustic: how far into the ring its bright crescent reaches, a fraction of the size
    // Lamp's life: how its pool of light moves on its own
    var liveInkLampBreath = 0.15     // 0 to 0.5: how far its size and light rise and fall
    var liveInkLampBreathSeconds = 3.5 // how long one breath takes
    var liveInkLampEnergy = 0.6      // 0 to 1.5: how much brighter and wider it grows while the pointer moves fast
    var liveInkLampDrift = 0.3       // 0 to 1: light drifting slowly round inside the pool
    // Live ink's answers
    var liveInkDrawOn = 0.5          // how long an answer's mark takes to draw itself on
    var liveInkHideFade = 0.12       // a mark fading out as the content under it starts to move
    var liveInkShowFade = 0.22       // a mark fading back in once the content is still
    var liveInkTextSize = 15.0       // an answer's note, in points of the screen
    var liveInkTextWidth = 320.0     // the widest an answer's note wraps at, in points
    // Live ink's speech input
    var liveInkSpeechPause = 1.2     // how long a quiet spell after the chord is let go ends listening
    var liveInkSpeechQuiet = 0.4     // the input's level under which it counts as quiet, 0 for -60 dB to 1 for 0 dB
    // The person's live ink as opal gel (InkGel; docs/live-ink-gel-2026-10-12.md): a rod of milky
    // material under a thin film whose pale colours follow the line, with a glow under it.
    var inkGelLight = "#8cc7ff"      // the ice's hue, over dark content
    var inkGelDeep = "#244d9e"       // the deep blue, over light content
    var inkGelWidth = 5.0            // the line's width, in points of the screen
    var inkGelCore = 0.9             // 0 to 1: how white the ice is along its middle
    var inkGelSheen = 0.6            // 0 to 2: the highlight
    var inkGelGlow = 0.55            // 0 to 2: the glow round the line
    var inkGelBloom = 0.6            // 0 to 2: more glow where the line faces the light
    var inkGelGlowRadius = 6.0       // how far the glow reaches, in points
    var inkGelShadow = 0.18          // 0 to 1: the shadow under the line, which shows on light windows
    var inkGelMotion = 1.0           // 0 to 3: how fast the light and the shimmer drift; 0 holds them still
    var inkGelShimmer = 1.0          // 0 to 3: a slow ripple of light along the line
    var inkGelWander = 0.35          // how far the light wanders, in radians
    var inkGelHighlightSharpness = 110.0 // the highlight's specular power: higher is a smaller, harder spot
    var inkGelGlowFalloff = 2.2      // how fast the glow fades past the line's core
    var inkGelDeepEdge = 0.38        // the deep blue at the line's edge, as a share of it at the middle
    var inkGelEdgeOpacity = 0.75     // the ice's opacity at the line's edge; its middle is opaque
    var inkGelSheathDepth = 1.3      // how far the deep blue sheath reaches in over light content
    var inkGelShimmerLength = 90.0   // the shimmer's wavelength along the line, in points
    var inkGelShimmerSpeed = 1.1     // how fast the shimmer runs along the line
    var inkGelLightAngle = -123.19   // where the light comes from, in degrees, 0 to the right
    var inkGelLightHeight = 1.1      // how high the light is over the line: lower lights it from the side
    var inkGelPointerLight = 1.0     // 0 to 1: how much of the light comes from the pointer rather than the light angle
    var inkGelPointerHeight = 120.0  // how high over the screen the pointer's light hangs, in points
    // The person's live ink as the hand draws it (`InkHand.Feel`). Widths are multiples of `inkGelWidth`.
    var inkHandWidth = 0.9           // the width where the hand moves at its average speed
    var inkHandSpeed = 0.42          // how much each multiple of the average speed narrows it
    var inkHandThinnest = 0.72
    var inkHandWidest = 1.4
    var inkHandSpeedMemory = 48.0    // pointer events the average speed is taken over
    var inkHandWidthSmoothing = 6.0  // points either side that a width is averaged with
    var inkHandStartTaper = 14.0     // points the line narrows over where the pen lands
    var inkHandStartWidth = 0.38     // its width where the pen lands, a share of the full width
    var inkHandEndTaper = 26.0       // points a loop narrows over where the pen lifts
    var inkHandEndWidth = 0.3
    var inkLength = 1800.0           // points of line the pen keeps; past it, the line's start recedes
    var inkSettle = 0.3              // seconds of the spring a drawn loop or arrow settles onto its shape on
    var inkSettleBounce = 0.25       // 0 to 0.9: how far it swings past its shape before it is still
    var inkSettleStagger = 0.08      // seconds after the line's end lets go that its start does
    // An agent's marks on the live screen, drawn as light (`LightMarkLayer`)
    var lightGlow = 3.0              // the tight glow's reach, in points, over a dark window
    var lightGlowWide = 9.0          // the wide glow's
    var lightGlowStrength = 1.0      // multiplies the glows once the mark has settled
    var lightGlowDrawing = 1.0       // multiplies the glows while the mark draws itself on
    var lightCoreWhite = 0.75        // how white the core's middle is over a dark window
    var lightGlintLength = 26.0      // points of the glint that runs at the head as a mark draws on
    var lightGlintFade = 0.15        // seconds the glint takes to go once the mark is drawn
    var lightOverLight = 1.0         // multiplies the glows over a light window, where they tint it

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
    /// swells. Dwell times (`thumbnailSeconds`, `markSeconds`, `sendGraceSeconds`) are not motion and
    /// stay as they are, and `flightArcMax` is a limit on the bow rather than an amount of it.
    func scaledForMotion(_ scale: Double) -> UITweaks {
        var u = self
        u.slideInDuration *= scale; u.slideOutDuration *= scale
        u.staggerDelay *= scale; u.staggerTotalMax *= scale
        u.relayoutDuration *= scale; u.shiftUpDuration *= scale; u.expandDuration *= scale; u.hoverRevealDuration *= scale
        u.introDuration *= scale
        u.checkSpinDuration *= scale; u.checkSpinDelay *= scale
        u.noteSettleDuration *= scale
        u.liveInkFieldFade *= scale; u.liveInkDrawOn *= scale
        u.liveInkFieldFollow *= scale
        u.liveInkHideFade *= scale; u.liveInkShowFade *= scale
        u.inkSettle *= scale; u.inkSettleStagger *= scale; u.lightGlintFade *= scale
        // The lamp's breath and drift are motion, so they go with it.
        u.liveInkLampBreath *= scale; u.liveInkLampDrift *= scale
        u.backdropFadeIn *= scale; u.backdropFadeOut *= scale; u.dimFade *= scale
        u.backdropSlideIn *= scale; u.backdropSlideOut *= scale
        u.flightArc *= scale; u.flightDepth *= scale
        return u
    }

    /// Bounds outside which a value crashes, divides by zero, or makes NaN. Not design limits. Each is
    /// defined with its tweak in `TweakCatalog`.
    static let bounds: [Bound] = TweakCatalog.sections.flatMap(\.tweaks).compactMap { spec in
        switch spec.control {
        case .number(let path, _, _, _, let safe), .style(let path, _, let safe): Bound(spec.key, path, safe)
        default: nil
        }
    }
}

extension UITweaks {
    /// Set on the encoder that writes settings.json. There `ui` holds only the values that differ
    /// from the defaults, so a default tuned in a later build reaches a file an earlier one wrote.
    /// Every other encoding is whole, since `Settings.load` merges a file over it.
    static let differencesOnly = CodingUserInfoKey(rawValue: "vignette.ui.differencesOnly")!

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Every stored property under its own name, as the synthesized encoding writes it; decoding
    /// stays synthesized. Mirror walks the properties, so a new tweak needs nothing here.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        let differencesOnly = encoder.userInfo[Self.differencesOnly] as? Bool ?? false
        for (child, fallback) in zip(Mirror(reflecting: self).children, Mirror(reflecting: UITweaks()).children) {
            guard let name = child.label, let value = child.value as? any Encodable else { continue }
            if differencesOnly, Self.same(child.value, fallback.value) { continue }
            try container.encode(value, forKey: Key(stringValue: name))
        }
    }

    /// Equal, counting floating-point noise as equal: a slider's steps leave values such as
    /// 0.30000000000000004 where it showed 0.3, and written as a difference that would pin the
    /// default it equals.
    static func same(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? Double, let y = b as? Double { return abs(x - y) <= 1e-9 * max(1, abs(x), abs(y)) }
        guard let x = a as? AnyHashable, let y = b as? AnyHashable else { return false }
        return x == y
    }

    var inkHandFeel: InkHand.Feel {
        InkHand.Feel(width: inkHandWidth, speed: inkHandSpeed, thinnest: inkHandThinnest, widest: inkHandWidest,
                     memory: Int(inkHandSpeedMemory.rounded()), smoothing: Int(inkHandWidthSmoothing.rounded()),
                     startTaper: inkHandStartTaper, startWidth: inkHandStartWidth, endTaper: inkHandEndTaper, endWidth: inkHandEndWidth)
    }

    var editorMetrics: EditorMetrics {
        EditorMetrics(dragDistance: dragDistance, hitMargin: hitMargin, cornerHitSize: cornerHitSize, edgeHitSize: edgeHitSize,
                      smallSide: smallSide, handleSize: handleSize, dotRadius: dotRadius, dotHitRadius: dotHitRadius,
                      smallestRectangle: smallestRectangle, shortestArrow: shortestArrow, textDragDelay: textDragDelay,
                      textDragDistance: textDragDistance, newTextSize: newTextSize, selectionOutlineWidth: selectionOutlineWidth)
    }

    /// The style every text is set in. The system font draws only its nine named weights, whatever
    /// weight it is asked for (measured on macOS 15), so a weight picks one: 100 is the first.
    var textStyle: TextStyle {
        func named(_ value: Double, _ fallback: Double) -> NSFont.Weight {
            let weights: [NSFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
            let weight = value.isFinite ? min(max(value, 100), 900) : fallback
            return weights[Int((weight / 100).rounded()) - 1]
        }
        return TextStyle(personFont: textFont, personWeight: named(textWeight, UITweaks().textWeight),
                         agentFont: agentTextFont, agentWeight: named(agentTextWeight, UITweaks().agentTextWeight),
                         lineHeight: textLineHeight, padTop: notePaddingTop, padBottom: notePaddingBottom, padSide: notePaddingSide,
                         widthCap: noteMaxWidth, badgeInset: badgeInset, badgeOverlap: badgeOverlap, agentSize: agentTextSize / 100)
    }

    /// How every mark is painted. A colour that is not `#rrggbb` takes the default's, as `validated`
    /// has already reported.
    var markStyle: MarkStyle {
        func color(_ path: KeyPath<UITweaks, String>) -> SRGB { SRGB(hex: self[keyPath: path]) ?? SRGB(hex: UITweaks()[keyPath: path])! }
        return MarkStyle(strokeWidth: strokeWidth, edgeWidth: edgeWidth, personColor: color(\.personColor), agentColor: color(\.agentColor),
                         edgeColor: color(\.edgeColor), wordColor: color(\.noteTextColor), shadowOpacity: shadowOpacity,
                         arrowheadLength: arrowheadLength, arrowheadWidth: arrowheadWidth)
    }
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
    nonisolated static let currentVersion = 2
    nonisolated static let isOverridden = ProcessInfo.processInfo.environment["VIGNETTE_SETTINGS"].map { !$0.isEmpty } ?? false
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
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/\(Identity.urlScheme)/settings.json")
    }()
    static var directory: URL { fileURL.deletingLastPathComponent() }

    @Published private(set) var data: SettingsData
    var onChange: ((SettingsData, SettingsData) -> Void)?
    /// The system's Reduce Motion switch, kept current by the workspace notification.
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// Where macOS sends a capture (`AppleScreencapture.target`), kept current by an observer.
    /// Anything but `file` leaves the watch folder with no new screenshots.
    @Published private(set) var appleTarget = AppleScreencapture.target
    private var motionObserver: Any?

    /// 0 to 1: what every animation duration is multiplied by. Reduce Motion makes it 0.
    var motionScale: Double { Motion.scale(reduceMotion: reduceMotion, multiplier: data.ui.motion) }
    /// The tweaks every animation reads: layout as in `data.ui`, durations scaled by `motionScale`.
    var motionUI: UITweaks { data.ui.scaledForMotion(motionScale) }
    /// What the Settings window says when this launch had to set the file aside. nil when all was well.
    let startupNotice: Notice?

    /// What went wrong with the file at launch, as the General tab says it.
    struct Notice {
        var title: String
        var detail: String
    }
    private var sync: SettingsSync
    private let hold = EventHold<SettingsSync.Event>()
    /// True when nothing is written to the file (`SettingsSync.readOnly`).
    var readOnly: Bool { sync.readOnly }

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
        var notice: Notice?
        var readOnly = false
        var readOnlyReason = ""
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
                boot.readOnlyReason = "the file is from a newer version"
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
            // Fill in any settings the file lacks so each is visible to whoever edits it next. `ui`
            // is the exception: it holds only what differs from the defaults.
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
            do {
                let raw = try encoder().encode(d)
                try writeOrThrow(raw, to: url)
                boot.written = raw
                boot.log.append("created \(url.path)")
            } catch {
                // A `~/.config` that belongs to root is common on developer Macs. Without this, every
                // launch would find no file and start over as a first launch.
                let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
                boot.readOnly = true
                boot.readOnlyReason = "\(folder) cannot be written"
                boot.log.append("error cannot create \(url.path): \(error.localizedDescription); running on defaults without saving")
                boot.notice = Notice(title: "Settings can't be saved",
                                     detail: "Vignette can't write to \(folder). Changes last until it quits.")
            }
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
                boot.notice = Notice(title: "settings.json could not be read",
                                     detail: "Vignette is using the default settings. Your file was kept as settings.json.invalid.")
            } else {
                boot.log.append("could not move the invalid file aside; running on defaults without writing")
                boot.readOnly = true
                boot.readOnlyReason = "the invalid file could not be moved aside"
                boot.notice = Notice(title: "settings.json could not be read",
                                     detail: "Vignette is using the default settings and will not save changes until the file is fixed.")
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
        return parse(raw)
    }

    /// Reads the file's bytes over the defaults, as `load` does once it has them. Never answers `.missing`.
    nonisolated static func parse(_ raw: Data) -> Load {
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
    /// A file from a newer version is returned unchanged. A bump that changes a key rewrites it
    /// here, between the guard and the stamp, one step per version. Version 1 introduced the
    /// version field. Version 2 writes only the `ui` values that differ from the defaults.
    nonisolated static func migrate(_ raw: [String: Any]) -> (json: [String: Any], from: Int) {
        var json = raw
        let from = (json["version"] as? NSNumber)?.intValue ?? 0
        guard from < currentVersion else { return (json, from) }
        // 0.1.0 and 0.1.1 wrote every `ui` value, so a value there is a choice only where it
        // differs from their default. Kept, their old defaults would read as choices from now on.
        if from < 2, var ui = json["ui"] as? [String: Any] {
            for (key, old) in Self.uiDefaultsBeforeVersion2 where (ui[key] as? NSObject)?.isEqual(old) == true {
                ui[key] = nil
            }
            json["ui"] = ui
        }
        json["version"] = currentVersion
        return (json, from)
    }

    /// Every `ui` default of 0.1.0 and 0.1.1, which are the same, taken from v0.1.1's source. All of
    /// them, not only those that differ from today's, so a default changed later cannot turn one
    /// into a choice.
    nonisolated static let uiDefaultsBeforeVersion2: [String: any Sendable] = [
        "slideInCurve": "spring",
        "cardMaxWidth": 208, "cardMaxHeight": 86, "cardMinSide": 114, "cardSpacing": 10, "panelInset": 19,
        "screenMargin": 17, "stackMinScale": 0.5, "stackGap": 24, "cardCornerRadius": 12,
        "cardBorderWidth": 2, "cardBorderOpacity": 0.35, "cardShadowRadius": 4, "cardShadowOpacity": 0.5,
        "cardShadowY": 6, "hoverScale": 1.06, "pressScale": 0.96, "hoverDim": 0.35, "buttonSize": 27,
        "buttonIconSize": 11, "buttonSpacing": 4, "selectionCircleSize": 19, "selectionBarHeight": 44,
        "selectionStripGap": 16, "autoScrollZone": 44, "autoScrollSpeed": 600, "thumbnailSeconds": 5,
        "toastSeconds": 1.7, "slideInDuration": 0.75, "slideOutDuration": 0.3, "staggerDelay": 0.05,
        "staggerTotalMax": 0.3, "relayoutDuration": 0.2, "insertDuration": 0.5, "expandDuration": 0.25,
        "hoverRevealDuration": 0.15, "flightArc": 0.08, "flightArcMax": 64, "flightDepth": 0.05, "motion": 1,
        "backdropWidth": 290, "backdropTint": 0, "backdropTintStart": 0, "backdropBlurRadius": 13,
        "backdropBands": 3, "backdropRampPower": 2, "backdropFadeIn": 0.35, "backdropFadeOut": 0.35,
        "backdropSlideIn": 0.5, "backdropSlideOut": 0.3, "dimOpacity": 0.5, "dimBlurRadius": 12,
        "dimFade": 0.4, "annotationMinWidth": 770, "annotationMinHeight": 320, "annotationCornerRadius": 10,
        "annotationToolbarGap": 12, "annotationScreenInset": 65, "zoomEdgeBandPoints": 120,
        "zoomEdgePull": 0.5, "dragDistance": 4, "hitMargin": 4, "cornerHitSize": 13.5, "edgeHitSize": 9,
        "smallSide": 16, "handleSize": 8, "dotRadius": 4, "dotHitRadius": 12, "smallestRectangle": 4,
        "shortestArrow": 8, "textDragDelay": 0.15, "textDragDistance": 24, "newTextSize": 24,
        "selectionOutlineWidth": 3.5, "textWeight": 500, "textLineHeight": 1.35, "arrowheadLength": 4.5,
        "arrowheadWidth": 4, "stitchLongSide": 4096,
    ]

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

    // MARK: File

    nonisolated static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.userInfo[UITweaks.differencesOnly] = true
        return enc
    }

    @discardableResult
    private static func write(_ raw: Data, to url: URL) -> Data? {
        (try? writeOrThrow(raw, to: url)).map { raw }
    }

    private static func writeOrThrow(_ raw: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try raw.write(to: url, options: .atomic)
    }

    private nonisolated static func deepMerge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var out = base
        for (k, v) in over {
            if let b = base[k] as? [String: Any], let o = v as? [String: Any] { out[k] = deepMerge(b, o) } else { out[k] = v }
        }
        return out
    }

    /// Three-way merge from `base`, what the file and the app last agreed on: a key the app changed
    /// takes the app's value, and every other key the file's. Where both changed a key, the file's
    /// value stands, and the key is listed in `conflicts`. nil when one of them does not encode.
    nonisolated static func merged(base: SettingsData, app: SettingsData, file: SettingsData) -> (data: SettingsData, conflicts: [String])? {
        func object(_ d: SettingsData) -> [String: Any]? {
            (try? JSONEncoder().encode(d)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        // JSONSerialization's values are all NSObjects, which compare with `isEqual`.
        func same(_ a: Any?, _ b: Any?) -> Bool { (a as? NSObject) == (b as? NSObject) }
        func merge(_ base: [String: Any], _ app: [String: Any], _ file: [String: Any], path: String,
                   conflicts: inout [String]) -> [String: Any] {
            var out = file
            for key in Set(app.keys).union(base.keys) where !same(app[key], base[key]) {
                if let b = base[key] as? [String: Any], let a = app[key] as? [String: Any], let f = file[key] as? [String: Any] {
                    out[key] = merge(b, a, f, path: "\(path)\(key).", conflicts: &conflicts)
                } else if same(file[key], base[key]) {
                    out[key] = app[key]
                } else if !same(file[key], app[key]) {
                    conflicts.append(path + key)
                }
            }
            return out
        }
        guard let b = object(base), let a = object(app), let f = object(file) else { return nil }
        var conflicts: [String] = []
        let out = merge(b, a, f, path: "", conflicts: &conflicts)
        guard let raw = try? JSONSerialization.data(withJSONObject: out),
              let data = try? JSONDecoder().decode(SettingsData.self, from: raw) else { return nil }
        return (data, conflicts.sorted())
    }

    private func send(_ event: SettingsSync.Event) {
        // An event sent while effects run (an `onChange` handler's `update`, or the answer to
        // `.writeAppData` or `.readFileAndFlush`) is reduced after the current event's effects.
        hold.send(event) { event in
            let effects = sync.reduce(event)
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
            Settings.write(raw, to: Settings.fileURL)
            watchFile()   // atomic write replaced the inode
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

/// Apple's screenshot defaults (`defaults read com.apple.screencapture`). A launch with
/// `VIGNETTE_SETTINGS` reads and writes `<bundle id>.screencapture` instead, so a test copy never
/// takes or moves the user's save location. macOS itself never reads that domain.
enum AppleScreencapture {
    static let domainName = (ProcessInfo.processInfo.environment["VIGNETTE_SETTINGS"].map { !$0.isEmpty } ?? false) ? "\(Identity.bundleID).screencapture" : "com.apple.screencapture"
    private static let domain = domainName as CFString

    static func string(_ key: String) -> String? { CFPreferencesCopyAppValue(key as CFString, domain) as? String }
    static func bool(_ key: String) -> Bool? { CFPreferencesCopyAppValue(key as CFString, domain) as? Bool }

    /// Where macOS sends a capture: `file`, or `clipboard`, `mail` or `preview` when ⌘⇧5's Options
    /// name those. Unset means a file.
    static var target: String { string("target") ?? "file" }

    /// The target as the Screenshot app's Options menu names it.
    static func targetName(_ target: String) -> String {
        switch target {
        case "clipboard": "the Clipboard"
        case "mail": "Mail"
        case "preview": "Preview"
        default: target
        }
    }

    /// Where macOS saves screenshots: the `location` key, or the Desktop when it is unset.
    static var location: String { string("location") ?? SettingsData().screenshotsFolder }

    /// Two folder paths name the same folder, whatever their tildes and trailing slashes.
    static func samePath(_ a: String, _ b: String) -> Bool {
        func standard(_ path: String) -> String {
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        }
        return standard(a) == standard(b)
    }

    /// Calls `changed` on the main thread whenever `key` changes, whoever changed it: the
    /// preferences daemon tells every process observing the key. Measured for `location` with a
    /// `defaults write` from another process: 10 to 35 ms.
    static func observe(_ key: String, _ changed: @escaping @MainActor @Sendable () -> Void) -> Observer? {
        UserDefaults(suiteName: domainName).map { Observer(defaults: $0, key: key, changed: changed) }
    }

    final class Observer: NSObject {
        private let defaults: UserDefaults
        private let key: String
        private let changed: @MainActor @Sendable () -> Void

        init(defaults: UserDefaults, key: String, changed: @escaping @MainActor @Sendable () -> Void) {
            self.defaults = defaults
            self.key = key
            self.changed = changed
            super.init()
            defaults.addObserver(self, forKeyPath: key, options: [], context: nil)
        }

        deinit { defaults.removeObserver(self, forKeyPath: key) }

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

    /// When the animation `swiftUI(curve, duration:)` makes first covers `fraction` of its way.
    static func reaches(_ fraction: Double, curve: String, duration: Double) -> Double {
        switch curve {
        case "easeOut": return reaches(fraction, duration: duration) { UnitCurve.easeOut.value(at: $0) }
        case "easeInOut": return reaches(fraction, duration: duration) { UnitCurve.easeInOut.value(at: $0) }
        case "linear": return max(0, min(1, fraction)) * duration
        default: return reaches(fraction, spring: duration, bounce: flightBounce)
        }
    }

    /// When `spring(duration, bounce:)` first covers `fraction` of its way.
    static func reaches(_ fraction: Double, spring duration: Double, bounce: Double = 0) -> Double {
        let spring = Spring(duration: duration, bounce: bounce)
        return reaches(fraction, duration: duration) { spring.value(target: 1.0, time: $0 * duration) }
    }

    /// Searches `progress`, a function of the time as a fraction of `duration`, in 1/240 s steps.
    private static func reaches(_ fraction: Double, duration: Double, progress: (Double) -> Double) -> Double {
        guard duration > 0, fraction > 0 else { return 0 }
        let step = 1.0 / 240
        var t = 0.0
        while t < duration * 4, progress(t / duration) < fraction { t += step }
        return t
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

