import AppKit
import SwiftUI

/// Views found by name, asked where they are on the screen, for something drawn over them, such as
/// setup's ink. Unlike an anchor, it reaches out of a `Form`'s rows, which are hosted views of their own.
@MainActor
final class ScreenSpots {
    private var views: [String: () -> NSView?] = [:]

    func register(_ name: String, _ view: NSView) { views[name] = { [weak view] in view } }

    /// Where `name` is, in global top-left points, while it is on the screen.
    func global(_ name: String) -> CGRect? {
        guard let view = views[name]?(), let window = view.window, view.bounds.width > 0 else { return nil }
        return StateReport.flipped(window.convertToScreen(view.convert(view.bounds, to: nil)))
    }
}

private struct ScreenSpot: NSViewRepresentable {
    let name: String
    let spots: ScreenSpots

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        spots.register(name, view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// Names this view for `spots`.
    func screenSpot(_ name: String, in spots: ScreenSpots?) -> some View {
        background { if let spots { ScreenSpot(name: name, spots: spots) } }
    }
}
