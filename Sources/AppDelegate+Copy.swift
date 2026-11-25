import AppKit

// MARK: Copy Drawing, Done and Cmd+C

extension AppDelegate {
    /// How a copied rendering lays out its pins' comments: below or beside the picture, at a new
    /// note's text size.
    var copiedLayout: Rendering.Layout { .withComments(textSize: settings.data.ui.newTextSize) }

    /// Copy Drawing: each card's drawing as it is now, rendered and written beside its screenshot,
    /// and the original file for a card without one. The queue renders these in the order asked, so
    /// once the last rendering is done every one is.
    func copyAnnotated(_ shots: [Screenshot]) {
        let ui = settings.data.ui, style = ui.textStyle, layout = copiedLayout
        let renderings = shots.map { shot -> (shot: Screenshot, rendering: PendingRendering?, words: String?) in
            let drawing = drawings.current(of: shot.key, style: style)
            guard let drawing, !drawing.isEmpty else { return (shot, nil, nil) }
            return (shot, RenderingQueue.shared.render(drawing, imageAt: shot.url, output: .file,
                                                       style: style, markStyle: ui.markStyle, layout: layout),
                    Pin.clipboardWords(of: drawing))
        }
        if let last = renderings.compactMap(\.rendering).last {
            last.whenDone { [weak self] _ in self?.finishCopyAnnotated(renderings) }
        } else {
            finishCopyAnnotated(renderings)
        }
    }

    private func finishCopyAnnotated(_ renderings: [(shot: Screenshot, rendering: PendingRendering?, words: String?)]) {
        var urls: [URL] = [], words: [URL: String] = [:]
        for (shot, rendering, pinWords) in renderings {
            guard let rendering else { urls.append(shot.url); continue }
            let output = rendering.wait(timeout: 0)
            guard let file = output?.file else {
                let failure = output?.failure ?? .writeFailed("no rendering")
                Commands.error("copy-annotated", failure.code, "\(shot.url.lastPathComponent): \(failure)")
                thumbnail.showNotCopied(shot, reason: failure.reason)
                return
            }
            urls.append(file)
            words[file] = pinWords
        }
        Clipboard.copyFiles(urls, words: words)
        let drawn = renderings.filter { $0.rendering != nil }.count
        Commands.ok("copy-annotated", "files=\(RenderingQueue.paths(urls)); \(drawn) with annotations")
        thumbnail.showCopied(renderings.map(\.shot))
    }

    /// Done: the rendering goes on the clipboard at once as a promise and the card goes home; the
    /// file is written when the rendering finishes. With nothing drawn, the original file is copied.
    func finishAnnotation(_ shot: Screenshot, _ drawing: Drawing) {
        copyRendering(of: drawing, shot: shot, verb: "done", in: annotator.opening)
        // Quick annotate: the drawing was the point; nothing comes back.
        if settings.data.quickAnnotate { Log.write("[annotate] quick close") }
        thumbnail.annotationFinished(quick: settings.data.quickAnnotate)
    }

    /// Cmd+C in the editor with nothing selected: the same clipboard Done gives, and the editor stays open.
    func copyDrawing(_ drawing: Drawing, of shot: Screenshot) {
        copyRendering(of: drawing, shot: shot, verb: "copied", in: annotator.opening)
    }

    /// The annotated file on the clipboard as a file, an image, and its path as text, so a terminal
    /// pastes the path and a chat app pastes the image. The text carries the pins' words after the
    /// path. The file is promised, so nothing waits for the rendering but a paste that comes before
    /// it, and the rendering goes ahead of any that has not started. `verb` names the moment in the
    /// log line. The rendering, or nil when the original file was copied.
    @discardableResult
    func copyRendering(of drawing: Drawing, shot: Screenshot, verb: String, in opening: Opening?) -> PendingRendering? {
        let name = shot.url.lastPathComponent
        guard !drawing.isEmpty else {
            Clipboard.copyFiles([shot.url])
            Log.write("[annotate] \(verb) \(name) nothing drawn, original copied")
            return nil
        }
        let ui = settings.data.ui
        let rendering = RenderingQueue.shared.render(drawing, imageAt: shot.url, output: .file, style: ui.textStyle, markStyle: ui.markStyle,
                                                     layout: copiedLayout, order: .first)
        Clipboard.copyRendering(rendering, words: Pin.clipboardWords(of: drawing))
        rendering.whenDone { [weak self] output in
            guard let self else { return }
            if let failure = output.failure {
                Log.write("[annotate] error \(failure.code.rawValue) \(name): \(failure)")
                // The clipboard took its promise back; the card must not say otherwise.
                thumbnail.showNotCopied(shot, reason: failure.reason, in: opening)
            } else if let file = output.file, let png = output.png {
                Log.write("[annotate] \(verb) files=\(RenderingQueue.paths([file])) \(png.count) bytes, copied")
            }
        }
        return rendering
    }
}
