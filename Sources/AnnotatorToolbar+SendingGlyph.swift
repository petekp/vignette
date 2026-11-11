import SwiftUI

/// The send inside Send's button: a paper plane that comes in from the lower left and settles, and
/// carries on up and to the right as the bar leaves. The wait is usually a rendering of about
/// 150 ms, too short for a spinner to read as anything but a flicker; past half a second a spinner
/// takes the plane's place.
struct SendingGlyph: View {
    let leaving: Bool
    @State private var arrived = false
    @State private var slow = false

    var body: some View {
        let motion = Settings.shared.motionScale
        ZStack {
            if slow && !leaving {
                ProgressView().controlSize(.small).environment(\.colorScheme, .dark)
                    .transition(.blurReplace)
            } else {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .offset(x: leaving ? 16 : (arrived ? 0 : -10), y: leaving ? -12 : (arrived ? 0 : 6))
                    .opacity(leaving ? 0 : 1)
                    .transition(.blurReplace)
            }
        }
        .onAppear {
            withAnimation(Anim.spring(0.35 * motion, bounce: 0.3)) { arrived = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(Anim.spring(0.3 * motion)) { slow = true }
            }
        }
    }
}
