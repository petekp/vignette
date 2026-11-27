import Foundation

/// Where macOS's permission for the watch folder stands, as the setup window shows it.
enum FolderAccess {
    /// Nothing has read the folder yet, so macOS has not asked.
    case ask
    /// Something has, and macOS's prompt is waiting for an answer.
    case waiting
    case granted
    case refused
}

/// Why the watch folder can't be read, when macOS has not refused it.
enum FolderReadFailure: Equatable {
    /// The folder isn't there: a volume that is not mounted, or a folder moved or deleted.
    case notFound
    /// Opening or listing it fails, as when macOS's sandbox daemon does not answer.
    case failed
}

/// What the setup window reacts to, read together each time it looks: the permissions, the watch
/// folder and macOS's own screenshot settings. Setup reads them from this Mac, and the Setup Lab
/// sets them.
struct SetupConditions: Equatable {
    /// Trusted for Accessibility, which the double tap and live ink need.
    var trusted: Bool
    /// Allowed to record the screen, which live ink's asks need.
    var screenRecording: Bool
    /// macOS's window picker question, which the first capture after that raises (`PickerQuestion`).
    var pickerQuestion: PickerQuestion.Status
    /// The folder macOS will ask about, as setup names it ("your Desktop"), or nil when it won't
    /// ask, which leaves the welcome page without a folder row.
    var protectedArea: String?
    var folder: FolderAccess
    /// Why the folder has failed to read for longer than `ui.unreadableFolderSeconds`, other than
    /// a refusal, which `folder` says. Nil while it reads.
    var folderReadFailure: FolderReadFailure? = nil
    var hasScreenshots: Bool
    /// ⌘⇧5's Save to: `file`, or where else macOS sends screenshots (`AppleScreencapture.target`).
    var saveTarget: String
    /// Whether the menu bar icon can be seen: it is off, or macOS found no room for it.
    var menuBarIconVisible: Bool

    /// Screen Recording is allowed and macOS's window picker question answered, so live ink's first
    /// ask meets no question of macOS's.
    var screenRecordingSetUp: Bool { screenRecording && pickerQuestion == .answered }
}
