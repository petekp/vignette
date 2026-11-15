import AppKit

extension AppDelegate {
    @objc func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        ShortcutHints.highlight(item, in: menu)
    }
}
