import AppKit

/// Report a Problem…: opens a new GitHub issue on the feedback form with the version and the Mac filled
/// in, then shows the log and this app's crash reports in Finder, since a browser cannot attach a
/// file by itself. The issue address is `VignetteIssuesURL` in Info.plist (project.yml), so a fork
/// reports to its own repository; without the key there is no menu item.
enum ProblemReport {
    static let issuesURL = (Bundle.main.infoDictionary?["VignetteIssuesURL"] as? String).flatMap(URL.init(string:))

    /// GitHub fills a form's field from the query item named by its id, `details` in
    /// `.github/ISSUE_TEMPLATE/bug_report.yml`. Released builds open that file by name.
    static func formURL(issues: URL, build: BuildInfo, mac: String) -> URL? {
        var parts = URLComponents(url: issues, resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            // Room to type on top. The blank line keeps `---` a rule; under a line of text it makes a heading.
            URLQueryItem(name: "details", value: "\n\n---\nVignette \(build.description) on \(mac)"),
        ]
        return parts?.url
    }

    /// "macOS 15.7.7 (24G720), Mac15,3"
    static func thisMac() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        let build = sysctl("kern.osversion").map { " (\($0))" } ?? ""
        return os + build + (sysctl("hw.model").map { ", \($0)" } ?? "")
    }

    /// This app's newest crash reports. macOS names them `<executable>-<date>.ips`, or `.crash`
    /// before macOS 12.
    static func crashReports(in folder: URL, executable: String, limit: Int = 3) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        func date(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("\(executable)-") && ["ips", "crash"].contains($0.pathExtension) }
            .sorted { date($0) > date($1) }
            .prefix(limit)
            .map { $0 }
    }

    @MainActor
    static func open() {
        guard let issues = issuesURL, let form = formURL(issues: issues, build: .current, mac: thisMac()) else { return }
        let executable = Bundle.main.executableURL?.lastPathComponent ?? Identity.name
        let reports = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let crashes = crashReports(in: reports, executable: executable)
        Log.write("[report] opening \(form.absoluteString) crashReports=\(crashes.count)")
        Log.flush()
        let files = ([Log.url] + crashes).filter { FileManager.default.fileExists(atPath: $0.path) }
        // Finder comes up after the browser, so the log is in front, ready to drag onto the form.
        NSWorkspace.shared.open(form, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting(files) }
        }
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }
}
