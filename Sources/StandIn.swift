import AppKit
import WebKit

/// The picture the annotator shows while a zoom is moving: the screenshot at its own pixels with
/// the annotations over it, in the frame's own layer tree.
///
/// The page is drawn by WebKit's process and the frame by this one, and the two have no shared
/// frame clock, so a moving frame and a page inside it can never be exactly aligned. The stand-in
/// is two layers in the same tree as the frame, so the frame's rect and the picture inside it
/// change in one Core Animation commit and cannot disagree. The page stays under it, covered and
/// never hidden: WebKit pauses a hidden view's frame callbacks, and the page has to report its
/// paint before the stand-in goes.
@MainActor
final class StandIn {
    /// The screenshot. `marks` is its subview, so one frame set moves both.
    let view = PictureView()
    private let marks = PictureView()

    init(shot: CGImage?, marks image: CGImage?) {
        view.image = shot
        marks.image = image
        marks.autoresizingMask = [.width, .height]
        marks.frame = view.bounds
        view.addSubview(marks)
    }

    func setShot(_ image: CGImage?) { view.image = image }
    func setMarks(_ image: CGImage?) { marks.image = image }

    /// Puts the picture where the page would draw it: the frame magnified by `camera` and slid so
    /// that the part of the image `center` names fills the frame. The caller sets the frame's own
    /// rect in the same turn, so both reach the window server together.
    func layout(in bounds: CGRect, camera: CGFloat, center: CGPoint) {
        view.frame = Zoom.picture(in: bounds, camera: camera, center: center)
    }
}

/// Everything the annotator puts on screen in place of its page while a zoom moves: the stand-in
/// itself, the two images it draws, the overlay rendering that keeps its annotations current, and
/// the hand-over that gives the picture back to the page.
///
/// It is its own type because each of the last two is a call left outstanding on the page, and the
/// annotator already remembers three of those by hand — `pendingExport`, `pendingBuild`,
/// `pendingHide` — in two places that nothing links, `canvasRefusal` and
/// `webViewWebContentProcessDidTerminate`. The stand-in's own outstanding calls were in neither
/// list. Behind this seam there is nothing to remember: the annotator says `pageRestarted()` when
/// the web process dies and `forget()` when the window goes, and what is outstanding is this
/// file's to know.
@MainActor
final class StandInController {
    /// The picture, while it is up. Nil at rest, when the page is what is seen and edited.
    private var picture: StandIn?
    /// Counts the picture's comings and goings, so an answer or a fade from before an input does
    /// not act on the picture that input is using.
    private var generation = 0
    /// The screenshot, decoded off the main thread when the image is prepared.
    private var shot: CGImage?
    /// The current image's annotations alone, as the page last rendered them.
    private var marks: CGImage?
    /// The image these pictures are of. Every answer from the page is checked against it.
    private var imageURL: URL?
    /// One overlay rendering at a time, with a redo waiting when the annotations changed while it
    /// was out; the stand-in keeps the last finished one meanwhile.
    private var overlayInFlight = false
    private var overlayStale = false
    /// How long the stand-in takes to give the picture back to the page. Short: the two are
    /// showing the same thing, so this only covers the last pixel of difference between them.
    private let fadeSeconds = 0.12

    /// Whether the zoom is standing still. The picture is handed back only at rest, and a fade
    /// that started at rest is abandoned if an input arrives during it.
    var atRest: () -> Bool = { true }
    /// Whether the annotator window is still on screen. A hand-over to a window that has gone is
    /// dropped rather than retried.
    var windowVisible: () -> Bool = { false }

    var isUp: Bool { picture != nil }
    /// The overlay's pixel size for the state report, or nil when nothing is drawn on the image.
    var overlayPixels: [Int]? { marks.map { [$0.width, $0.height] } }

    // MARK: The images

    /// A new image is opening. Forgets the last one's pictures and decodes this one's screenshot,
    /// off the main thread and inside the thumbnail cache's budget. `maxPixel` is big enough for
    /// the frame at its largest, which is the visible screen at most: past that the picture is
    /// magnified rather than grown, and the page takes over crisp at rest. It is usually the
    /// decode the flight already asked for, so it costs nothing twice.
    func prepare(for url: URL, maxPixel: Int) {
        drop()
        imageURL = url
        shot = nil
        marks = nil
        Thumbnailer.load(at: url, maxPixel: maxPixel) { [weak self] image in
            guard let self, self.imageURL == url else { return }
            self.shot = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            self.picture?.setShot(self.shot)
        }
    }

