import Foundation

/// Live ink's words for setup's pages and the Settings window.
enum SetupInkCopy {
    /// What leaves the Mac when you ask, for the agents that can answer.
    static func costNote(claude: Bool, codex: Bool) -> String {
        switch (claude, codex) {
        case (true, true):
            "When you ask, Claude or Codex sees a picture of each window you drew on, with its title and URL. An ask to Claude costs about one to four cents. One to Codex counts toward your ChatGPT plan's usage limit."
        case (false, true):
            "When you ask, Codex sees a picture of each window you drew on, with its title and URL, through your ChatGPT account. An ask counts toward your plan's usage limit."
        default:
            "When you ask, Claude sees a picture of each window you drew on, with its title and URL, through your own Claude Code. An ask costs about one to four cents."
        }
    }

    /// Setup's live ink page, after the line about drawing, when an agent can answer: the one that
    /// will (`ResponderStatus.askLine`).
    static func askLine(agent: AgentClient) -> String {
        "Then ask \(name(agent)) about it, or send it to a Claude Code or Codex session."
    }

    /// Why setup asks for Screen Recording, naming the agent that will answer (`ResponderStatus.namedAgent`).
    static func screenRecordingReason(agent: AgentClient) -> String {
        "So \(name(agent)) can see the window you drew on."
    }

    /// macOS asks to quit and reopen an app it has just let record the screen, since the grant
    /// reaches only a new process.
    static let reopenNote = "Once you allow Screen Recording, macOS asks to quit and reopen \(Identity.name). Setup opens again on this page."

    /// Screen Recording's reason once it is allowed, until macOS's window picker question is answered.
    static let pickerQuestionReason = "macOS has one more question about the screen."

    /// Under the permissions while macOS's window picker question is unanswered.
    static func pickerQuestionNote(agent: AgentClient) -> String {
        "macOS asks this question the first time \(Identity.name) looks at the screen. Allow lets \(name(agent)) see the window you drew on."
    }

    /// Why live ink asks for each permission, in the General tab.
    @MainActor static var liveInkAccessibilityReason: String {
        "Lets Vignette notice \(Settings.shared.data.liveInkChordChoice.glyphs) held down in any app."
    }
    static let liveInkSpeechReason = "Lets Vignette hear what you say while you draw. The words are made on this Mac."
    static let liveInkScreenRecordingReason = "Lets Vignette see the window under your ink when you ask about it. macOS may ask you to reopen Vignette after you allow it."

    /// The one-time offer to an install that finished setup before live ink had a page, naming the
    /// agent that will answer (`ResponderStatus.namedAgent`).
    static func offer(pair: String, agent: AgentClient) -> String {
        "Live ink is new. Holding \(pair) lets you draw over any app and ask \(name(agent)) about what you drew."
    }

    /// What a note calls `agent`.
    private static func name(_ agent: AgentClient) -> String { LiveNotePopover.Responder.able(agent).name }
}
