import AppKit

// MARK: The agent's title

extension AnnotationController {
    /// The agent's title above the frame in screen coordinates, while it is shown.
    var titleFrameOnScreen: NSRect? {
        guard let win = window, let frame = titleView.shownFrame else { return nil }
        return win.convertToScreen(frame)
    }

    /// Puts the title above `frame`, in screen coordinates, wrapping where `StackLayout` says.
    func placeTitle(frame: NSRect) {
        guard let win = window else { return }
        let ui = Settings.shared.data.ui
        let wrap = StackLayout.titleWrapWidth(frame: frame, room: zoom.room, minimum: ui.agentTitleMinWidth,
                                              indent: ui.annotationCornerRadius)
        titleView.place(above: frame.offsetBy(dx: -win.frame.minX, dy: -win.frame.minY), wrap: wrap, ui: ui)
    }

    /// Picks the title's ink for where the block is now. With Screen Recording, from the screen
    /// behind the block, read off the main thread, under the dim. Without it, from the system
    /// appearance: Vignette cannot see other apps' windows then, and a light appearance mostly
    /// means light windows. An answer for a block that has moved since, or an image that has gone,
    /// is dropped.
    func measureTitleInk() {
        guard titleView.content != nil, current != nil, let win = window else { inkSource = nil; return }
        inkMeasurement += 1
        let measurement = inkMeasurement
        guard CGPreflightScreenCaptureAccess() else {
            applyInk(appearanceInk, source: "appearance", detail: "no screen recording")
            return
        }
        let screen = win.convertToScreen(titleView.frame)
        let primary = StateReport.primaryHeight
        let rect = CGRect(x: screen.minX, y: primary - screen.maxY, width: screen.width, height: screen.height)
        let ui = Settings.shared.data.ui
        Task { [weak self] in
            let cells = await TitleBackdrop.brightness(in: rect, cell: max(ui.dimBlurRadius, 8))
            guard let self, inkMeasurement == measurement, current != nil else { return }
            let luminances = (cells ?? []).map { TitleInk.luminance(encoded: $0, dim: ui.dimOpacity) }
            guard let ink = TitleInk.choose(behind: luminances), let low = luminances.min(), let high = luminances.max() else {
                applyInk(appearanceInk, source: "appearance", detail: "the screen could not be read")
                return
            }
            applyInk(ink, source: "backdrop", detail: String(format: "luminance=%.3f...%.3f", low, high))
        }
    }

    private var appearanceInk: TitleInk {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    }

    private func applyInk(_ ink: TitleInk, source: String, detail: String) {
        titleView.set(ink: ink)
        inkSource = source
        Log.write("[annotate] title ink=\(ink.rawValue) source=\(source) \(detail)")
        revealTitle(.inkKnown(at: CACurrentMediaTime()))
    }

    /// The file's sender changed after it opened: the session list answered late, or a push named
    /// another. The sender's line says it in place, so the block keeps its height and the frame stays.
    func refreshSender(of shot: Screenshot) {
        guard current?.url == shot.url, var content = titleView.content else { return }
        content.sender = .of(shot.url)
        guard content != titleView.content else { return }
        titleView.set(content, ui: Settings.shared.data.ui)
        if let frame = frameOnScreen { placeTitle(frame: frame) }
    }

    func revealTitle(_ input: TitleReveal.Input) {
        switch titleReveal.reduce(input) {
        case .waitForInk?:
            guard let opening = opened else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + TitleReveal.inkWait) { [weak self] in
                guard let self, opened == opening, current != nil else { return }
                revealTitle(.waitEnded(at: CACurrentMediaTime()))
            }
        case .show(let waited)?:
            showTitle(waited: waited)
        case .showInAppearanceInk(let waited)?:
            applyInk(appearanceInk, source: "appearance", detail: "no answer from the screen after \(Self.milliseconds(waited))ms")
            showTitle(waited: waited)
        case nil:
            break
        }
    }

    private func showTitle(waited: TimeInterval) {
        titleView.show(true, duration: Settings.shared.motionUI.agentTitleFade)
        Log.write("[annotate] title shown ink=\(titleView.ink.rawValue) source=\(inkSource ?? "none") waited=\(Self.milliseconds(waited))ms")
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int { Int((seconds * 1000).rounded()) }

    /// The agent's title as it is drawn now, for the flight taking `key` home, which carries it from
    /// here. The block stops drawing with the frame (`hideWindows`).
    func takeTitle(of key: ScreenshotKey) -> TransitionLayer.Caption? {
        guard opened?.key == key, let frameView, let image = titleView.picture() else { return nil }
        let offset = CGPoint(x: titleView.frame.minX - frameView.frame.minX, y: frameView.frame.maxY - titleView.frame.maxY)
        return TransitionLayer.Caption(image: image, offset: offset, frameWidth: frameView.frame.width,
                                       opacity: titleView.alphaValue)
    }
}
