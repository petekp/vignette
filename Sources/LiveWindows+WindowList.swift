import CoreGraphics
import Foundation

/// The window list, read the cheap way: a description of the listed windows only, and the ids of the
/// windows above one, which `CGWindowListCreate` gives without describing them.
enum WindowList {
    private typealias Create = @convention(c) (UInt32, UInt32) -> Unmanaged<CFArray>?
    /// Swift marks `CGWindowListCreate` unavailable, so it is looked up.
    private static let create: Create? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreate")
        .map { unsafeBitCast($0, to: Create.self) }

    /// The windows above `id`, front to back, as the window server lists them.
    static func ids(above id: CGWindowID) -> [CGWindowID] {
        guard let array = create?(CGWindowListOption.optionOnScreenAboveWindow.rawValue, id)?.takeRetainedValue() else { return [] }
        return (0..<CFArrayGetCount(array)).map { CGWindowID(UInt(bitPattern: CFArrayGetValueAtIndex(array, $0))) }
    }

    /// The window list's entries for `ids`. The array holds the ids themselves, not numbers.
    static func describe(_ ids: [CGWindowID]) -> [[String: Any]] {
        guard !ids.isEmpty else { return [] }
        var values = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let array = CFArrayCreate(nil, &values, values.count, nil) else { return [] }
        return CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] ?? []
    }

    static func bounds(_ info: [String: Any]) -> CGRect? {
        (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
    }

    /// The app's frontmost window on the screen, past the small one macOS 15 puts over a titled
    /// window's title bar.
    static func front(of pid: pid_t) -> CGWindowID? {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let front = infos.first {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
                && (bounds($0).map { $0.width > 60 && $0.height > 60 } ?? false)
        }
        return front?[kCGWindowNumber as String] as? CGWindowID
    }
}
