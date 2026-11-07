import Foundation

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
    var liveInk = false                      // holding `liveInkChord` draws on the screen itself; needs Accessibility
    var liveInkOffered = false               // whether live ink's one-time offer was made to an install that finished setup before it had a page
    var liveInkAskedClaude = false           // whether a live ink ask has gone to Claude, which ends the line that says what Claude sees
    var liveInkAskedCodex = false            // the same for Codex
    var liveInkChord = LiveInkChord.standard.rawValue  // the two modifiers that hold live ink on: ⌃⌥ unless another pair is chosen
    var liveInkSpeech = false                // talking while drawing fills the note; needs the microphone and speech recognition
    var liveInkSendWhenQuiet = true          // experiment: the ask goes as the pair is let go, or waits for Return
    var debug = false                        // unlocks tweaks, install-skill root=, live-ink-stroke, and file= outside the watch folder
    var agentSkill = AgentSkill.unasked.rawValue  // whether the skill was offered: unasked, then off
    var setup = SetupState.unasked.rawValue  // whether the setup window has run: unasked, then done
    var ui = UITweaks()                      // visual and timing knobs; the debug panel edits these live
    var appleOriginal: AppleOriginal?        // Apple's screencapture values before Vignette changed them

    var folderURL: URL { URL(fileURLWithPath: (screenshotsFolder as NSString).expandingTildeInPath) }

    /// `liveInkChord` as the pair it holds. An unknown word reads as the standard pair.
    var liveInkChordChoice: LiveInkChord { LiveInkChord(rawValue: liveInkChord) ?? .standard }

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
