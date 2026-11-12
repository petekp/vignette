import Foundation

/// What the bar offers for the open image, and so what Return and Cmd+Return do. Each case has one
/// filled button: the action that takes the drawing furthest.
enum ToolbarOffer: Equatable {
    /// Nothing to send to: Copy alone.
    case copy
    /// No session runs to send to, and some can be started: Copy, then the target with nothing in
    /// it, whose menu lists them. Only a person's pick starts a session, so none is chosen for them.
    case choose
    /// A session to send to: Copy on Return, then the target, and Send on Cmd+Return.
    case send(AgentDestination)
    /// The image names the session it came from: Reply alone, on Return and Cmd+Return.
    case reply(AgentDestination)

    /// A reply goes back where the image came from, unless the whole list has answered without that
    /// Claude Code session: the inboxes list every session running the plugin, so it has closed. Codex's listing holds only the
    /// threads used last, so a Codex thread missing from it may still be there.
    init(replyTo: AgentDestination?, destinations: [AgentDestination], listed: Bool, target: AgentDestination?,
         startable: [AgentDestination] = []) {
        if let replyTo {
            let closed = listed && replyTo.client == .claude && !destinations.contains { $0.id == replyTo.id }
            if !closed {
                self = .reply(destinations.first { $0.id == replyTo.id } ?? replyTo)
                return
            }
        }
        // Only once every client has answered: a session running may be listed a moment after the
        // ones Vignette can start.
        let chooses = listed && !startable.isEmpty
        self = target.map(ToolbarOffer.send) ?? (chooses ? .choose : .copy)
    }

    var isSend: Bool {
        if case .send = self { return true }
        return false
    }

    /// Whether the bar has the target and its menu.
    var offersTarget: Bool { isSend || self == .choose }

    /// Where the drawing goes when the offer's filled button is pressed, or nil for Copy.
    var destination: AgentDestination? {
        switch self {
        case .copy, .choose: return nil
        case .send(let destination), .reply(let destination): return destination
        }
    }

    /// Return never sends to a session Vignette picked, only to the one the image came from.
    var finishes: EditorCore.Finishes {
        switch self {
        case .copy, .choose: return .init(returnKey: .done, commandReturn: .done)
        case .send: return .init(returnKey: .done, commandReturn: .send)
        case .reply: return .init(returnKey: .send, commandReturn: .send)
        }
    }
}
