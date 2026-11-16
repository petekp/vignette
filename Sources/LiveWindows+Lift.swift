import QuartzCore

extension LiveWindows {
    /// A window's overlay floated over normal windows, and why.
    struct Lift: Equatable {
        enum Cause: Equatable {
            /// Its app came forward, and raises its windows over every other app's.
            case activating
            /// Its app, already frontmost, is getting the keys back from Vignette (`FocusReturn`).
            /// macOS says nothing of it, and Dia brings its window to the front about 20 ms later,
            /// over the overlay (docs/dia-flicker-2026-11-15.md).
            case keysBack
        }

        let cause: Cause
        let since: CFTimeInterval

        /// How long an app is given to bring its windows forward.
        static let limit: CFTimeInterval = 0.5
        /// Over every app's normal windows, and under the dim and Vignette's floating windows, as the
        /// screen's overlay rests. The popovers hung from the overlay take its level.
        static let level = LiveInkOverlay.restingLevel

        /// Whether the overlay goes back down, just above its window: once no other app's window
        /// overlaps it from above, after its app came forward; as soon as one does, while its app
        /// takes the keys back; and after `limit` either way.
        func ends(coveredByAnotherApp covered: Bool, at now: CFTimeInterval) -> Bool {
            if now - since > Self.limit { return true }
            switch cause {
            case .activating: return !covered
            case .keysBack: return covered
            }
        }
    }
}
