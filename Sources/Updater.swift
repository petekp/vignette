import AppKit
@preconcurrency import Sparkle

/// Sparkle, checking the feed in Info.plist (`SUFeedURL`) once a day and verifying each download
/// against `SUPublicEDKey`. A version found by a scheduled check waits as a gentle reminder: a dot on
/// the status item and an item at the top of its menu, never a window that takes the focus from the
/// app the person is in. Choosing either opens Sparkle's own window, and nothing installs until the
/// person presses Install there. With the menu bar icon hidden there is no place for a reminder, so
/// Sparkle shows its window as usual.
@MainActor
final class Updater: NSObject {
    /// The version a scheduled check found and the person has not looked at yet, as Sparkle
    /// displays it.
    private(set) var waiting: String? { didSet { if waiting != oldValue { onChange?() } } }
    /// Called when `waiting` changes, to put the dot on the status item or take it off.
    var onChange: (() -> Void)?
    /// Whether the status item is there to carry a reminder.
    var hasStatusItem: () -> Bool = { false }

    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    /// False while a check or an update is already under way.
    var canCheck: Bool { controller.updater.canCheckForUpdates }

    /// Checks now, or brings forward the update a scheduled check already found.
    @objc func checkForUpdates(_ sender: Any?) {
        Log.write("[update] check asked\(waiting.map { " waiting=\($0)" } ?? "")")
        controller.checkForUpdates(sender)
    }

    var stateJSON: [String: Any] {
        [
            "waiting": waiting as Any,
            "canCheck": canCheck,
            "automaticChecks": controller.updater.automaticallyChecksForUpdates,
            "lastCheck": controller.updater.lastUpdateCheckDate.map { ISO8601DateFormatter().string(from: $0) } as Any,
        ]
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let found = "\(item.displayVersionString) (\(item.versionString))"
        MainActor.assumeIsolated { Log.write("[update] found \(found)") }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        let reason = (error as NSError).localizedDescription
        MainActor.assumeIsolated { Log.write("[update] none: \(reason)") }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let error = error as NSError
        // Sparkle ends a check that found nothing through here too; `none` already logged it.
        if error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue) { return }
        let detail = "\(error.domain) \(error.code) \(error.localizedDescription)"
        MainActor.assumeIsolated { Log.write("[update] error \(detail)") }
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { Log.write("[update] installing \(version)") }
    }

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { Log.write("[update] relaunching") }
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows a scheduled update itself only when there is no status item to show it on.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        MainActor.assumeIsolated { !hasStatusItem() }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let version = update.displayVersionString
        let userInitiated = state.userInitiated
        MainActor.assumeIsolated {
            if !handleShowingUpdate && !userInitiated {
                Log.write("[update] waiting \(version)")
                waiting = version
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { waiting = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { waiting = nil }
    }
}
