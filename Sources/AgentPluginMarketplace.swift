import Foundation

extension AgentPlugin {
    /// Writes the marketplace the agents install from: `template` with `skill` in it, the inbox path
    /// the scripts read, the requests folder the skill's reply helper takes tickets from, and
    /// `marketplace`, the URL scheme, as both lists' name. The skill is written
    /// for Vignette, so it is rewritten to name this copy: `app`, its scheme and its log (`retarget`).
    /// It is assembled beside `folder` and swapped in whole, so an agent never reads half of it.
    /// Returns whether anything changed.
    @discardableResult
    static func stage(template: URL, skill: URL, into folder: URL, inboxRoot: URL, requestsRoot: URL, marketplace: String,
                      appName: String, app: URL) throws -> Bool {
        let fileManager = FileManager.default
        let parent = folder.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".\(folder.lastPathComponent)-incoming")
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: staging)
        do {
            try fileManager.copyItem(at: template, to: staging)
            let plugin = pluginFolder(in: staging)
            let skills = plugin.appendingPathComponent("skills")
            try fileManager.createDirectory(at: skills, withIntermediateDirectories: true)
            try fileManager.copyItem(at: skill, to: skills.appendingPathComponent(name))
            try write(requestsRoot: requestsRoot, into: skills.appendingPathComponent("\(name)/scripts/reply"))
            try retarget(skill: skills.appendingPathComponent(name).appendingPathComponent("SKILL.md"), scheme: marketplace, appName: appName,
                         app: app)
            try Data((inboxRoot.path + "\n").utf8).write(to: plugin.appendingPathComponent("scripts/inbox-root"))
            for list in [".claude-plugin/marketplace.json", ".agents/plugins/marketplace.json"] {
                try rename(list: staging.appendingPathComponent(list), to: marketplace)
            }
            if SkillFiles.matches(source: staging, installed: folder) {
                try fileManager.removeItem(at: staging)
                return false
            }
            if fileManager.fileExists(atPath: folder.path) {
                _ = try fileManager.replaceItemAt(folder, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: folder)
            }
            return true
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    /// Points the skill's commands and log at this copy of the app. Left as written, a test copy's or
    /// a fork's agent would drive the real Vignette. Every `open -g` names `app` with `-a`: a bare
    /// `open` goes to the copy LaunchServices registered last, which on a Mac with another build of
    /// the app can be one that is not running, and it starts that build on the person's settings.
    private static func retarget(skill: URL, scheme: String, appName: String, app: URL) throws {
        let text = try String(contentsOf: skill, encoding: .utf8)
        let quoted = "'" + app.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let aimed = try NSRegularExpression(pattern: #"open -g ("?)vignette://"#)
            .stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                      withTemplate: NSRegularExpression.escapedTemplate(for: "open -g -a \(quoted) ") + "$1vignette://")
        try aimed.replacingOccurrences(of: "vignette://", with: "\(scheme)://")
            .replacingOccurrences(of: "Logs/Vignette.log", with: "Logs/\(appName).log")
            .write(to: skill, atomically: true, encoding: .utf8)
    }

    /// Writes the requests folder into the reply helper's `requests_root=` line. A folder the helper
    /// read from beside itself would follow `$0`, which the caller chooses. Written in place, the file
    /// keeps its executable bit.
    private static func write(requestsRoot: URL, into reply: URL) throws {
        let text = try String(contentsOf: reply, encoding: .utf8)
        let line = "\nrequests_root=\n"
        guard text.contains(line) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "the reply helper has no requests_root line"])
        }
        let quoted = "'" + requestsRoot.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        try text.replacingOccurrences(of: line, with: "\nrequests_root=\(quoted)\n").write(to: reply, atomically: false, encoding: .utf8)
    }

    /// Sets a marketplace list's top-level `name`.
    private static func rename(list: URL, to marketplace: String) throws {
        let data = try Data(contentsOf: list)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard object["name"] as? String != marketplace else { return }
        object["name"] = marketplace
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: list)
    }
}
