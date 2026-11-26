import AppKit

/// What Vignette keeps about a card an agent pointed the person at (`vignette://show`): the agent,
/// the session that asked and its name, its message and when. It lives in `StackModel` beside the card, in memory
/// only, and ends when the card leaves the column, opens in the annotator or is shown again.
struct Shown: Equatable {
    /// `agent=` as `Agent.clean` read it: "" for an agent with no name.
    let agent: String
    let session: AgentAddress?
    let message: String?
    let at: Date
    /// The session's name: `from=`, else what the session list answers, which can come after the
    /// card is up (`ThumbnailController.named`). Nil until then, and for a session with no name.
    var sender: String? = nil

    /// The notice's first line, the words an agent's tab uses: "From vignette", else "From Claude".
    var headline: String { Agent.label(for: agent, sender: sender) }

    /// The most a message keeps: the length of a notice's second line (`docs/voice.md`).
    static let messageLimit = 60

    /// `text` trimmed and cut at a word to `messageLimit` characters, and whether it was cut. Nil
    /// for a message with nothing in it.
    static func message(_ text: String?) -> (text: String?, cut: Bool) {
        let words = (text ?? "").split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return (nil, false) }
        guard words.count > messageLimit else { return (words, false) }
        let head = words.prefix(messageLimit)
        let atWord = head.lastIndex(of: " ").map { head[..<$0] } ?? head
        return (atWord.trimmingCharacters(in: .whitespaces) + "…", true)
    }

    /// What the person's hand is doing in the corner, which a `show` waits for.
    enum Wait: String { case press, drag, sweep, swipe, stitch, slideOut = "slide-out" }

    /// The words VoiceOver says once for a call: "vignette showed you 3 screenshots", else "Claude
    /// showed you 3 screenshots".
    static func announcement(agent: String, sender: String?, count: Int) -> String {
        let who = sender ?? (agent.isEmpty ? "An agent" : agent.prefix(1).uppercased() + agent.dropFirst())
        return "\(who) showed you \(count == 1 ? "a screenshot" : "\(count) screenshots")"
    }
}

/// An agent's marks that `show` brought, drawn on top of a screenshot in the agent's colour and
/// apart from the person's drawing, until the person keeps them or clears them. The file and its
/// drawing are untouched until Keep, which joins them to the drawing as one undo step. In memory only.
@MainActor
final class PendingMarks {
    struct Entry {
        /// Tells these marks from others the same agent or another put on the same screenshot later.
        let id = UUID()
        let agent: String
        /// The session that showed them, and its name as `Shown.sender` has it.
        let session: AgentAddress?
        var sender: String?
        /// As `marks=` gave them, for Keep, which adds them as `add` does.
        let marks: [AgentMark]
        /// The same marks in px on the screenshot, and the new pins numbered as they would be now, in a
        /// drawing of their own, for drawing on top.
        let drawing: Drawing
        /// As `pins=` gave them, for Keep, which numbers the new pins then and adds the answers.
        var pins: [AgentPin] = []
        /// When `show` brought them, the time their comments keep.
        var at = Date()

        /// Keep's additions to the drawing, as `add` takes them.
        var additions: AgentAdditions { AgentAdditions(marks: marks, pins: pins, agent: agent, at: at) }
    }

    private(set) var entries: [ScreenshotKey: Entry] = [:]
    /// Called after each change, with the file it was on.
    var changed: (ScreenshotKey) -> Void = { _ in }

    subscript(key: ScreenshotKey) -> Entry? { entries[key] }

    func set(_ entry: Entry?, on key: ScreenshotKey) {
        entries[key] = entry
        changed(key)
    }

    /// The session list named `session`: the marks it showed that have no name yet say whose they are.
    func name(_ sender: String, of session: AgentAddress) {
        for (key, entry) in entries where entry.session == session && entry.sender == nil {
            var named = entry
            named.sender = sender
            set(named, on: key)
        }
    }

    func rename(from old: ScreenshotKey, to new: ScreenshotKey) {
        guard let entry = entries.removeValue(forKey: old) else { return }
        entries[new] = entry
        changed(old)
        changed(new)
    }
}

/// The `show` calls waiting for the person's hand to leave the corner, first in, first out.
struct ShowQueue<Call> {
    private(set) var waiting: [Call] = []

    var isEmpty: Bool { waiting.isEmpty }

    mutating func add(_ call: Call) { waiting.append(call) }

    /// Changes every waiting call in place.
    mutating func update(_ change: (inout Call) -> Void) {
        for index in waiting.indices { change(&waiting[index]) }
    }

    /// The calls to run now, in the order they came: every one while the corner is free, none while
    /// `busy` names what the hand is doing.
    mutating func take(busy: Shown.Wait?) -> [Call] {
        guard busy == nil else { return [] }
        defer { waiting = [] }
        return waiting
    }
}
