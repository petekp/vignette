import Foundation

extension LiveInk {
    static let screenRecordingNotice = "Live ink needs Screen Recording to see the window under your ink. You can allow it in System Settings."
    static let speechNotice = "Speaking needs the microphone and speech recognition. You can allow them in System Settings."

    /// `reply` with `notice` in its row, grown to fit it.
    func noticed(_ reply: Mark, _ notice: String) -> Mark {
        guard case .text(let text) = reply.geometry else { return reply }
        var reply = reply
        reply.notice = notice
        return LiveAnswerLayout.grown(reply, to: text.text, sizes: answerSizes, foot: reply.popover?.foot ?? .zero)
    }
}
