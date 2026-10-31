import Foundation

/// A launch with `VIGNETTE_SETTINGS` set is a test launch. It reads and writes that settings file and
/// its own screenshot defaults, and reaches nothing else of the person's: no login item, and no
/// update feed, agent folder or agent tool the environment does not name.
enum Launch {
    static let settingsPath = settingsPath(in: ProcessInfo.processInfo.environment)
    static let isTest = settingsPath != nil

    static func isTest(in environment: [String: String]) -> Bool {
        settingsPath(in: environment) != nil
    }

    private static func settingsPath(in environment: [String: String]) -> String? {
        environment["VIGNETTE_SETTINGS"].flatMap { $0.isEmpty ? nil : $0 }
    }
}
