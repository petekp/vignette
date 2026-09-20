import Foundation

/// Version and build id as build.sh stamps them into Info.plist: `MARKETING_VERSION` for the
/// version, the git commit count for `CFBundleVersion`, and `git describe` for `VignetteBuild`.
struct BuildInfo: Equatable {
    let version: String
    let number: String
    let build: String

    init(info: [String: Any]) {
        version = info["CFBundleShortVersionString"] as? String ?? "dev"
        number = info["CFBundleVersion"] as? String ?? "0"
        build = info["VignetteBuild"] as? String ?? "unknown"
    }

    static let current = BuildInfo(info: Bundle.main.infoDictionary ?? [:])

    /// "0.1.0 (12, a1b2c3d)"
    var description: String { "\(version) (\(number), \(build))" }
}
