import AppKit

/// macOS's own prompts: a privacy question such as macOS 15's "bypass the system private window
/// picker", the Accessibility alert, a password panel, Gatekeeper's question. Each is a window of a
/// process of macOS's own, which comes up over the app the person is in.
enum SystemPrompts {
    /// The processes that own them, as the window list names them. Owner names need no Screen
    /// Recording permission.
    static let owners: Set<String> = ["UserNotificationCenter", "universalAccessAuthWarn", "SecurityAgent", "CoreServicesUIAgent"]

    /// The window list's entry is one of them.
    static func isPrompt(_ info: [String: Any]) -> Bool {
        (info[kCGWindowOwnerName as String] as? String).map(owners.contains) ?? false
    }

    /// The ones on the screen.
    static func windowIDs() -> Set<CGWindowID> {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(windows.filter(isPrompt).compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
    }
}