    /// Asks the page for the annotations alone, for the stand-in to lay over the screenshot. One
    /// at a time: the page renders it in its own queue, and while one is out the stand-in keeps
    /// the last one, which is the same annotations minus the change that started this.
    func refreshOverlay(on webView: WKWebView, for key: String) {
        guard key == imageURL?.path else { return }
        let epoch = self.epoch
        guard !overlayInFlight else { overlayStale = true; return }
        overlayInFlight = true
        overlayStale = false
        webView.callAsyncJavaScript(PageAPI.overlay(maxPixel: Config.overlayMaxPixel).script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard self.epoch == epoch else { self.overlayInFlight = false; return }
            guard case .success(let value) = result, let png = (value as? String).flatMap(WebMessage.pngData) else {
                self.setMarks(nil, for: key, on: webView)
                return
            }
            Thumbnailer.decode(png: png) { [weak self] image in
                self?.setMarks(image?.cgImage(forProposedRect: nil, context: nil, hints: nil), for: key, on: webView)
            }
        }
    }

    /// The annotations the stand-in draws, and the next rendering when they changed while this one
    /// was out. The redo waits for this one so the newest rendering is the one that stays.
    private func setMarks(_ image: CGImage?, for key: String, on webView: WKWebView) {
        overlayInFlight = false
        guard key == imageURL?.path else { return }
        marks = image
        picture?.setMarks(image)
        if let image { Log.write("[annotate] overlay \(image.width)x\(image.height) \((key as NSString).lastPathComponent)") }
        if overlayStale { refreshOverlay(on: webView, for: key) }
    }

    /// Counts web process restarts, so an answer from a page that has since been replaced is
    /// dropped rather than acted on.
    private var epoch = 0

    // MARK: Up and down

    /// The picture becomes the app's own: the screenshot and the annotations in the frame's own
    /// layer tree, over the page, which stays where it is. Called before every zoom step, and on
    /// the fit the window makes on its way out.
    func raise(over webView: WKWebView, in container: NSView, camera: CGFloat, center: CGPoint) {
        generation += 1
        if let picture {
            // A fade out may be running: the picture is wanted again, so take it back at once.
            picture.view.layer?.removeAllAnimations()
            picture.view.alphaValue = 1
            return
        }
        // Whatever is decoded stands in until the full decode lands; the card's own thumbnail is
        // warm by now, and a soft picture for a frame or two beats an empty frame.
        let image = shot ?? imageURL.flatMap { Thumbnailer.cached(at: $0, maxPixel: 1) }?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
        let made = StandIn(shot: image, marks: marks)
        container.addSubview(made.view, positioned: .above, relativeTo: webView)
        picture = made
        made.layout(in: container.bounds, camera: camera, center: center)
    }

    /// One tick of a zoom. The caller sets the frame's own rect in the same run loop turn.
    func layout(in bounds: CGRect, camera: CGFloat, center: CGPoint) {
        picture?.layout(in: bounds, camera: camera, center: center)
    }

    /// The picture goes at once. The annotator calls this when the window is hidden and when the
    /// web process dies: the page cannot answer that it has painted, and the stand-in only ever
    /// comes down on that answer, so without this it would cover the reloaded page for good.
    func drop() {
        generation += 1
        picture?.view.removeFromSuperview()
        picture = nil
    }

    /// The window has gone: the picture and both its images with it.
    func forget() {
        drop()
        imageURL = nil
        shot = nil
        marks = nil
    }

    /// The web process restarted. Nothing outstanding on the old page can answer, so the picture
    /// comes down and the overlay throttle is free again for the page that replaces it.
    func pageRestarted() {
        epoch += 1
        overlayInFlight = false
        overlayStale = false
        drop()
    }

    // MARK: The hand-over

