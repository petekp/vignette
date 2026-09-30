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

    /// The app's path when it last registered, in the app's own defaults rather than settings.json,
    /// since a registration belongs to this Mac and this copy.
    private static let registeredPathKey = "loginItemRegisteredPath"

    /// Whether the person took the login item out in System Settings: macOS no longer has it, and
    /// this copy is where it was when it registered. A copy that moved lost it without anyone asking.
    /// Removed with "−" under Open at Login, the status reads `.notFound` (measured on macOS 15).
    static var removedByPerson: Bool {
        [.notRegistered, .notFound].contains(SMAppService.mainApp.status)
            && UserDefaults.standard.string(forKey: registeredPathKey) == Bundle.main.bundleURL.path
    }

    /// Registers or unregisters, logging one `[login]` line. Skips the call when macOS already
    /// agrees, so a launch with the setting on does not re-register every time.
    /// A test launch never registers: macOS would open the copy at login without `VIGNETTE_SETTINGS`,
    /// on the person's own settings file.
    static func apply(_ enabled: Bool) {
        let current = SMAppService.mainApp.status
        // Also for a registration made before the path was kept.
        if current == .enabled { UserDefaults.standard.set(Bundle.main.bundleURL.path, forKey: registeredPathKey) }
        do {
            if enabled, current != .enabled, Settings.isOverridden {
                Log.write("[login] test launch: not registered status=\(status)")
            } else if enabled, current != .enabled {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(Bundle.main.bundleURL.path, forKey: registeredPathKey)
                Log.write("[login] registered status=\(status)")
            } else if !enabled, current != .notRegistered, current != .notFound {
                try SMAppService.mainApp.unregister()
                UserDefaults.standard.removeObject(forKey: registeredPathKey)
                Log.write("[login] unregistered status=\(status)")
            }
        } catch {
            Log.write("[login] error \(enabled ? "register" : "unregister") failed: \(error.localizedDescription) status=\(status)")
        }
    }
}
