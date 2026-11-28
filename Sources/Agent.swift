import AppKit
import CryptoKit

/// Which agent added a screenshot. `add?file=…&agent=<name>` records the name on the copied file
/// as an extended attribute: it travels with the file through a rename or a move on the same
/// volume, needs no database and no sweep, and a card reads it back when it is made. A copy to
/// another volume or through a tool that drops attributes loses it, and the card is then plain.
enum Agent {
    /// Where the name is stored. Named after the bundle, like everything else a fork renames.
    private static let attribute = Identity.bundleID + ".agent"
    /// Longest name that is stored or shown. A name is a label, not a payload.
    static let maxLength = 64

    /// The `agent=` value as it may be stored: one line, trimmed, and short. Nil when the parameter
    /// was not given; empty when it was given without a name, which still means an agent added the file.
    static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let oneLine = value.components(separatedBy: .controlCharacters).joined()
        return String(oneLine.trimmingCharacters(in: .whitespaces).prefix(maxLength))
    }

    /// Where the session a file came from is stored, whether a push or live ink recorded it: a
    /// Claude Code session, or a Codex thread. These names are a contract on files already in
    /// people's folders.
    private static func attribute(for client: AgentClient) -> String {
        switch client {
        case .claude: return Identity.bundleID + ".session"
        case .codex: return Identity.bundleID + ".thread"
        }
    }

    /// The `session=` value as it may be stored: a UUID, which is what a Claude Code session id and
    /// a Codex thread id are, in the lowercase herdr reports. Nil for anything else, including the
    /// empty value a push sends when its client set no id.
    static func cleanSession(_ value: String?) -> String? {
        guard let value, UUID(uuidString: value) != nil else { return nil }
        return value.lowercased()
    }

    /// The session a push names: `session=` as the address of `agent=`'s client, a Claude Code
    /// session for `claude` and a Codex thread for `codex`. Nil for another agent, or for a
    /// `session=` that is not a session id.
    static func pushOrigin(agent: String?, session: String?) -> AgentAddress? {
        guard let id = cleanSession(session), let client = agent.flatMap({ AgentClient(rawValue: $0.lowercased()) }) else { return nil }
        return AgentAddress(client: client, id: id)
    }

    /// Records the agent that added the file and the session it came from, which is what
    /// `origin(of:)` reads back. With an origin, its client is the agent. A session recorded by an
    /// earlier push and not named by this one is removed, so Reply never goes to it, and so is a
    /// send of the file (`Sent`), which was of the picture this push replaces, and the earlier
    /// push's sender (`record(sender:on:)`). A failure is
    /// logged and otherwise ignored: the push itself has already succeeded, and without the session
    /// Reply on the card asks where to send, as for a screenshot of your own.
    static func record(agent name: String, origin: AgentAddress?, on url: URL) {
        write(origin?.client.rawValue ?? name, attribute, "the agent", on: url)
        forgetSent(on: url)
        removexattr(url.path, senderAttribute, 0)
        for client in AgentClient.allCases {
            if let origin, origin.client == client {
                write(origin.id, attribute(for: client), "its session", on: url)
            } else {
                removexattr(url.path, attribute(for: client), 0)
            }
        }
    }

    /// Where the name of the session that pushed the file is stored: the agent's `from=`, else the
    /// session's title as its session menu row says it (`SessionListing.senderName`).
    private static let senderAttribute = Identity.bundleID + ".sender"
    /// The most characters a sender's name keeps: a herdr tab's label, a few words.
    static let maxSenderLength = 40

    /// `from=` as it may be stored and shown: one line, trimmed, and cut at a word to
    /// `maxSenderLength` with an ellipsis, and whether it was cut. Nil for a name with nothing in it.
    static func cleanSender(_ value: String?) -> (name: String?, cut: Bool) {
        let clipped = AgentTitle.clipped(AgentTitle.oneLine(value), to: maxSenderLength)
        return (clipped.text, clipped.cut)
    }

    /// Records the name of the session that pushed the file, which its tab says ("From vignette").
    /// Nil removes it. A failure is logged and otherwise ignored, as for the agent's name.
    static func record(sender: String?, on url: URL) {
        guard let sender else { removexattr(url.path, senderAttribute, 0); return }
        write(sender, senderAttribute, "its sender", on: url)
    }

    /// The name `record(sender:on:)` wrote, read back through `cleanSender`, or nil when the file has none.
    static func sender(of url: URL) -> String? {
        cleanSender(read(senderAttribute, of: url, upTo: titleBytes)).name
    }

    /// Where each part of an agent's title for the file is stored.
    private static func attribute(for part: AgentTitle.Part) -> String {
        Identity.bundleID + "." + part.rawValue
    }

    /// Records what the agent says the file shows, which the editor shows above it. A part this push
    /// does not give, or every part for a push with no title, is removed, so a second push of a file
    /// already in the folder leaves no stale line. A failure is logged and otherwise ignored, as for
    /// the name.
    static func record(title: AgentTitle?, on url: URL) {
        for (part, value) in [(AgentTitle.Part.title, title?.title), (.description, title?.description)] {
            if let value { write(value, attribute(for: part), "its \(part.rawValue)", on: url) } else { removexattr(url.path, attribute(for: part), 0) }
        }
    }

    /// The title `record(title:on:)` wrote, read back through `AgentTitle.validated`, or nil when
    /// the file has none.
    static func title(of url: URL) -> AgentTitle? {
        AgentTitle.validated(title: read(attribute(for: .title), of: url, upTo: titleBytes),
                             description: read(attribute(for: .description), of: url, upTo: titleBytes)).value
    }

    /// Where the fingerprint of the drawing the agent sent with the file is stored.
    private static let sentDrawingAttribute = Identity.bundleID + ".sentDrawing"

    /// SHA-256 over the drawing as its file holds it, without the screenshot's path, so a rename keeps
    /// it, and over the picture file's size and modification date, so an edit to the picture in
    /// another app is a change. A mark read back gets a new id and the file has none, so two reads of
    /// one drawing match. An empty drawing is one value whatever the drawing's scale. Its comments' session
    /// names are left out. Nil when the file is gone.
    private static func fingerprint(of drawing: Drawing?, file url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int, let modified = attributes[.modificationDate] as? Date else { return nil }
        var data = Data("\(size) \(modified.timeIntervalSinceReferenceDate)\n".utf8)
        if var drawing = drawing?.withoutSessionNames, !drawing.isEmpty {
            // The session list can name a session after the drawing was recorded (`Drawings.name`),
            // which is no change the person made.
            drawing.key = ""
            guard let encoded = try? drawing.encoded() else { return nil }
            data += encoded
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Records the drawing an agent sent with the file, a push's or a reply's, as it is now, so Reply
    /// can tell the person changed nothing (`hasSentDrawing`). Nil is no drawing.
    static func record(sentDrawing drawing: Drawing?, on url: URL) {
        guard let fingerprint = fingerprint(of: drawing, file: url) else { return forgetSentDrawing(on: url) }
        write(fingerprint, sentDrawingAttribute, "its drawing", on: url)
    }

    /// Removes the recorded drawing: a push that names no session, or one onto a file already drawn on.
    static func forgetSentDrawing(on url: URL) {
        removexattr(url.path, sentDrawingAttribute, 0)
    }

    /// True when `drawing` is exactly the drawing the agent sent with the file at `url`, on the same
    /// picture. False for a file no agent recorded one on: a person's screenshot, a live ink card, a
    /// push from an older build.
    static func hasSentDrawing(_ drawing: Drawing, at url: URL) -> Bool {
        guard let recorded = read(sentDrawingAttribute, of: url) else { return false }
        return recorded == fingerprint(of: drawing, file: url)
    }

    /// The last send of the file that reached its client: accepted, or queued by Codex. The card's
    /// tab says it ("Sent to vignette"), or, on an agent's card sent back to the session it came
    /// from, "Replied". `title` is what the send's notice called the session (`SessionMenu.cardTitle`).
    struct Sent: Codable, Equatable {
        let client: AgentClient
        let id: String
        let title: String
        let at: Date

        var address: AgentAddress { AgentAddress(client: client, id: id) }
    }

    /// Where the last send is stored, as JSON. A newer send replaces it.
    private static let sentAttribute = Identity.bundleID + ".sent"
    /// The most bytes a send is read with: a session's title is a tab's label, far shorter. A card
    /// reads it as it is made, so the buffer stays small.
    private static let sentBytes = 4096

    /// Records a send of the file. A failure is logged and otherwise ignored: the send itself went,
    /// and the card then shows no tab for it.
    static func record(sent: Sent, on url: URL) {
        guard let json = try? JSONEncoder().encode(sent) else { return }
        let bytes = Array(json)
        guard setxattr(url.path, sentAttribute, bytes, bytes.count, 0, 0) != 0 else { return }
        Log.write("[send] warning could not record the send on \(url.lastPathComponent): \(String(cString: strerror(errno)))")
    }

    static func forgetSent(on url: URL) {
        removexattr(url.path, sentAttribute, 0)
    }

    /// The send `record(sent:on:)` wrote, or nil when the file has none or it does not decode.
    static func sent(of url: URL) -> Sent? {
        read(sentAttribute, of: url, upTo: sentBytes).flatMap { try? JSONDecoder().decode(Sent.self, from: Data($0.utf8)) }
    }

    /// The most bytes a title's part is read with. A character's bytes have no fixed bound, since
    /// combining marks can stack on one letter, so this is generous and `validated` cuts what it reads.
    private static let titleBytes = 64 * 1024

    private static func write(_ value: String, _ attribute: String, _ what: String, on url: URL) {
        let bytes = Array(value.utf8)
        guard setxattr(url.path, attribute, bytes, bytes.count, 0, 0) != 0 else { return }
        Log.write("[add] warning could not record \(what) on \(url.lastPathComponent): \(String(cString: strerror(errno)))")
    }

    /// The agent that added this file, or nil when none did. One `getxattr`, about 4 µs (measured),
    /// so a card reads it as it is made; it is the folder listing that must not touch every file.
    static func of(_ url: URL) -> String? {
        read(attribute, of: url)
    }

    /// The agent session a file came from, as `record(origin:)` wrote it: the Claude Code session or
    /// Codex thread its push named, or the one whose live ink result it is. A push's session is the
    /// pusher's claim, since `add` has no authenticated sender. Sending to it still goes through the
    /// check that the session is running with the plugin's inbox (`ClaudeCodeConnection.submit`), and
    /// a thread through `codex queue`, which finds the thread in Codex's store or fails.
    static func origin(of url: URL) -> AgentDestination? {
        guard let client = of(url).flatMap({ AgentClient(rawValue: $0.lowercased()) }),
              let id = cleanSession(read(attribute(for: client), of: url)) else { return nil }
        return AgentDestination(id: id, name: client.label, address: AgentAddress(client: client, id: id))
    }

    private static func read(_ attribute: String, of url: URL, upTo limit: Int = maxLength * 4) -> String? {
        var buffer = [UInt8](repeating: 0, count: limit)
        let size = getxattr(url.path, attribute, &buffer, buffer.count, 0, 0)
        guard size >= 0 else { return nil }
        return String(decoding: buffer.prefix(size), as: UTF8.self)
    }

    /// What the badge says: "From vignette" for a card whose sender is known, else "From Claude" for
    /// `agent=claude` and "From an agent" for a push with no name.
    static func label(for name: String, sender: String?) -> String {
        if let sender, !sender.isEmpty { return "From " + sender }
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
        image?.isTemplate = oneColourLogos.contains(key)
        logos[key] = .some(image)
        return image
    }
    @MainActor private static var logos: [String: NSImage?] = [:]

    /// Vendors whose logo is a single black shape. It is a template image, drawn in the colour of the
    /// text beside it, since black would vanish on a dark bar or in a dark menu.
    static let oneColourLogos: Set<String> = ["codex"]

    /// The avatar of `maker` when it is an agent whose logo is one colour: the logo in black on a white
    /// circle, which reads on a light or dark popover and on any picture under a pin's dot, at
    /// `style.oneColourLogoSize` of the circle across. Nil for every other agent, whose avatar is its
    /// logo on its pins' colour.
    static func oneColourAvatar(_ maker: PinMaker, style: PinStyle) -> (fill: SRGB, ink: SRGB, logoSize: CGFloat)? {
        guard case .agent(let name) = maker, oneColourLogos.contains(name.lowercased()) else { return nil }
        return (fill: SRGB(red: 1, green: 1, blue: 1), ink: SRGB(red: 0, green: 0, blue: 0), logoSize: style.oneColourLogoSize)
    }

    /// The glyph for a vendor without a logo: the closest SF Symbol to the robot this wants to be.
    static let fallbackSymbol = "cpu"

    /// Whether the bundle holds a logo for the vendor named `name`, in any case.
    static func hasLogo(_ name: String) -> Bool {
        !name.isEmpty && Bundle.main.url(forResource: name.lowercased(), withExtension: "svg", subdirectory: "agents") != nil
    }

    /// The colour of each vendor's pins, by lower-case name. Claude's is the fill of `claude.svg`.
    /// Codex's logo is one black shape, so its pins are black. A vendor not listed takes `ui.agentColor`.
    static let brandColors: [String: SRGB] = ["claude": SRGB(hex: "#d97757")!, "codex": SRGB(hex: "#000000")!]
}
