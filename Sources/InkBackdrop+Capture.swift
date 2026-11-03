import ScreenCaptureKit

extension InkBackdrop {
    /// Each display behind the ink, drawn down to its map's cells. Vignette's own windows are left
    /// out, so the ink and its glow never brighten their own map.
    nonisolated static func capture() async -> [(frame: CGRect, luminance: LivePacket.Luminance)] {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return [] }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var maps: [(frame: CGRect, luminance: LivePacket.Luminance)] = []
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            // A pixel every two points gives each cell sixteen to take its mean from.
            configuration.width = max(1, Int(display.frame.width / 2))
            configuration.height = max(1, Int(display.frame.height / 2))
            configuration.showsCursor = false
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration),
                  let luminance = LivePacket.Luminance(image, frame: display.frame, columns: max(1, Int(display.frame.width / cell))) else { continue }
            maps.append((display.frame, luminance))
        }
        return maps
    }
}
