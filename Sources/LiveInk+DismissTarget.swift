import CoreGraphics

extension LiveInk {
    /// The reply whose note, or whose × button while it shows, is under `point`. The newest reply is
    /// on top, so it wins where two overlap.
    static func dismissTarget(at point: CGPoint, in asks: LiveAsks, replies: [LiveAsks.Ask.ID: ShownReply],
                              dismissing: LiveAsks.Ask.ID?, buttonFrame: CGRect?) -> (id: LiveAsks.Ask.ID, reply: ShownReply)? {
        for ask in asks.asks.reversed() {
            guard asks.offersDismiss(ask.id), let reply = replies[ask.id] else { continue }
            let onNote = reply.note.insetBy(dx: -10, dy: -10).contains(point)
            let onButton = dismissing == ask.id && buttonFrame?.insetBy(dx: -6, dy: -6).contains(point) == true
            if onNote || onButton { return (ask.id, reply) }
        }
        return nil
    }
}
