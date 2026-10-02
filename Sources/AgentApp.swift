import AppKit

/// An agent client's own app. When it was the app in front before Vignette, it is where you came
/// from, and the session it shows is where Send starts (`AgentDestination.cameFrom`).
enum AgentApp {
    /// The Codex app. Its process and its window are both named ChatGPT.
    static let codexBundleID = "com.openai.codex"

    /// The CLI inside the Codex app, wherever the app is installed. It comes before any other
    /// codex: the app updates it with itself, so it matches the engine that holds the app's threads,
    /// where a CLI installed on its own falls behind (0.154.0 beside the app's 0.159.2, 2026-10-01).
    static var codexCLI: String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: codexBundleID)?
            .appendingPathComponent("Contents/Resources/codex-cli/bin/codex").path
    }

    /// The client whose own app this is, or nil for any other app.
    static func client(of app: NSRunningApplication?) -> AgentClient? {
        app?.bundleIdentifier == codexBundleID ? .codex : nil
    }

    /// The id of the thread the Codex app shows, from the app's own log. Nil when it shows something
    /// else (its home, a new thread not sent yet, a ChatGPT chat) or its log does not say.
    ///
    /// The app logs a `received browser sidebar owner sync` line with `ownerRoutePath=/local/<id>`
    /// each time its window moves to another page (every build from 2026-09-18 to 26.928 on
    /// 2026-10-01). That is a log line rather than an interface, so a build that drops it gives the
    /// thread used last. Accessibility no longer answers: the app's window has had no page in its
    /// accessibility tree since it left Electron (openai/codex#25740). This reads files, so call it
    /// off the main thread.
    static func shownThread(pid: pid_t, launched: Date?,
                            logs: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/\(codexBundleID)")) -> String? {
        for file in logFiles(of: pid, launched: launched, in: logs) {
            if let route = lastRoute(in: file) { return thread(inRoute: route) }
        }
        return nil
    }

    /// The process's log files, the one written last first. The app files them under the UTC day it
    /// opened them, `<year>/<month>/<day>/codex-desktop-<run>-<pid>-<part>.log`, so the walk goes back
    /// day by day and stops before the day the process started, where a file with its pid is
    /// another process's.
    static func logFiles(of pid: pid_t, launched: Date?, in logs: URL) -> [URL] {
        let manager = FileManager.default
        func newestFirst(_ folder: URL) -> [URL] {
            let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.filter { Int($0) != nil }.sorted { Int($0)! > Int($1)! }.map { folder.appendingPathComponent($0) }
        }
        let start = launched.map { day(of: $0) }
        var files: [URL] = [], days = 0
        for year in newestFirst(logs) {
            for month in newestFirst(year) {
                for folder in newestFirst(month) {
                    let parts = folder.pathComponents.suffix(3).joined(separator: "/")
                    if let start, parts < start { return files }
                    days += 1
                    if start == nil && days > 14 { return files }
                    let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
                    let own = names.filter { $0.hasPrefix("codex-desktop-") && $0.hasSuffix(".log") && $0.contains("-\(pid)-") }
                        .map { folder.appendingPathComponent($0) }
                    let dated = own.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
                    files += dated.sorted { $0.1 > $1.1 }.map(\.0)
                }
            }
        }
        return files
    }

    /// `2026/10/02` for a date, in UTC, the way the app names its day folders.
    private static func day(of date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static let routeLine = Data("received browser sidebar owner sync".utf8)
    private static let routeKey = "ownerRoutePath="

    /// The route on the last page-change line in `file`. A file is at most about 10 MB before the app
    /// starts another, and it is mapped rather than read, so the search from its end touches only
    /// the pages it passes.
    static func lastRoute(in file: URL) -> String? {
        guard let data = try? Data(contentsOf: file, options: .alwaysMapped) else { return nil }
        var end = data.endIndex
        while let found = data.range(of: routeLine, options: .backwards, in: data.startIndex..<end) {
            let lineEnd = data[found.upperBound...].firstIndex(of: UInt8(ascii: "\n")) ?? data.endIndex
            let rest = String(decoding: data[found.upperBound..<lineEnd], as: UTF8.self)
            if let key = rest.range(of: routeKey) {
                return String(rest[key.upperBound...].prefix { !$0.isWhitespace })
            }
            end = found.lowerBound
        }
        return nil
    }

    /// The thread a route shows: `/local/<id>` is a Codex thread on this Mac. Every other route is
    /// a page with no thread Vignette can send to.
    static func thread(inRoute route: String) -> String? {
        let parts = route.split(separator: "/")
        guard parts.count == 2, parts[0] == "local", UUID(uuidString: String(parts[1])) != nil else { return nil }
        return String(parts[1])
    }
}
