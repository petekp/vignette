import AppKit

/// What Vignette keeps about a card an agent pointed the person at (`vignette://show`): the agent,
/// the session that asked, its message and when. It lives in `StackModel` beside the card, in memory
/// only, and ends when the card leaves the column, opens in the annotator or is shown again.
struct Shown: Equatable {
    /// `agent=` as `Agent.clean` read it: "" for an agent with no name.
    let agent: String
    let session: AgentAddress?
    let message: String?
    let at: Date

    /// The notice's first line, the words an agent's tab uses: "From Claude".
    var headline: String { Agent.label(for: agent) }

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

    /// The words VoiceOver says once for a call: "Claude showed you 3 screenshots".
    static func announcement(agent: String, count: Int) -> String {
        let who = agent.isEmpty ? "An agent" : agent.prefix(1).uppercased() + agent.dropFirst()
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
        /// As `marks=` gave them, for Keep, which adds them as `add` does.
        let marks: [AgentMark]
        /// The same marks in px on the screenshot, in a drawing of their own, for drawing on top.
        let drawing: Drawing
    }

    private(set) var entries: [ScreenshotKey: Entry] = [:]
    /// Called after each change, with the file it was on.
    var changed: (ScreenshotKey) -> Void = { _ in }

    subscript(key: ScreenshotKey) -> Entry? { entries[key] }

    func set(_ entry: Entry?, on key: ScreenshotKey) {
        entries[key] = entry
        changed(key)
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

    /// The calls to run now, in the order they came: every one while the corner is free, none while
    /// `busy` names what the hand is doing.
    mutating func take(busy: Shown.Wait?) -> [Call] {
        guard busy == nil else { return [] }
        defer { waiting = [] }
        return waiting
    }
}
