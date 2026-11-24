import Foundation

extension AppDelegate {
    /// Where an image was taken, when Vignette saw where (`CaptureOrigin.rect(of:pixels:)`, which
    /// each capture asks once).
    func capturedRect(of shot: Screenshot) -> NSRect? {
        guard shot.kind == .image, case .read(let header) = Thumbnailer.lookUp(shot.url), let pixels = header.pixels else { return nil }
        return captureOrigin?.rect(of: shot.url, pixels: pixels)
    }

    /// What a Stitch's file is named for, which tells it from a capture the person took.
    static let stitchNamePrefix = "Stitch "

    /// Writes `[capture] clues <file> apps=<app:share%,…|none|unlocated> herdr=… focus=… project=…` for
    /// a capture the person took. The apps are read now, from the windows on screen; Herdr's focus
    /// and its session are read off the main thread, and the line is written when they are
    /// (`HerdrFocus.logged`). Only app ids, Herdr's pane and a session's id and repository are
    /// logged, never a window's title or text from the screen.
    func logClues(of shot: Screenshot) {
        guard shot.kind == .image, !shot.url.lastPathComponent.hasPrefix(Self.stitchNamePrefix) else { return }
        let name = shot.url.lastPathComponent
        let apps = CaptureRect.logged(captureOrigin?.owners(of: shot.url))
        let claude = Self.connections[.claude]
        DispatchQueue.global(qos: .utility).async {
            let clue = HerdrFocus.clue(listing: { claude?.destinations() ?? [] })
            Log.write("[capture] clues \(name) apps=\(apps) \(HerdrFocus.logged(clue))")
        }
    }
}
