import AppKit

extension AppDelegate {
    /// What the menu lists first, as the way to fix it, and the intro's popover names.
    enum Blocker {
        case folderAccess
        /// The folder has failed to read for a while, for a reason other than a refusal.
        case folderReadFailure(FolderReadFailure)
        /// macOS saves captures somewhere other than a folder, named for a person ("the Clipboard").
        case saveTarget(String)
        /// Accessibility, for the double tap, live ink, or both.
        case accessibility(shortcut: Bool, liveInk: Bool)
        /// Screen Recording, which live ink's asks need to see the window under the ink.
        case screenRecording
    }

    /// What is missing under `conditions`, for someone who uses live ink or not.
    func missing(in conditions: SetupConditions, usesLiveInk liveInk: Bool) -> [Blocker] {
        var missing: [Blocker] = []
        if conditions.folder == .refused { missing.append(.folderAccess) }
        if let failure = conditions.folderReadFailure { missing.append(.folderReadFailure(failure)) }
        if conditions.saveTarget != "file" { missing.append(.saveTarget(AppleScreencapture.targetName(conditions.saveTarget))) }
        let shortcut = settings.data.usesDoubleTap
        if shortcut || liveInk, !conditions.trusted { missing.append(.accessibility(shortcut: shortcut, liveInk: liveInk)) }
        if liveInk, !conditions.screenRecording { missing.append(.screenRecording) }
        return missing
    }

    /// What the intro's popover says is still missing: one sentence for one thing, else a list
    /// worded as the menu items are.
    func missingNote(_ missing: [Blocker]) -> MenuBarIntro.Note? {
        guard let only = missing.first else { return nil }
        guard missing.count == 1 else {
            return .list("Click the icon to:", missing.map { blocker in
                switch blocker {
                case .folderAccess: "Allow access to your screenshots"
                case .folderReadFailure(.notFound): "See why \(Identity.name) can't find your screenshots folder"
                case .folderReadFailure(.failed): "See why \(Identity.name) can't read your screenshots yet"
                case .saveTarget: "Save screenshots to a folder"
                case let .accessibility(shortcut, liveInk):
                    "Allow Accessibility for \(shortcut && liveInk ? "the shortcut and live ink" : shortcut ? "the shortcut" : "live ink")"
                case .screenRecording: "Allow Screen Recording for live ink"
                }
            })
        }
        switch only {
        case .folderAccess: return .text("\(Identity.name) can't open your screenshots folder. Click the icon to allow it.")
        case .folderReadFailure(.notFound): return .text("\(Identity.name) can't find your screenshots folder. It keeps looking.")
        case .folderReadFailure(.failed):
            return .text("macOS isn't letting \(Identity.name) read your screenshots folder yet. \(Identity.name) keeps trying.")
        case let .saveTarget(target): return .text("macOS sends your screenshots to \(target). Click the icon to save them to a folder.")
        case let .accessibility(shortcut, liveInk):
            let what = shortcut && liveInk ? "The shortcut and live ink need" : shortcut ? "The shortcut needs" : "Live ink needs"
            return .text("\(what) Accessibility. Click the icon to allow it.")
        case .screenRecording: return .text("Live ink needs Screen Recording. Click the icon to allow it.")
        }
    }

    /// Where macOS's permission for the folder stands, as setup shows it.
    var folderAccess: FolderAccess {
        guard let watcher else { return .ask }
        if watcher.isDenied { return .refused }
        return watcher.isReadable ? .granted : .waiting
    }

    /// Why the watch folder has failed to read for longer than `ui.unreadableFolderSeconds`, when
    /// macOS has not refused it.
    var folderReadFailure: FolderReadFailure? {
        switch watcher?.unreadable(after: settings.data.ui.unreadableFolderSeconds) {
        case .missing: .notFound
        case .unavailable: .failed
        case .refused, .available, nil: nil
        }
    }

    /// Why a press found nothing to show, for the log, when the folder is what stopped it.
    var unreadableFolder: String? {
        if watcher?.isDenied == true { return "macOS refused \(watchFolder.path)" }
        switch folderReadFailure {
        case .notFound: return "cannot find \(watchFolder.path)"
        case .failed: return "cannot read \(watchFolder.path)"
        case nil: return nil
        }
    }
}
