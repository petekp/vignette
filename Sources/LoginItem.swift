import Foundation
import ServiceManagement

/// Launch at login through `SMAppService`, behind the `launchAtLogin` setting. macOS keeps the
/// registration itself (System Settings > General > Login Items), so the app only reconciles:
/// the setting says what the user wants, `status` says what macOS has.
enum LoginItem {
    static var status: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .notRegistered: return "notRegistered"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }

    /// Registers or unregisters, logging one `[login]` line. Skips the call when macOS already
    /// agrees, so a launch with the setting on does not re-register every time.
    static func apply(_ enabled: Bool) {
        let current = SMAppService.mainApp.status
        do {
            if enabled, current != .enabled {
                try SMAppService.mainApp.register()
                Log.write("[login] registered status=\(status)")
            } else if !enabled, current != .notRegistered, current != .notFound {
                try SMAppService.mainApp.unregister()
                Log.write("[login] unregistered status=\(status)")
            }
        } catch {
            Log.write("[login] error \(enabled ? "register" : "unregister") failed: \(error.localizedDescription) status=\(status)")
        }
    }
}
