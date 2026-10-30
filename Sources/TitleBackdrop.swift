import ScreenCaptureKit

/// The screen behind an agent's title, for its ink. Needs Screen Recording, which the caller checks
/// first: asked without it, ScreenCaptureKit raises macOS's prompt.
enum TitleBackdrop {
    /// The brightness, sRGB encoded from 0 to 1, of each `cell`-wide part of the screen under `rect`,
    /// in global top-left points, with Vignette's own windows left out, so the dim is not in it. Nil
    /// when the screen could not be read.
    static func brightness(in rect: CGRect, cell: CGFloat) async -> [Double]? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.frame.intersects(rect) }) else { return nil }
        let part = rect.intersection(display.frame)
        guard !part.isNull, part.width >= 1, part.height >= 1 else { return nil }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = part.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        // A pixel every two points, as live ink reads the screen.
        configuration.width = max(1, Int(part.width / 2))
        configuration.height = max(1, Int(part.height / 2))
        configuration.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration),
              let luminance = LivePacket.Luminance(image, frame: part, columns: max(1, Int(part.width / cell))) else { return nil }
        return luminance.cells.map { Double($0) / 255 }
    }
}