    /// Gives the picture back to the page: it is laid out at the frame's size and given the exact
    /// view the stand-in is showing. The page answers when it has painted that, and the stand-in
    /// fades out over it. The page is covered, never hidden, so its frame callbacks keep running
    /// and the answer arrives.
    ///
    /// `retrying` is the second attempt, made once when the first one does not answer inside an
    /// export's timeout: the page answers from a `requestAnimationFrame`, which WebKit stops while
    /// the screen is locked. After that the stand-in comes down without an answer, since a picture
    /// that never leaves covers an editor the user can still draw in.
    func handOver(to webView: WKWebView, size: CGSize, camera: CGFloat, center: CGPoint,
                  pageReady: Bool, retrying: Bool = false) {
        guard picture != nil, windowVisible(), atRest() else { return }
        let epoch = self.epoch
        // Only when the frame's size really changed: past the window's limit a zoom moves the
        // magnification alone, and a resize the page has to answer costs it a relayout.
        if webView.frame.size != size { webView.frame = CGRect(origin: .zero, size: size) }
        guard pageReady else { fade(); return }
        let request = ViewRequest(ratio: Double(camera), x: Double(center.x), y: Double(center.y),
                                  width: Double(size.width), height: Double(size.height))
        let generation = self.generation
        let started = CACurrentMediaTime()
        var answered = false
        // The call takes its turn behind the other canvas calls, so the deadline is an export's:
        // a hand-over behind a Copy Drawing is late, not lost. One retry, and then the picture
        // comes down anyway; a stand-in left up covers an editor the user can draw in blind.
        let timeout = AnnotationController.exportTimeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, !answered, self.epoch == epoch, self.generation == generation else { return }
            answered = true
            Log.write("[annotate] view timeout after \(Int(timeout)) s\(retrying ? " (second try)" : "")")
            guard !retrying, self.windowVisible() else { self.fade(); return }
            self.handOver(to: webView, size: size, camera: camera, center: center,
                          pageReady: pageReady, retrying: true)
        }
        webView.callAsyncJavaScript(PageAPI.setView(request).script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, !answered, self.epoch == epoch, self.generation == generation else { return }
            answered = true
            if case .failure(let error) = result {
                Log.write("[web] error view failed: \(String(describing: error).replacingOccurrences(of: "\n", with: " "))")
            } else if let view = ViewResult(body: try? result.get()) {
                let asked = String(format: "%.4f", camera), painted = String(format: "%.4f", view.ratio)
                Log.write("[annotate] view \(Int((CACurrentMediaTime() - started) * 1000))ms ratio=\(asked) painted=\(painted) waited=\(view.waited)")
                // The page paints at the size and the magnification that reached its process. A gap
                // wider than the layout's own rounding, or a magnification that is not the one
                // asked for, means its picture is not this frame's, so it gets a line.
                if abs(view.width - Double(size.width)) > 1 || abs(view.height - Double(size.height)) > 1
                    || abs(view.ratio - Double(camera)) > 0.001 {
                    Log.write("[annotate] view mismatch page=\(Int(view.width))x\(Int(view.height))@\(painted) host=\(Int(size.width))x\(Int(size.height))@\(asked)")
                }
            } else {
                // The page refused the numbers and left its camera where it was, so it is showing
                // the view it had. Uncovering that beats a frozen picture over a live editor.
                Log.write("[web] error view refused ratio=\(String(format: "%.4f", camera))")
            }
            self.fade()
        }
    }

    /// The page has the picture; the stand-in goes. Short and motion scaled, so `ui.motion: 0` and
    /// Reduce Motion swap outright.
    ///
    /// Only while the zoom is standing still. The page paints the view it was given at the size it
    /// was given; if the spring has moved on while that answer was in the air, the page's picture
    /// is behind the frame and fading to it would show the gap for a frame. The stand-in stays and
    /// the next rest hands over again.
    private func fade() {
        guard let picture, atRest() else { return }
        generation += 1
        let generation = self.generation
        let seconds = fadeSeconds * Settings.shared.motionScale
        guard seconds > 0 else { drop(); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = seconds
            picture.view.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == generation else { return }
            self.drop()
        })
    }
}

/// A view whose layer shows one image, stretched to its bounds by Core Animation rather than
/// redrawn: a zoom changes those bounds on every display refresh, and a redraw of a screen-sized
/// image per refresh would be a main-thread cost per frame. `wantsUpdateLayer` is what stops
/// AppKit replacing the layer's contents with a backing store of its own.
final class PictureView: NSView {
    var image: CGImage? {
        didSet {
            wantsLayer = true
            layer?.contents = image
        }
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.contentsGravity = .resize
        // The screenshot is usually larger than the frame it is shown in; trilinear takes the
        // shimmer out of that minification, which linear leaves in.
        layer?.minificationFilter = .trilinear
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}
