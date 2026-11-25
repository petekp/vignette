import AppKit

/// A fill of the window colour behind the session menu's rows, inside the menu's own glass, so the
/// windows behind the menu show only as a faint hue. NSMenu has no API for its background or its
/// window, so this reads AppKit's own: the menu's window from its implementation object, and the
/// glass, which macOS 27.2 draws in a child window that shows the menu window's views on the glass.
/// The fill is the back view of the menu window's content view, a view the menu owns, so a window
/// AppKit reuses for another menu does not keep it. When a macOS draws the menu some other way,
/// nothing is added and the menu keeps the system's look.
@MainActor
final class SessionMenuBacking: NSView {
    /// How much of the glass the window colour covers.
    static let opacity: CGFloat = 0.78

    /// Adds a backing to the window AppKit opens for `menu`, unless Reduce Transparency already
    /// makes menus opaque or the window has one, and logs what it found. Call it as the menu opens:
    /// AppKit makes a menu's window only as it presents the menu, so this looks it up on the main
    /// queue's next turn.
    static func install(for menu: NSMenu) {
        guard #available(macOS 26.0, *) else {
            Log.write("[send] session menu backing skipped: no glass before macOS 26")
            return
        }
        DispatchQueue.main.async { [weak menu] in
            guard let menu else { return }
            let window = window(of: menu)
            Log.write("[send] session menu backing \(place(in: window)) window=\(window.map { "\(type(of: $0))" } ?? "none")")
        }
    }

    /// The window AppKit shows `menu` in, from the menu's implementation object, or nil when this
    /// macOS has no such object or the menu has no window.
    private static func window(of menu: NSMenu) -> NSWindow? {
        let implementation = NSSelectorFromString("_menuImpl")
        let window = NSSelectorFromString("window")
        guard menu.responds(to: implementation),
              let impl = menu.perform(implementation)?.takeUnretainedValue() as? NSObject,
              impl.responds(to: window) else { return nil }
        return impl.perform(window)?.takeUnretainedValue() as? NSWindow
    }

    @available(macOS 26.0, *)
    private static func place(in window: NSWindow?) -> String {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency { return "skipped: reduce transparency" }
        guard let window else { return "skipped: no menu window" }
        guard let content = window.contentView else { return "skipped: no views" }
        guard let glass = window.childWindows?.lazy.compactMap({ $0.contentView as? NSGlassEffectView }).first else {
            return "skipped: no glass"
        }
        if content.subviews.contains(where: { $0 is SessionMenuBacking }) { return "kept" }
        let backing = SessionMenuBacking(frame: content.bounds)
        backing.autoresizingMask = [.width, .height]
        backing.layer?.cornerRadius = glass.cornerRadius
        backing.layer?.cornerCurve = .continuous
        content.addSubview(backing, positioned: .below, relativeTo: nil)
        return "added"
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(Self.opacity).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
