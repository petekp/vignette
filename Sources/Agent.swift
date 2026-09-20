import AppKit

/// Which agent added a screenshot. `add?file=…&agent=<name>` records the name on the copied file
/// as an extended attribute: it travels with the file through a rename or a move on the same
/// volume, needs no database and no sweep, and a card reads it back when it is made. A copy to
/// another volume or through a tool that drops attributes loses it, and the card is then plain.
enum Agent {
    /// Where the name is stored. Named after the bundle, like everything else a fork renames.
    static let attribute = Identity.bundleID + ".agent"
    /// Longest name that is stored or shown. A name is a label, not a payload.
    static let maxLength = 64

    /// The `agent=` value as it may be stored: one line, trimmed, and short. Nil when the parameter
    /// was not given; empty when it was given without a name, which still means an agent added the file.
    static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let oneLine = value.components(separatedBy: .controlCharacters).joined()
        return String(oneLine.trimmingCharacters(in: .whitespaces).prefix(maxLength))
    }

    /// Records `name` on the file. A failure is logged and otherwise ignored: the badge is a hint,
    /// and the push itself has already succeeded.
    static func record(_ name: String, on url: URL) {
        let bytes = Array(name.utf8)
        guard setxattr(url.path, attribute, bytes, bytes.count, 0, 0) != 0 else { return }
        Log.write("[add] warning could not record the agent on \(url.lastPathComponent): \(String(cString: strerror(errno)))")
    }

    /// The agent that added this file, or nil when none did. One `getxattr`, about 4 µs (measured),
    /// so a card reads it as it is made; it is the folder listing that must not touch every file.
    static func of(_ url: URL) -> String? {
        var buffer = [UInt8](repeating: 0, count: maxLength * 4)
        let size = getxattr(url.path, attribute, &buffer, buffer.count, 0, 0)
        guard size >= 0 else { return nil }
        return String(decoding: buffer.prefix(size), as: UTF8.self)
    }

    /// What the badge says: "From Claude" for `agent=claude`, "From an agent" for a push with no name.
    static func label(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "From an agent" }
        return "From " + first.uppercased() + trimmed.dropFirst()
    }

    /// The vendor's logo, `Resources/agents/<name>.svg` in the bundle, or nil for a vendor without one.
    /// Loaded once per name; the SVG is rasterized by AppKit at the size it is drawn.
    @MainActor static func logo(for name: String) -> NSImage? {
        let key = name.lowercased()
        if let cached = logos[key] { return cached }
        let image = Bundle.main.url(forResource: key, withExtension: "svg", subdirectory: "agents").flatMap { NSImage(contentsOf: $0) }
        logos[key] = .some(image)
        return image
    }
    @MainActor private static var logos: [String: NSImage?] = [:]

    /// The glyph for a vendor without a logo: the closest SF Symbol to the robot this wants to be.
    static let fallbackSymbol = "cpu"
}
