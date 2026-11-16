import AppKit
import ScreenCaptureKit
import Vision

/// What an ask sends about the screen (docs/live-ink-integration-2026-10-04.md, "The packet"): a
/// capture of the whole window under the new ink with the ink drawn in, the window's text lines from
/// Vision with ids a mark can name, the ink as boxes, and where it is.
///
/// The text is read from the capture before the ink is drawn in, since ink across a line garbled
/// what Vision read of it. Accurate recognition only: the fast level read code as `swif t` and
/// `rnarkz` (docs/live-ink-step2-spike-2026-10-04.md).
struct LivePacket: @unchecked Sendable {
    /// One line of the window's text, with the box it was read in.
    struct Line {
        let id: String
        /// What an ask sends: `read` cut at `LivePacket.maxLineLength`.
        let text: String
        /// In fractions of the picture, from its top-left corner.
        let box: CGRect
        /// Every character read on the line. A mark's words are found in this, not in `text`.
        let read: String
        private let rangeBox: (Range<String.Index>) -> CGRect?

        init(id: String, read: String, box: CGRect, rangeBox: @escaping (Range<String.Index>) -> CGRect?) {
            self.id = id
            text = String(read.prefix(LivePacket.maxLineLength))
            self.box = box
            self.read = read
            self.rangeBox = rangeBox
        }

        /// The box of `range`, a range of `read`, in fractions of the picture from its top-left corner,
        /// or nil where the reading gives none. On the main actor, because Vision's reading behind it is
        /// only read on the main thread once the packet is built.
        @MainActor func box(of range: Range<String.Index>) -> CGRect? { rangeBox(range) }
    }

    /// The window the ink is on, in global top-left points, when it was captured.
    let frame: CGRect
    let windowID: CGWindowID?
    let app: String?
    let title: String?
    /// The page's URL or the document's path, when Accessibility gives one.
    let location: String?
    /// The web page's area in a browser's window, in global top-left points, when Accessibility gives
    /// it: the window less its tabs, toolbar and title bar.
    let page: CGRect?
    let lines: [Line]
    /// The capture with the ink drawn in, sized for the reader.
    let picture: Data
    /// The number drawn beside each of the person's strokes in the picture, from 1 in the order they
    /// were drawn. The ink in `message` and a spoken note's `[n]` use the same numbers.
    let numbers: [Mark.ID: Int]
    /// A part of the window round the ink at full detail, for a window too large to read whole after
    /// the reader's resize, with its rect in fractions of the picture.
    let detail: (png: Data, box: CGRect)?
    /// How light the screen is under the picture as the person sees it, coarsely, before the ink.
    let luminance: Luminance?
    /// The window as captured, without the ink, at the display's scale.
    let capture: CGImage
    /// Says whether the window's text is what it was in an earlier packet.
    var textSignature: String { lines.map(\.text).joined(separator: "\n") }

    /// For a picture of an area of the screen, the windows that hold the ink asked about, front to
    /// back; empty for a picture of one window.
    let windows: [Shown]
    /// For a picture of an area, each window holding ink the area does not show, alone.
    let alone: [Alone]
    /// What the picture is of: a follow-up sends no picture only when this is the same.
    let subject: Subject
    /// For a picture of the screen, the parts it shows, in global top-left points: the windows the ink
    /// is on, a menu it is over, and the screen round ink on no window. Nil for a picture of one window.
    let shownRegions: [CGRect]?

    /// Where an answer's mark points, in global top-left points, or nil when it is not found or points
    /// at a part of the screen the picture left out, which the model saw only as wallpaper.
    @MainActor func target(of mark: AnswerMark, sent: Set<String>) -> CGRect? {
        guard let box = mark.target(in: lines, sent: sent).map(global) else { return nil }
        return shownRegions?.contains { $0.contains(CGPoint(x: box.midX, y: box.midY)) } ?? true ? box : nil
    }

    /// The capture's pixels per point.
    var scale: CGFloat { CGFloat(capture.width) / frame.width }

    /// A window in a picture of an area: its app, its title and its frame in global top-left points.
    struct Shown {
        let app: String?
        let title: String?
        let frame: CGRect
    }

