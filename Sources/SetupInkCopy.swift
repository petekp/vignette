import Foundation

/// Live ink's words for setup's pages and the Settings window.
enum SetupInkCopy {
    static let costNote = "When you ask, Claude sees a picture of the window, its title and URL, through your own Claude Code. An ask costs about one to four cents."
    /// macOS asks to quit and reopen an app it has just let record the screen, since the grant
    /// reaches only a new process.
    static let reopenNote = "Once you allow Screen Recording, macOS asks to quit and reopen \(Identity.name). Setup opens again on this page."

    /// The one-time offer to an install that finished setup before live ink had a page.
    static func offer(pair: String) -> String {
        "Live ink is new. Holding \(pair) lets you draw over any app and ask Claude about what you drew."
    }
}
