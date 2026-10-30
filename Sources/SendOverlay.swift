import SwiftUI

/// The Copied notice's counterpart for a send: the destination's logo, a badge on it for the
/// delivery, and the session it went to. On a card too narrow for the words the session's title
/// stands alone, cut when it is too long for that too.
/// A delivery usually answers about as the card lands, so the sending state, once on screen, holds
/// `sendingHold` before it gives way: two steps rather than one state flickering into the next.
/// While the send waits out its grace the logo wears a ring that empties, and a Don't send button
/// is the one part of the overlay that takes presses.
///
/// The logo is one view in every state, so when the grace ends it glides to its new place rather
/// than being replaced by a copy drawn there. Its badge comes in once it has arrived.
struct SendOverlay: View {
    let notice: SendNotice
    let corner: CGFloat
    let onUnsend: () -> Void
    let onOverControl: (Bool) -> Void
    @State private var landed = false
    @State private var shown: SendNotice.State?
    @State private var since = Date()
    /// The logo is where the layout puts it, so its badge may show.
    @State private var logoArrived = true
    private static let sendingHold: TimeInterval = 0.45
    /// The logo over the smallest Don't send. A card shorter than this puts the button beside it.
    private static let stackedHeight: CGFloat = 57
    /// The narrowest a cut headline is shown at: a few letters either side of the ellipsis.
    private static let shortestCut: CGFloat = 40

    private var state: SendNotice.State { shown ?? notice.state }

    private var words: String {
        switch state {
        case .inGrace: return "Sending to \(notice.sessionTitle)"
        case .sending: return notice.starts ? "Starting in \(notice.sessionTitle)" : "Sending to \(notice.sessionTitle)"
        case .sent: return "Sent to \(notice.sessionTitle)"
        case .queued: return "Queued for \(notice.sessionTitle)"
        case .uncertain: return "Check \(notice.sessionTitle)"
        case .failed: return "Not sent"
        case .replyFailed: return "Reply not shown"
        case .done: return "Done in \(notice.sessionTitle)"
        }
    }

    private var namesSession: Bool { state != .failed && state != .replyFailed }

