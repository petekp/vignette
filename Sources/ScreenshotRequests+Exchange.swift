import Foundation

extension ScreenshotRequests {
    /// The session a reply card's request went to, and when Vignette accepted the reply: one of the
    /// screenshot's exchanges (`CommentTarget.last`).
    func replyExchange(of url: URL) -> CommentTarget.Exchange? {
        guard let origin = replyOrigin(of: url) else { return nil }
        let url = url.standardizedFileURL
        let reply = replies.values.filter { $0.stage == .published && $0.publishedURL == url }.max { ($0.accepted ?? .distantPast) < ($1.accepted ?? .distantPast) }
        return CommentTarget.Exchange(session: origin.address, at: reply?.accepted)
    }
}
