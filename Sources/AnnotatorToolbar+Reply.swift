import Foundation

extension AnnotatorToolbar.Model {
    /// Reply on the agent's own image would send nothing new: no message, and the drawing as the agent
    /// sent it. Reply is unavailable then, and Return copies and closes as Done does
    /// (`AppDelegate.sendDrawing`).
    var nothingToReply: Bool {
        guard case .reply = offer else { return false }
        return drawingAsSent && sentMessage == nil
    }

    static let nothingToReplyTip = "Add a message or draw to reply"
}
