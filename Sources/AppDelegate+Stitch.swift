import AppKit

// MARK: Stitch

extension AppDelegate {
    /// Each piece carries its drawing as it is now into the stitch: its marks drawn into the picture,
    /// and its pins made the stitch's own (`Stitch.Composition.pins`).
    func stitch(_ shots: [Screenshot]) {
        guard shots.count >= 2 else { Commands.error("stitch", .notEnoughFiles, "needs 2, got \(shots.count)"); return }
        let ui = settings.data.ui, style = ui.textStyle, markStyle = ui.markStyle, limit = ui.stitchLongSide
        let pieces = shots.map { Stitch.Piece(url: $0.url, drawing: drawings.current(of: $0.key, style: style)) }
        DispatchQueue.global(qos: .userInitiated).async {
            let composed = Stitch.compose(pieces, style: style, markStyle: markStyle, longSideLimit: limit)
            DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in self?.finishStitch(shots, pieces, composed) } }
        }
    }

    private func finishStitch(_ shots: [Screenshot], _ pieces: [Stitch.Piece], _ composed: Stitch.Composition?) {
        guard let composed else {
            Commands.error("stitch", .unreadableImage, shots.map(\.url.lastPathComponent).joined(separator: ", ")); return
        }
        if let refusal = Stitch.refusal(pieces, composed), let shot = shots.first(where: { $0.url == refusal.piece }) {
            Commands.error("stitch", composed.unread.isEmpty ? .writeFailed : .unreadableImage, "\(shot.url.lastPathComponent): \(refusal.reason)")
            return thumbnail.showNotCopied(shot, reason: refusal.reason)
        }
        // A file that would not decode is not in the picture, and one image is not a stitch.
        guard composed.pieces >= 2 else {
            Commands.error("stitch", .unreadableImage, "only \(composed.pieces) of \(shots.count) images could be read"); return
        }
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let key: ScreenshotKey, name = "\(Self.stitchNamePrefix)\(stamp.string(from: Date())).png"
        do { key = try folderWrites.writeStitch(composed.png, in: watchFolder, as: name) } catch { Commands.error("stitch", .writeFailed, "\(name): \(error.localizedDescription)"); return }
        // The drawing is written before the card appears, so the card shows the pins from the start.
        let shot = Screenshot(key: key)
        var copied: PendingRendering?, saved = true
        let drawing = stitchDrawing(composed, of: key)
        if let drawing, !drawing.pins.isEmpty {
            saved = drawings.write(drawing, reason: "stitched")
            if !saved {
                Log.write("[stitch] error \(CommandError.writeFailed.rawValue) \(key.name): its drawing was not written; the copy holds its pins")
            }
            copied = copyRendering(of: drawing, shot: shot, verb: "stitched", in: nil)
        } else {
            // Without pins only the piece numbers' places are lost, which a pin added later avoids.
            if let drawing, !drawings.write(drawing, reason: "stitched") {
                Log.write("[stitch] warning \(key.name): where its pieces wear their numbers was not written")
            }
            Clipboard.copyFiles([key.url])
        }
        // readerScale is what a vision model's resize leaves of the composition; see Stitch.swift.
        Commands.ok("stitch", "\(key.url.path) from \(composed.pieces) images, \(Int(composed.size.width))x\(Int(composed.size.height)) columns=\(composed.columns) readerScale=\(String(format: "%.2f", composed.readerScale)) \(composed.png.count) bytes pins=\(composed.pins.count), copied")
        // The cards conjoin into the new one when the stack is showing them; otherwise the new card
        // comes up with the Copied notice. Either way Copied waits for a rendering of the pins. A
        // drawing that was not written says Not saved instead, since its pins are only on the clipboard.
        let withoutCopied = PendingRendering()
        withoutCopied.finish(png: nil, failure: .writeFailed("\(key.name): its drawing was not written"))
        let notice = saved ? copied : withoutCopied
        if !conjoin(shots, into: key, copied: notice) { thumbnail.showCopied([shot], after: notice) }
        if !saved { thumbnail.showNotSaved(shot) }
    }

    /// The stitch's drawing: its pieces' pins and where the pieces wear their numbers, sized as an
    /// agent's new drawing is, so a pin added later matches a mark added later. Nil with no pins and
    /// no piece numbers.
    private func stitchDrawing(_ composed: Stitch.Composition, of key: ScreenshotKey) -> Drawing? {
        guard !composed.pins.isEmpty || !composed.badges.isEmpty else { return nil }
        let pixels = PixelSize(width: Int(composed.size.width), height: Int(composed.size.height))
        var drawing = Drawing(key: key.path, pixels: pixels, sizedFor: Self.newDrawingScreen, rule: settings.data.ui.markScaleRule)
        drawing.pins = composed.pins
        drawing.nextPin = composed.pins.count + 1
        drawing.pieceNumbers = composed.badges
        return drawing
    }
}
