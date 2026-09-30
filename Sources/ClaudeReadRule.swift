import Foundation

/// Claude Code asks before it reads a file outside the session's folder, and the image Send puts in a
/// session is in Vignette's request folder, so a session stops on that question when it opens the
/// drawing, and every request sent to it after waits behind that question.
/// This rule in Claude Code's own settings lets it read the sent images, and nothing else of Vignette's,
/// without asking. The person turns it on: it is their Claude Code's configuration.
enum ClaudeReadRule {
    struct Failure: Error { let reason: String }

    /// `Read(~/Library/Application Support/<bundle id>/requests/*/image.png)`: every request's image,
    /// in Claude Code's permission syntax, which takes `~/` for the home folder and the path's spaces
    /// as they are.
    static func rule(requests: URL = ScreenshotRequests.defaultRoot,
                     home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let path = requests.appendingPathComponent("*/image.png").path
        let homePath = home.path.hasSuffix("/") ? home.path : home.path + "/"
        return "Read(" + (path.hasPrefix(homePath) ? "~/" + path.dropFirst(homePath.count) : "/" + path) + ")"
    }

    /// The switch's words, in the Agents tab and on setup's last page.
    static let title = "Claude Code reads your drawings without asking"
    static let explanation = "Adds a rule to Claude Code's settings for the drawings you send. Without it, Claude Code asks before opening them."

    /// The switch: sets the rule and logs it. Answers why it failed, for the line under the switch.
    @discardableResult
    static func apply(_ on: Bool, in root: URL) -> String? {
        let url = settingsFile(in: root)
        do {
            try set(on, in: root)
            Log.write("[permissions] \(on ? "added" : "removed") \(rule()) in \(url.path)")
            return nil
        } catch {
            let reason = (error as? Failure)?.reason ?? error.localizedDescription
            Log.write("[permissions] error write-failed \(url.path): \(reason)")
            return "Couldn't change Claude Code's settings: \(reason)."
        }
    }

    /// Claude Code's user settings under an agent directory (`~/.claude`).
    static func settingsFile(in root: URL) -> URL { root.appendingPathComponent("settings.json") }

    static func isSet(in root: URL, rule: String = rule()) -> Bool {
        guard let settings = try? read(settingsFile(in: root)) else { return false }
        return allowList(of: settings).contains(rule)
    }

    /// Adds or removes the rule, leaving every other setting as it was. A file that does not parse is
    /// left alone and reported, since rewriting it would lose what the person wrote.
    static func set(_ on: Bool, in root: URL, rule: String = rule()) throws {
        let url = settingsFile(in: root)
        var settings = try read(url)
        // Anything but a list of rules where one belongs is the person's to fix, not to replace.
        guard settings["permissions"] == nil || settings["permissions"] is [String: Any],
              (settings["permissions"] as? [String: Any])?["allow"].map({ $0 is [String] }) ?? true else {
            throw Failure(reason: "its permissions in settings.json aren't in the shape Vignette expects, so it left them alone")
        }
        var allow = allowList(of: settings)
        guard allow.contains(rule) != on else { return }
        if on { allow.append(rule) } else { allow.removeAll { $0 == rule } }
        // Off leaves no empty list or section behind, so on and then off is the file as it was.
        var permissions = settings["permissions"] as? [String: Any] ?? [:]
        permissions["allow"] = allow.isEmpty ? nil : allow
        settings["permissions"] = permissions.isEmpty ? nil : permissions
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            // An atomic write replaces a link with a plain file, and people keep this file in a
            // dotfiles repository through one, so the write goes to the file the link names. The
            // replacement file would also take default permissions, so the old ones are put back.
            let target = url.resolvingSymlinksInPath()
            let permissions = (try? FileManager.default.attributesOfItem(atPath: target.path))?[.posixPermissions]
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            if let permissions { try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path) }
        } catch {
            throw Failure(reason: error.localizedDescription)
        }
    }

    /// The settings as a dictionary; a missing file is empty settings.
    private static func read(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(reason: "its settings.json doesn't parse, so Vignette left it alone")
        }
        return object
    }

    private static func allowList(of settings: [String: Any]) -> [String] {
        (settings["permissions"] as? [String: Any])?["allow"] as? [String] ?? []
    }
}
