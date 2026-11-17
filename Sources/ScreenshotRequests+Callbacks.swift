import Foundation

extension ScreenshotRequests {
    /// What the coordinator needs from the rest of the app. Closures, like ThumbnailController's,
    /// so nothing here reaches into the annotator or the stack.
    struct Callbacks {
        /// Adds marks to a screenshot's drawing and stores it, without showing anything, then answers
        /// nil, or why not. Publication waits for the answer, so a card never appears without its marks.
        /// The name is the agent's, which its notes' badges show. `answersLiveInk` is true for an
        /// answer to live ink, whose marks were laid out on `cardCanvas`.
        var installDrawing: (Screenshot, [AgentMark], _ agent: String?, _ answersLiveInk: Bool,
                             @escaping (Drawings.Failure?) -> Void) -> Void = { _, _, _, _, done in
            done(Drawings.Failure(code: .writeFailed, description: "nothing stores drawings"))
        }
        /// The picture at a URL as `installDrawing` will draw an agent's answer on it, so the answer's
        /// words and labels are measured and placed there; nil leaves them in the corner and under their marks.
        var cardCanvas: (URL, _ agent: String?) -> LiveAnswer.Canvas? = { _, _ in nil }
        /// Shows a published reply's card. Managed replies never reach the watcher's capture path.
        var present: (Screenshot) -> Void = { _ in }
        /// Makes an answer to live ink its result card, from a fresh capture of the window the ink was
        /// on, then answers the indexes of the marks it could not find there, or nil when it could not
        /// capture that window and the reply is published on the request's own picture instead.
        var presentLive: (Record, LiveAnswer, @escaping ([Int]?) -> Void) -> Void = { _, _, done in done(nil) }
        var watchFolder: () -> URL = { FileManager.default.temporaryDirectory }
        /// What the client answered for a request, which the card that was sent shows.
        var delivered: (Record, SubmissionOutcome) -> Void = { _, _ in }
        /// A reply to this request was accepted and could not be made a card, which the card that
        /// was sent shows, since there is no card of the reply's own to show it on. The reason is
        /// what the person can do about it.
        var replyFailed: (Record, String) -> Void = { _, _ in }
        /// A send that waited out its grace is going to its client now. Called on the timer's turn,
        /// before the client is asked, so before `delivered`. Never called for a send with no grace.
        var released: (Record) -> Void = { _ in }
        /// A send that was waiting ended without reaching its client: Don't send, or a clear took
        /// its request.
        var cancelled: (Record) -> Void = { _ in }
        /// Don't send is taking a queued line out of its session's queue. `queueChanged` follows once
        /// the session answered.
        var withdrawing: (Record) -> Void = { _ in }
        /// Whether the request's line waits in its session's queue, or why, changed: the card's tab
        /// reads `queuedSend(of:)` again. A line the session took, a line removed by Don't send or in
        /// the session's own app, a cleared request, and a new reason all come here, and none of them
        /// is a notice.
        var queueChanged: (Record) -> Void = { _ in }
        /// More to say about a send whose answer the card already showed: its thread is gone, or Don't
        /// send found the line started or could not remove it.
        var laterAnswer: (Record, SendNotice.State, _ reason: String) -> Void = { _, _, _ in }
        /// A screenshot's drawing as the editor would open it, so a published reply records what
        /// the agent sent (`Agent.record(sentDrawing:on:)`).
        var storedDrawing: (ScreenshotKey) -> Drawing? = { _ in nil }
    }
}
