import AppKit

/// Borderless windows refuse key status by default; the editor needs it for typing and shortcuts.
final class AnnotationWindow: NSWindow {
    /// Above the stack's backdrop blur (19) and the Dock (20), so the blur never paints over the
    /// image, and under the stack and the flight layer (`.statusBar`, 25), so a flight image still
    /// covers this window and the stack draws over its shadow. The toolbar shares it.
    static let level = NSWindow.Level(rawValue: 21)
    var onCloseRequest: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { onCloseRequest?() }
    /// Esc reaches the window only when no view took it, which means the editor was not the first
    /// responder. It still closes, as Esc does from the editor, and says what held the keys.
    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else { return super.keyDown(with: event) }
        Log.write("[annotate] esc reached the window firstResponder=\(firstResponder.map { String(describing: type(of: $0)) } ?? "none")")
        onCloseRequest?()
    }
}
