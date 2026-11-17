import Foundation

/// How Vignette reaches one agent session. The terminal a session happens to be displayed in is
/// not part of this: a destination is a conversation, and a connection is the native call that
/// puts a request into it. See docs/glossary.md for the words.
///
/// Two routes exist. Codex is addressed by its thread UUID alone, and the engine that owns the
/// thread refuses a UUID it does not have. Claude Code is addressed by its session id, through the
/// plugin's inboxes, and nothing on that route refuses a stale id, so Vignette checks that an inbox
/// still holds that exact session immediately before it writes. `AgentAddress.guardTier` is the
/// difference, and it is recorded on every request.
enum AgentClient: String, Codable, CaseIterable {
    case claude, codex

    /// What a person calls it. `rawValue` is also the `agent=` name a reply's card is badged with.
    var label: String { self == .claude ? "Claude Code" : "Codex" }
}

/// How strongly a destination's conversation is pinned at the moment of delivery.
enum AddressGuard: String, Codable {
    /// The receiving runtime resolves the conversation itself and fails when it is gone.
    case runtimeEnforced = "runtime-enforced"
    /// Vignette checks the conversation just before submitting. The window between the check and
    /// the submission is small but real, and it belongs to the person's own terminal.
    case preflight
}

/// The native identity of a destination, as its client understands it.
enum AgentAddress: Equatable, Codable {
    /// A Claude Code session id. The plugin's inboxes resolve it to the process running it at send time.
    case claudeSession(String)
    /// A Codex thread. `codex queue --thread` finds the engine that owns it, so there is nothing
    /// else to say: the UUID is the whole address.
    case codexThread(uuid: String)

    init(client: AgentClient, id: String) {
        switch client {
        case .claude: self = .claudeSession(id)
        case .codex: self = .codexThread(uuid: id)
        }
    }

    var client: AgentClient {
        switch self {
        case .claudeSession: return .claude
        case .codexThread: return .codex
        }
    }

    /// The session id or thread UUID.
    var id: String {
        switch self {
        case .claudeSession(let id): return id
        case .codexThread(let uuid): return uuid
        }
    }

    var guardTier: AddressGuard {
        switch self {
        case .claudeSession: return .preflight
        case .codexThread: return .runtimeEnforced
        }
    }

    /// How the address reads in `[state]` and in a request record's log line.
    var description: String {
        switch self {
        case .claudeSession(let id): return "claude session=\(id)"
        case .codexThread(let uuid): return "codex thread=\(uuid)"
        }
    }
}

/// One agent session a request may be addressed to.
struct AgentDestination: Equatable, Identifiable {
    /// Vignette's stable handle for it: the thread UUID for Codex, the session id for Claude
    /// Code. It is what a request records, so a reply's card can offer the conversation it came
    /// from.
    let id: String
    let name: String
    /// The project folder the session works in, shown beside its name.
    var detail: String = ""
    let address: AgentAddress
    /// When the session was last used, which is the order Send lists sessions in. Nil when its
    /// client could not say.
    var lastUsed: Date? = nil
    /// Why Send starts on this session, when it does for a reason other than its last use: the kept
    /// pick, its agent's own app in front, or herdr's focus on its pane or beside it. Set only by
    /// `DestinationChoice` on the list it answers. Nil for every other session.
    var focus: Focus? = nil
    /// Where the session works: its repository, or else its folder. Filled by the client's listing.
    var place: Place = .none
    /// The checked-out branch when it is not the repository's default. Nil on the default branch,
    /// on a detached `HEAD`, and when it could not be read.
    var branch: String? = nil
    /// The name of the Herdr tab the session runs in.
    var hostLabel: String? = nil
    /// Its terminal's `fleet.role` (`HerdrFocus.loggedRole`).
    var role: String? = nil
    /// When the session started, which numbers sessions with equal names.
    var started: Date? = nil
    /// Where the session is in its turns. Nil when its client does not report turns.
    var turn: SessionTurn? = nil
    /// The process whose Claude Code inbox held the session when it was listed, which names the
    /// inbox's folder. Nil for a Codex thread and for a session not listed from an inbox.
    var inbox: Int32? = nil
    /// The goal the inbox mod wrote for the session.
    var goal: String? = nil
    /// Whether `name` is the session's own (its custom or AI title) rather than a stand-in.
    var hasOwnName = true
    /// When a drawing was last handed to this session, from the request records. Stamped by
    /// `SessionListing`; it orders the session menu.
    var lastSent: Date? = nil
    /// The folder a Claude Code session runs in, as its inbox says (`pwd -P`). Nil for a Codex thread.
    var folder: String? = nil
    /// How Vignette starts the session when a person sends to it: set on a Claude Code project's
    /// Continue last session and New session rows, which are not running (`StartableSessions`).
    /// Nil for a session that is running and can receive now.
    var start: SessionStart? = nil

    var client: AgentClient { address.client }
    /// Its project folder's name, or the client's name when it has none.
    var project: String { detail.isEmpty ? client.label : detail }

    /// Whether this session is known to be in use, which is what Send's menu lists. A Claude Code
    /// session is listed only while the Vignette plugin's monitor runs in it. Nothing says which threads the Codex
    /// app has open, so a Codex thread counts when it was used in the last day: on 2026-09-25, 2 of
    /// the 15 threads listed had been, and the rest were 33 hours to 17 days old.
    func isActive(now: Date = Date()) -> Bool {
        switch address {
        case .claudeSession: return true
        case .codexThread: return lastUsed.map { now.timeIntervalSince($0) < Self.activeWindow } ?? false
        }
    }

    static let activeWindow: TimeInterval = 24 * 60 * 60
}