    var body: some View {
        let motion = Settings.shared.motionScale
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.black.opacity(0.55))
                .allowsHitTesting(false)
            GeometryReader { geometry in
                let stacked = geometry.size.height >= Self.stackedHeight
                let layout = stacked ? AnyLayout(VStackLayout(spacing: 5)) : AnyLayout(HStackLayout(spacing: 6))
                layout {
                    logo
                    details(stacked: stacked)
                }
                .padding(.horizontal, 8)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .scaleEffect(landed ? 1 : 0.3)
            .opacity(landed ? 1 : 0)
            .allowsHitTesting(landed)
        }
        .onAppear {
            shown = notice.state
            since = Date()
            withAnimation(Anim.spring(0.4 * motion, bounce: 0.45)) { landed = true }
        }
        .onChange(of: notice.state) { previous, next in
            let spring = Anim.spring(0.35 * motion, bounce: 0.35)
            // The logo has arrived when its spring first reaches the new place.
            let glide = Anim.passesTarget(0.35 * motion, bounce: 0.35)
            var wait = shown == .sending ? max(0, Self.sendingHold - Date().timeIntervalSince(since)) : 0
            var last = shown ?? previous
            for step in SendNotice.steps(from: previous, to: next) {
                let leavesGrace = last == .inGrace && step != .inGrace
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                    // The grace is not the sending state: the hold counts from when the badge shows.
                    if step == .sending { since = Date().addingTimeInterval(leavesGrace ? glide : 0) }
                    withAnimation(spring) {
                        shown = step
                        if leavesGrace { logoArrived = false }
                    }
                    if leavesGrace {
                        DispatchQueue.main.asyncAfter(deadline: .now() + glide) {
                            withAnimation(Anim.spring(0.3 * motion, bounce: 0.45)) { logoArrived = true }
                        }
                    }
                }
                wait += (leavesGrace ? glide : 0) + Self.sendingHold
                last = step
            }
        }
    }

    /// What goes with the logo. While the send waits: the words, then Don't send, giving up the
    /// words, then the button's label, before the button, so a send in its grace can always be
    /// cancelled. After: the words, with a failure's reason under them while the card has room.
    @ViewBuilder
    private func details(stacked: Bool) -> some View {
        if state == .inGrace {
            Group {
                if stacked {
                    let unsend = ViewThatFits(in: .horizontal) {
                        unsendButton
                        unsendMark
                    }
                    ViewThatFits(in: .vertical) {
                        VStack(spacing: 5) {
                            headline.allowsHitTesting(false)
                            unsend
                        }
                        unsend
                    }
                } else {
                    unsendMark
                }
            }
            .transition(.opacity)
        } else {
            Group {
                if stacked {
                    ViewThatFits(in: .vertical) {
                        if let reason = notice.reason, state != .sending && state != .sent {
                            VStack(spacing: 3) {
                                headline
                                Text(reason).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                                    .multilineTextAlignment(.center).lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        headline
                        Color.clear.frame(width: 1, height: 1)
                    }
                } else {
                    headline
                }
            }
            .id(words)
            .transition(.blurReplace)
            .allowsHitTesting(false)
        }
    }

    private var unsendButton: some View {
        Button(action: onUnsend) {
            Text("Don't send").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.18)))
                .fixedSize()
        }
        .buttonStyle(TactileButtonStyle(shape: .capsule))
        .onHover(perform: onOverControl)
    }

    private var unsendMark: some View {
        Button(action: onUnsend) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.18)))
        }
        .buttonStyle(TactileButtonStyle(shape: .circle))
        .accessibilityLabel("Don't send")
        .onHover(perform: onOverControl)
    }

    /// The words; on a card too narrow for them, the session's title alone; then the title cut in
    /// the middle, as the toolbar's target cuts it, so a suffix that tells two sessions apart stays.
    /// A failure names no session, so its words are what is cut. Nothing on a card too narrow for
    /// even that.
    private var headline: some View {
        let shortest = namesSession ? notice.sessionTitle : words
        return ViewThatFits(in: .horizontal) {
            label(words).fixedSize()
            if namesSession { label(notice.sessionTitle).fixedSize() }
            label(shortest).truncationMode(.middle).frame(idealWidth: Self.shortestCut)
            Color.clear.frame(width: 1, height: 1)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
    }

    /// The agent's logo on a white disc, as on a card an agent sent: in its grace with the ring that
    /// empties, after it with the delivery at its corner.
    private var logo: some View {
        logoDisc
            .overlay {
                if state == .inGrace, let grace = notice.grace {
                    GraceRing(grace: grace).padding(-4).transition(.opacity)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if state != .inGrace, logoArrived {
                    badge.offset(x: 5, y: 4).transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .allowsHitTesting(false)
    }

    private var logoDisc: some View {
        ZStack {
            Circle().fill(.white).frame(width: 30, height: 30)
            if let image = Agent.logo(for: notice.client.rawValue) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: Agent.fallbackSymbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.black.opacity(0.8))
            }
        }
    }

    /// The dark disc the spinner turns on, and the coin after it.
    private var disc: some View { Circle().fill(Color(white: 0.18)).frame(width: 15, height: 15) }

    /// On a white ring, which parts it from the disc it sits on. The spinner is always there under
    /// what the delivery came to, and goes once that has covered it: removed instead, as the
    /// delivery's badge came in, it was gone in one frame and the ring showed white until the next
    /// one had grown over it.
    private var badge: some View {
        ZStack {
            Circle().fill(.white).frame(width: 18, height: 18)
            ZStack {
                disc
                ProgressView().controlSize(.mini).environment(\.colorScheme, .dark).scaleEffect(0.8)
            }
            .modifier(LeavesWhenCovered(shown: state == .sending ? 1 : 0))
            if let outcome = BadgeOutcome(state) {
                Group {
                    switch outcome {
                    case .check:
                        // The coin covers the badge only face on. Its own disc keeps the spinner,
                        // which leaves under it on a bouncing spring, out of sight while it turns.
                        ZStack {
                            disc
                            CheckCoin(diameter: 15)
                        }
                    case .clock:
                        // One layer, its hands cut out, so they show the white ring beneath.
                        Image(systemName: "clock.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.orange)
                    case .warning(let colour):
                        Image(systemName: "exclamationmark.circle.fill").font(.system(size: 15, weight: .bold))
                            .symbolRenderingMode(.palette).foregroundStyle(.white, colour)
                    }
                }
                .id(outcome)
                // States only move on, so a later outcome draws over the one it replaces.
                .zIndex(outcome.rank)
                .transition(.asymmetric(insertion: .scale(scale: 0.3).combined(with: .opacity),
                                        removal: .modifier(active: LeavesWhenCovered(shown: 0), identity: LeavesWhenCovered(shown: 1))))
            }
        }
    }
}

/// What a delivery's badge shows once it answered. Sent and Done are both the check, so the check
/// stays put when a sent note's turn ends.
private enum BadgeOutcome: Hashable {
    case check, clock, warning(Color)

    init?(_ state: SendNotice.State) {
        switch state {
        case .inGrace, .sending: return nil
        case .sent, .done: self = .check
        case .queued: self = .clock
        case .uncertain: self = .warning(.orange)
        case .failed, .replyFailed: self = .warning(.red)
        }
    }

    var rank: Double {
        switch self {
        case .check, .clock: return 0
        case .warning: return 1
        }
    }
}

/// A badge going stays opaque until its spring first reaches the end, which is when the badge
/// coming in on the same spring has reached its full size and opacity over it.
private struct LeavesWhenCovered: ViewModifier, Animatable {
    var shown: Double
    var animatableData: Double {
        get { shown }
        set { shown = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(shown > 0 ? 1 : 0)
    }
}

/// A ring round the logo that empties as a send's grace runs out. It is drawn from the clock, linearly,
/// to the absolute deadline: the motion scale does not shorten it, and a card shown late, or a
/// second send of the same file, starts at what is left.
private struct GraceRing: View {
    let grace: SendNotice.Grace

    var body: some View {
        TimelineView(.animation) { _ in
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 2.5)
                Circle().trim(from: 0, to: grace.remaining(at: ProcessInfo.processInfo.systemUptime))
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}