    /// One window captured alone, with its ink drawn in and numbered as in the area's picture,
    /// sized for the reader. `ink` is the ink asked about on it; on the screen, `covered` is under a
    /// window in front and `outside` is past the area's picture.
    struct Alone {
        let window: CGWindowID
        let app: String?
        let title: String?
        let picture: Data
        let ink: [Mark.ID]
        let covered: [Mark.ID]
        let outside: [Mark.ID]
    }

    enum Subject: Equatable {
        case window(CGWindowID?)
        case area(CGRect, alone: [CGWindowID])
    }

    var isArea: Bool { if case .area = subject { true } else { false } }

    /// Whether one of the packet's pictures shows `mark`: the main one, or that of a window alone.
    func holds(_ mark: Mark) -> Bool { numbers[mark.id] != nil || frame.intersects(mark.shapeExtent ?? .null) }

    /// `marks`, in global top-left points, as a drawing of `capture` holds them: in its pixels, with
    /// sizes in points of `scale`. Each is a new mark with the same geometry and author, so what
    /// only live ink keeps on a mark, such as its notice or its popover, stays behind.
    func drawingMarks(_ marks: [Mark]) -> [Mark] {
        let scale = scale
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - frame.minX) * scale, y: (p.y - frame.minY) * scale) }
        func rect(_ r: CGRect) -> CGRect { CGRect(origin: point(r.origin), size: CGSize(width: r.width * scale, height: r.height * scale)) }
        return marks.map { mark in
            let geometry: Mark.Geometry
            switch mark.geometry {
            case .rectangle(let box): geometry = .rectangle(rect(box))
            case .ellipse(let box): geometry = .ellipse(rect(box))
            case .arrow(var arrow):
                arrow.start = point(arrow.start)
                arrow.end = point(arrow.end)
                arrow.bend *= scale
                arrow.via = arrow.via.map(point)
                geometry = .arrow(arrow)
            case .text(var text):
                text.origin = point(text.origin)
                text.wrap = text.wrap.map { $0 * scale }
                geometry = .text(text)
            }
            return Mark(geometry: geometry, agent: mark.agent, agentName: mark.agentName)
        }
    }

    /// Where a window's text is, found before its text is read, in global top-left points: what a
    /// note keeps clear of. Vision finds the boxes in a tenth of the time it takes to read them well.
    struct Glance: Sendable {
        let frame: CGRect
        let page: CGRect?
        let text: [CGRect]
    }

    struct Failure: Error, CustomStringConvertible {
        let reason: String
        let detail: String
        var description: String { "\(reason) (\(detail))" }
    }

    /// The longest text line a packet keeps, in characters.
    static let maxLineLength = 200
    /// The most an ask sends of the window's text, in characters of `textLines`, the lines nearest its
    /// ink: about half of a terminal's, whose text cost more than the pictures
    /// (docs/live-ink-ask-cost-2026-10-06.md).
    static let sentCharacters = 4_500

    /// The window under `point`, in global top-left points, captured and read, or the window `id`
    /// names while it is on screen, whatever covers it. `ink` is every mark of the person's to draw
    /// into the picture, in global top-left points at 1 px per pt.
    /// `glanced` is called off the main thread with the window's `Glance` as soon as it is known,
    /// before the packet is.
    @MainActor
    static func build(at point: CGPoint, window id: CGWindowID? = nil, ink: [Mark], style: TextStyle,
                      markStyle: MarkStyle, glanced: (@Sendable (Glance) -> Void)? = nil) async throws -> LivePacket {
        try await build(.window(id), at: point, ink: ink, style: style, markStyle: markStyle, glanced: glanced)
    }

    /// What `plan` says to capture, read. For one window, as `build(at:window:)`. For an area, that
    /// part of the display with only what the ink is on, then each window the plan sends alone;
    /// `inkWindows` says which window each of `ink` is on.
    @MainActor
    static func build(_ plan: Plan, at point: CGPoint, ink: [Mark], inkWindows: [Mark.ID: CGWindowID] = [:], style: TextStyle,
                      markStyle: MarkStyle, glanced: (@Sendable (Glance) -> Void)? = nil) async throws -> LivePacket {
        let started = Date()
        let content = try await shareableContent()
        var id: CGWindowID?
        var area: (rect: CGRect, windows: [CGWindowID], alone: [Plan.Alone])?
        switch plan {
        case .window(let window): id = window
        case .area(let rect, let windows, let alone): area = (rect, windows, alone)
        }
        let named = id.flatMap { id in content.windows.contains { $0.windowID == id } ? (id: id, frame: CGRect.null) : nil }
        let target = area == nil ? named ?? LiveWindows.window(under: point, ordinary: false).map { ($0.id, $0.frame) } : nil
        let filter: SCContentFilter
        let frame: CGRect
        var source: CGRect?
        var asSeen: SCContentFilter?
        var shownRegions: [CGRect]?
        var app: String?, title: String?, pid: pid_t?
        if let target, let window = content.windows.first(where: { $0.windowID == target.id }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
            frame = window.frame
            app = window.owningApplication?.applicationName
            title = window.title
            pid = window.owningApplication?.processID
        } else if let display = area.flatMap({ area in content.displays.first { $0.frame.intersects(area.rect) } })
                    ?? content.displays.first(where: { $0.frame.contains(point) }) ?? content.displays.first {
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            asSeen = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            // Only what the ink is on: its windows, a menu it is over, and the desktop, which
            // `shareableContent` never lists. A prompt of macOS's own over the ink is not.
            let holders = Set((area?.windows ?? []) + (area?.alone ?? []).map(\.window))
            let prompts = SystemPrompts.windowIDs()
            let kept = content.windows.filter { window in
                holders.contains(window.windowID) || (window.windowLayer > Self.menuBarLevel && !prompts.contains(window.windowID)
                    && ink.contains { window.frame.intersects($0.shapeExtent ?? .null) })
            }
            filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { !kept.contains($0) })
            let margin = -Self.screenInkMargin
            shownRegions = kept.map(\.frame) + ink.filter { inkWindows[$0.id] == nil }.compactMap { $0.shapeExtent?.insetBy(dx: margin, dy: margin) }
            if let area {
                frame = area.rect.intersection(display.frame)
                source = frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            } else {
                frame = display.frame
            }
        } else {
            throw Failure(reason: "Vignette couldn't see the screen.", detail: "no window or display")
        }
        let capture: CGImage
        // As the person sees it, for the brightness under the answer's marks. Never sent.
        var seen: CGImage?
        do {
            let settings = configuration(frame, scale: scale(at: area == nil ? point : CGPoint(x: frame.midX, y: frame.midY)), source: source)
            capture = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: settings)
            if let asSeen { seen = try await SCScreenshotManager.captureImage(contentFilter: asSeen, configuration: settings) }
        } catch {
            throw captureFailed(error)
        }
        let captured = Date()
        try Task.checkCancellation()
        // Each Accessibility call may wait out its 0.1 s timeout, and a web page takes many, so the
        // page is looked for while the text is read.
        // Ink an area's picture does not show is numbered with the rest, for the pictures of its windows.
        let outside = Set((area?.alone ?? []).flatMap(\.outside))
        let found = Task.detached(priority: .userInitiated) { () -> (page: Page?, at: Date) in
            (pid.flatMap { Self.page(pid: $0, frame: frame) }, Date())
        }
        // The glance first: run beside the full read, it took 360 to 450 ms rather than 15 to 25.
        let assembled = try await Task.detached(priority: .userInitiated) {
            if let glanced {
                let text = textBoxes(capture).map {
                    CGRect(x: frame.minX + $0.minX * frame.width, y: frame.minY + $0.minY * frame.height,
                           width: $0.width * frame.width, height: $0.height * frame.height)
                }
                let read = Date()
                let page = await found.value.page?.area
                Log.write("[live-ink] glanced ms capture=\(Int(captured.timeIntervalSince(started) * 1000)) text=\(Int(read.timeIntervalSince(started) * 1000)) page=\(Int(Date().timeIntervalSince(started) * 1000)) lines=\(text.count)")
                glanced(Glance(frame: frame, page: page, text: text))
            }
            return try assemble(capture, seen: seen, frame: frame, ink: ink, also: outside, style: style, markStyle: markStyle)
        }.value
        let page = await found.value
        var alone: [Alone] = []
        for each in area?.alone ?? [] {
            try Task.checkCancellation()
            guard let window = content.windows.first(where: { $0.windowID == each.window }) else { continue }
            let own = ink.filter { inkWindows[$0.id] == each.window }
            alone.append(try await picture(of: window, ink: own, numbers: assembled.numbers, plan: each, style: style, markStyle: markStyle))
        }
        let shown = (area?.windows ?? []).compactMap { id in
            content.windows.first { $0.windowID == id }.map { Shown(app: $0.owningApplication?.applicationName, title: $0.title, frame: $0.frame) }
        }
        let ms = { (date: Date) in Int(date.timeIntervalSince(started) * 1000) }
        Log.write("[live-ink] looked ms capture=\(ms(captured)) page=\(ms(page.at)) read=\(ms(assembled.at))"
                  + (area == nil ? "" : " alone=\(alone.count) done=\(ms(Date()))"))
        let subject: Subject = area == nil ? .window(target?.id) : .area(frame, alone: alone.map(\.window))
        return LivePacket(frame: frame, windowID: target?.id, app: app, title: title, location: page.page?.location, page: page.page?.area,
                          lines: assembled.lines, picture: assembled.picture, numbers: assembled.numbers, detail: assembled.detail,
                          luminance: assembled.luminance, capture: capture, windows: shown, alone: alone, subject: subject,
                          shownRegions: shownRegions)
    }

    /// `window` captured alone with `ink` drawn in, each stroke numbered as `numbers` says, sized for
    /// the reader.
    @MainActor
    private static func picture(of window: SCWindow, ink: [Mark], numbers: [Mark.ID: Int], plan: Plan.Alone, style: TextStyle,
                                markStyle: MarkStyle) async throws -> Alone {
        let frame = window.frame
        let capture: CGImage
        do {
            capture = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                                 configuration: configuration(frame, scale: scale(at: CGPoint(x: frame.midX, y: frame.midY))))
        } catch {
            throw captureFailed(error)
        }
        let picture = try await Task.detached(priority: .userInitiated) { () throws -> Data in
            guard let inked = draw(ink, numbers: numbers, on: capture, frame: frame, style: style, markStyle: markStyle),
                  let data = png(inked, scale: Stitch.readerScale(CGSize(width: inked.width, height: inked.height))) else {
                throw Failure(reason: "Vignette couldn't draw the ink into the picture.", detail: "alone")
            }
            return data
        }.value
        return Alone(window: plan.window, app: window.owningApplication?.applicationName, title: window.title, picture: picture,
                     ink: plan.ink, covered: plan.covered, outside: plan.outside)
    }

    /// The window `id` as it is now, alone, so none of Vignette's overlays are in it, with its frame in
    /// global top-left points.
    static func capture(window id: CGWindowID) async throws -> (image: CGImage, frame: CGRect) {
        let content = try await shareableContent()
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw Failure(reason: "Vignette couldn't find the window.", detail: "no window \(id)")
        }
        let frame = window.frame
        let configuration = configuration(frame, scale: scale(at: CGPoint(x: frame.midX, y: frame.midY)))
        do {
            return (try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                               configuration: configuration), frame)
        } catch {
            throw captureFailed(error)
        }
    }

    private static func shareableContent() async throws -> SCShareableContent {
        guard CGPreflightScreenCaptureAccess() else {
            throw Failure(reason: "Live ink needs Screen Recording permission to see the screen.", detail: "screen-recording")
        }
        do {
            return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw Failure(reason: "Vignette couldn't see the screen.", detail: "shareable content: \(error.localizedDescription)")
        }
    }

    /// The backing scale of the screen holding `point`, in global top-left points.
    private static func scale(at point: CGPoint) -> CGFloat {
        StateReport.screen(at: point)?.backingScaleFactor ?? 2
    }

    /// A capture of `frame`'s size at `scale` pixels a point, without the cursor or a window's shadow.
    /// `source` is the part of a display to capture, in points from the display's top-left.
    private static func configuration(_ frame: CGRect, scale: CGFloat, source: CGRect? = nil) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        if let source { configuration.sourceRect = source }
        configuration.width = max(1, Int((frame.width * scale).rounded()))
        configuration.height = max(1, Int((frame.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        return configuration
    }

    private static func captureFailed(_ error: Error) -> Failure {
        Failure(reason: "Vignette couldn't capture the window.", detail: "capture: \(error.localizedDescription)")
    }

    /// What `assemble` makes, and when it was done. Unchecked for the packet's reason: its lines'
    /// readings are read only on the main thread once the packet is built.
    private struct Assembled: @unchecked Sendable {
        let lines: [Line]
        let picture: Data
        let numbers: [Mark.ID: Int]
        let detail: (png: Data, box: CGRect)?
        let luminance: Luminance?
        let at: Date
    }

    /// Off the main thread: reads the text, draws the ink in, and sizes the picture for the reader.
    private static func assemble(_ capture: CGImage, seen: CGImage?, frame: CGRect, ink: [Mark], also: Set<Mark.ID>, style: TextStyle,
                                 markStyle: MarkStyle) throws -> Assembled {
        let lines = read(capture)
        let pixels = CGSize(width: capture.width, height: capture.height)
        let numbers = numbered(ink, in: frame, also: also)
        guard let inked = draw(ink, numbers: numbers, on: capture, frame: frame, style: style, markStyle: markStyle) else {
            throw Failure(reason: "Vignette couldn't draw the ink into the picture.", detail: "bitmap")
        }
        let readerScale = Stitch.readerScale(pixels)
        guard let picture = png(inked, scale: readerScale) else {
            throw Failure(reason: "Vignette couldn't draw the ink into the picture.", detail: "png")
        }
        var detail: (Data, CGRect)?
        // Fewer pixels than points after the resize: small text no longer reads, so the part round the
        // new ink goes as well, at full detail.
        if readerScale * pixels.width / frame.width < 1, let box = detailBox(around: ink, in: frame),
           let crop = inked.cropping(to: CGRect(x: box.minX * pixels.width, y: box.minY * pixels.height,
                                                width: box.width * pixels.width, height: box.height * pixels.height).integral),
           let png = png(crop, scale: Stitch.readerScale(CGSize(width: crop.width, height: crop.height))) {
            detail = (png, box)
        }
        return Assembled(lines: lines, picture: picture, numbers: numbers, detail: detail,
                         luminance: Luminance(seen ?? capture, frame: frame), at: Date())
    }

    /// The lines nearest `ink`, a rect in global top-left points, that fit in `sentCharacters`, in
    /// reading order. Characters rather than lines, since the text is the cost: Vision splits a row
    /// into pieces, and a line of code can be ten times a terminal prompt's length.
    func lines(near ink: CGRect) -> [Line] {
        let gaps = lines.map { line -> CGFloat in
            guard !ink.isNull else { return 0 }
            let box = global(line.box)
            return hypot(max(0, box.minX - ink.maxX, ink.minX - box.maxX), max(0, box.minY - ink.maxY, ink.minY - box.maxY))
        }
        var room = Self.sentCharacters
        var kept: [Int] = []
        for index in lines.indices.sorted(by: { (gaps[$0], $0) < (gaps[$1], $1) }) {
            let size = Self.textLine(lines[index]).count + 1
            guard size <= room else { break }
            room -= size
            kept.append(index)
        }
        return kept.sorted().map { lines[$0] }
    }

    /// `lines` for an ask, one per line: the line's id, its box in thousandths of the picture, then
    /// its words, as `t2 12 34 640 14 error: …`. As JSON the same lines cost the reader nearly twice
    /// the tokens (docs/live-ink-ask-cost-2026-10-06.md). Nil for no lines.
    static func textLines(_ lines: [Line]) -> String? {
        lines.isEmpty ? nil : lines.map(textLine).joined(separator: "\n")
    }

    private static func textLine(_ line: Line) -> String {
        // A newline in the words would start a line with no id.
        let words = line.text.components(separatedBy: .newlines).joined(separator: " ")
        return ([line.id] + thousandths(line.box).map(String.init) + [words]).joined(separator: " ")
    }

    /// `rect`, in global top-left points, in thousandths of the picture.
    func thousandths(of rect: CGRect) -> [Int] {
        Self.thousandths(CGRect(x: (rect.minX - frame.minX) / frame.width, y: (rect.minY - frame.minY) / frame.height,
                                width: rect.width / frame.width, height: rect.height / frame.height))
    }

    func thousandths(of point: CGPoint) -> [Int] {
        [(point.x - frame.minX) / frame.width, (point.y - frame.minY) / frame.height].map(Self.thousandths)
    }

    /// A rect in fractions of the picture, in global top-left points.
    func global(_ fractions: CGRect) -> CGRect { Self.global(fractions, in: frame) }

    /// A rect in fractions of a picture of the window at `frame`, in global top-left points.
    static func global(_ fractions: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + fractions.minX * frame.width, y: frame.minY + fractions.minY * frame.height,
               width: fractions.width * frame.width, height: fractions.height * frame.height)
    }

    /// A rect in fractions of the picture as the reader gets it: x, y, width and height in thousandths.
    static func thousandths(_ rect: CGRect) -> [Int] {
        [rect.minX, rect.minY, rect.width, rect.height].map(thousandths)
    }

    static func thousandths(_ fraction: CGFloat) -> Int {
        Int((fraction * 1000).rounded())
    }

    // MARK: Pieces

    /// Vision's lines, in reading order: top to bottom, and left to right within a row.
    static func read(_ image: CGImage) -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: image)
        try? handler.perform([request])
        let found = (request.results ?? []).compactMap { observation -> (VNRecognizedText, CGRect)? in
            guard let text = observation.topCandidates(1).first, text.confidence > 0.3 else { return nil }
            let box = observation.boundingBox
            return (text, CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
        }
        let rowHeight = (found.map(\.1.height).sorted().dropFirst(found.count / 2).first ?? 0.01) / 2
        let ordered = found.sorted { a, b in
            let rowA = (a.1.midY / rowHeight).rounded(), rowB = (b.1.midY / rowHeight).rounded()
            return rowA == rowB ? a.1.minX < b.1.minX : rowA < rowB
        }
        return ordered.enumerated().map { index, item in
            let text = item.0
            return Line(id: "t\(index + 1)", read: text.string, box: item.1) { range in
                (try? text.boundingBox(for: range)?.boundingBox).map { CGRect(x: $0.minX, y: 1 - $0.maxY, width: $0.width, height: $0.height) }
            }
        }
    }

    /// Where the image's lines of text are, in fractions from its top-left. Vision's fast level
    /// without language correction: on a window of the demo it found 53 of the 55 lines the accurate
    /// level read, in 19 ms rather than 218, where text rectangle detection found 23.
    static func textBoxes(_ image: CGImage) -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).map { CGRect(x: $0.boundingBox.minX, y: 1 - $0.boundingBox.maxY, width: $0.boundingBox.width,
                                                    height: $0.boundingBox.height) }
    }

    /// Vision on a small blank image, so both levels' models are loaded before the first ink: the
    /// accurate level's first call took 300 to 480 ms, and later ones 100 to 170 ms for a window, and
    /// the fast level's first glance took 250 to 300 ms against 20 ms after.
    static func warmUp() {
        Task.detached(priority: .utility) {
            guard let context = CGContext(data: nil, width: 240, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 48))
            // A word to find: on a blank image Vision skips the recognizer, which stays unloaded.
            let words = NSAttributedString(string: "Ask about this", attributes: [
                .font: CTFontCreateUIFontForLanguage(.system, 22, nil)!, .foregroundColor: CGColor(gray: 0, alpha: 1),
            ])
            context.textPosition = CGPoint(x: 12, y: 16)
            CTLineDraw(CTLineCreateWithAttributedString(words), context)
            if let image = context.makeImage() {
                _ = read(image)
                _ = textBoxes(image)
            }
        }
    }

    /// The person's strokes on the window, and those of `also`, numbered from 1 in the order they were drawn.
    static func numbered(_ ink: [Mark], in frame: CGRect, also: Set<Mark.ID> = []) -> [Mark.ID: Int] {
        let strokes = ink.filter { also.contains($0.id) || $0.shapeExtent?.intersects(frame) ?? false }
        return Dictionary(uniqueKeysWithValues: strokes.enumerated().map { ($1.id, $0 + 1) })
    }

    /// The capture with `ink` drawn over it, and each stroke's number beside it, at the capture's own size.
    private static func draw(_ ink: [Mark], numbers: [Mark.ID: Int], on capture: CGImage, frame: CGRect, style: TextStyle,
                             markStyle: MarkStyle) -> CGImage? {
        let space = capture.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: capture.width, height: capture.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(capture, in: CGRect(x: 0, y: 0, width: capture.width, height: capture.height))
        // From here on the units are the marks' own: global top-left points.
        let scale = CGFloat(capture.width) / frame.width
        context.translateBy(x: 0, y: CGFloat(capture.height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -frame.minX, y: -frame.minY)
        for mark in ink { mark.draw(in: context, pointScale: 1, imageWidth: frame.maxX, style: style, markStyle: markStyle) }
        // Ink numbered for another picture has its badge there.
        for mark in ink where mark.shapeExtent?.intersects(frame) == true {
            if let number = numbers[mark.id] { drawNumber(number, beside: mark, in: context, frame: frame, markStyle: markStyle) }
        }
        return context.makeImage()
    }

    /// A badge's radius, in points.
    private static let badgeRadius: CGFloat = 9

    /// A round badge in the person's colour with `number` in white, outside the stroke where a hand
    /// would write it: past an arrow's tail, or off a loop's top-left. `context` is in global top-left
    /// points.
    private static func drawNumber(_ number: Int, beside mark: Mark, in context: CGContext, frame: CGRect, markStyle: MarkStyle) {
        let r = badgeRadius
        var center: CGPoint
        switch mark.geometry {
        case .arrow(let arrow):
            let dx = arrow.start.x - arrow.end.x, dy = arrow.start.y - arrow.end.y
            let length = max(1, hypot(dx, dy))
            center = CGPoint(x: arrow.start.x + dx / length * (r + 4), y: arrow.start.y + dy / length * (r + 4))
        case .ellipse(let box):
            let edge = CGPoint(x: box.midX - box.width / 2 * 0.7071, y: box.midY - box.height / 2 * 0.7071)
            center = CGPoint(x: edge.x - (r + 3) * 0.7071, y: edge.y - (r + 3) * 0.7071)
        case .rectangle(let box):
            center = CGPoint(x: box.minX - r - 2, y: box.minY - r - 2)
        case .text:
            return
        }
        center.x = min(max(center.x, frame.minX + r + 1), frame.maxX - r - 1)
        center.y = min(max(center.y, frame.minY + r + 1), frame.maxY - r - 1)
        let badge = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
        context.setFillColor(markStyle.color(.person))
        context.fillEllipse(in: badge)
        context.setStrokeColor(markStyle.edgeColor.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: badge)
        let font = NSFont.systemFont(ofSize: number < 10 ? 11 : 9, weight: .bold)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(number)", attributes: [.font: font, .foregroundColor: NSColor.white]))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        // The context runs y down; text is drawn y up, so it is flipped about its own baseline.
        context.textMatrix = .identity
        context.translateBy(x: center.x - bounds.midX, y: center.y + bounds.midY)
        context.scaleBy(x: 1, y: -1)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// `image` as a PNG whose DPI says `pointScale` pixels per point, as a macOS screenshot's does,
    /// so its card and its copies show it at the window's size.
    static func screenshotPNG(_ image: CGImage, pointScale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        let dpi = 72 * pointScale
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func png(_ image: CGImage, scale: CGFloat) -> Data? {
        var image = image
        if scale < 1 {
            let width = max(1, Int((CGFloat(image.width) * scale).rounded())), height = max(1, Int((CGFloat(image.height) * scale).rounded()))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = context.makeImage() else { return nil }
            image = scaled
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The part of the window round the new ink sent at full detail: as large as a reader takes
    /// without resizing at 2x, centred on the ink and kept inside the window, in fractions of it.
    private static func detailBox(around ink: [Mark], in frame: CGRect) -> CGRect? {
        let extent = ink.compactMap(\.shapeExtent).reduce(CGRect.null) { $0.union($1) }
        guard !extent.isNull else { return nil }
        let size = CGSize(width: min(frame.width, 784), height: min(frame.height, 560))
        var origin = CGPoint(x: extent.midX - size.width / 2, y: extent.midY - size.height / 2)
        origin.x = min(max(origin.x, frame.minX), frame.maxX - size.width)
        origin.y = min(max(origin.y, frame.minY), frame.maxY - size.height)
        return CGRect(x: (origin.x - frame.minX) / frame.width, y: (origin.y - frame.minY) / frame.height,
                      width: size.width / frame.width, height: size.height / frame.height)
    }
}
