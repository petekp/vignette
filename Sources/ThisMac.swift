import Foundation

/// Whether the person at this Mac was shown something that settings.json also records. A file copied
/// from another Mac, as dotfiles sync it, carries that record, but nobody here saw it, so it counts only
/// with a record in this Mac's own defaults too. A test launch goes by its scratch file alone.
enum ThisMac {
    static func saw(_ key: String) -> Bool { Launch.isTest || Identity.defaults.bool(forKey: key) }

    static func record(_ key: String) { Identity.defaults.set(true, forKey: key) }
}
