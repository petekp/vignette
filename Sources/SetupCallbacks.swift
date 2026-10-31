import AppKit
import Combine

extension SetupWindowController {
    /// What the window reads and asks for rather than doing itself: AppDelegate's parts, macOS's
    /// permissions, and the records setup makes, which `show` supplies. A test run from the Setup
    /// Lab leaves the records out and supplies the lab's conditions, so trying it changes nothing.
    struct Callbacks {
        /// Asked again on every look rather than read once: a grant, or a folder filled while the
        /// window is open, is what the window is asking for.
        var conditions: () -> SetupConditions = {
            SetupConditions(trusted: true, screenRecording: true, protectedArea: nil, folder: .granted,
                            hasScreenshots: false, saveTarget: "file", menuBarIconVisible: true)
        }
        /// The agents the last page offers the plugin to.
        var agents: () -> [AgentPluginStatus] = { [] }
        /// Whether Claude Code and Codex can answer, and Codex's sign-in, on the live ink pages.
        var responders = ResponderStatus.inert
        /// Sends, on the main thread once the change has landed, when something `conditions` or
        /// `agents` reads has changed, so the window looks now rather than at its next poll.
        var changes: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()
        /// Starts the watcher, whose first read of a protected folder is what raises macOS's prompt.
        var askFolder: () -> Void = {}
        /// After a refusal. macOS doesn't ask twice, so the answer is changed where it keeps it.
        var openFolderSettings: () -> Void = {}
        var askAccessibility: () -> Void = {}
        var askScreenRecording: () -> Void = {}
        var openScreenRecordingSettings: () -> Void = {}
        /// Sets ⌘⇧5's Save to back to a folder.
        var saveToFolder: () -> Void = {}
        /// The Open at login setting as setup opens. The welcome page's switch starts from it.
        var launchAtLogin: () -> Bool = { true }
        var installAgentPlugin: ([URL]) -> Void = { _ in }
        /// Flies the closing window into the menu bar icon, with a popover naming what the conditions
        /// setup saw leave missing for someone who uses live ink or not. Calls `close` once the window
        /// may close, and `finished` once the intro has gone. False when there is no intro, and the
        /// window closes as any window does.
        var introduceMenuBar: (NSWindow, SetupConditions, _ usesLiveInk: Bool, _ close: @escaping () -> Void,
                               _ finished: @escaping () -> Void) -> Bool = { _, _, _, _, _ in false }
        /// The answer on the live ink page: live ink on or off.
        var choseLiveInk: (Bool) -> Void = { _ in }
        /// Screen Recording was asked for, which macOS answers by asking to quit and reopen the app.
        var askedForScreenRecording: () -> Void = {}
        /// The window closed.
        var closed: (SetupModel) -> Void = { _ in }
    }
}
