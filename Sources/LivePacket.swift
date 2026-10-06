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
        let text: String
        /// In fractions of the picture, from its top-left corner.
        let box: CGRect
        /// Vision's reading, which gives the box of a part of the line. Only read on the main thread
        /// after the packet is built.
        let recognized: VNRecognizedText
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
    /// A part of the window round the ink at full detail, for a window too large to read whole after
    /// the reader's resize, with its rect in fractions of the picture.
    let detail: (png: Data, box: CGRect)?
    /// Says whether the window's text is what it was in an earlier packet.
    var textSignature: String { lines.map(\.text).joined(separator: "\n") }

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

    /// The most text lines a packet carries, and the longest line, in characters.
    static let maxLines = 300
    static let maxLineLength = 200

    /// The window under `point`, in global top-left points, captured and read, or the window `id`
    /// names while it is on screen, whatever covers it. `ink` is every mark of the person's to draw
    /// into the picture, in global top-left points at 1 px per pt.
    /// `glanced` is called off the main thread with the window's `Glance` as soon as it is known,
    /// before the packet is.
    @MainActor
    static func build(at point: CGPoint, window id: CGWindowID? = nil, ink: [Mark], style: TextStyle,
                      markStyle: MarkStyle, glanced: (@Sendable (Glance) -> Void)? = nil) async throws -> LivePacket {
        let started = Date()
        guard CGPreflightScreenCaptureAccess() else {
            throw Failure(reason: "Live ink needs Screen Recording permission to see the screen.", detail: "screen-recording")
        }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw Failure(reason: "Vignette couldn't see the screen.", detail: "shareable content: \(error.localizedDescription)")
        }
        let named = id.flatMap { id in content.windows.contains { $0.windowID == id } ? (id: id, frame: CGRect.null) : nil }
        let target = named ?? window(under: point)
        let filter: SCContentFilter
        let frame: CGRect
        var app: String?, title: String?, pid: pid_t?
        if let target, let window = content.windows.first(where: { $0.windowID == target.id }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
            frame = window.frame
            app = window.owningApplication?.applicationName
            title = window.title
            pid = window.owningApplication?.processID
        } else if let display = content.displays.first(where: { $0.frame.contains(point) }) ?? content.displays.first {
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            frame = display.frame
        } else {
            throw Failure(reason: "Vignette couldn't see the screen.", detail: "no window or display")
        }
        let primaryHeight = StateReport.primaryHeight
        let scale = NSScreen.screens.first { screen in
            let frame = screen.frame
            return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height).contains(point)
        }?.backingScaleFactor ?? 2
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((frame.width * scale).rounded()))
        configuration.height = max(1, Int((frame.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let capture: CGImage
        do {
            capture = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw Failure(reason: "Vignette couldn't capture the window.", detail: "capture: \(error.localizedDescription)")
        }
        let captured = Date()
        // Each Accessibility call may wait out its 0.1 s timeout, and a web page takes many, so the
        // page is looked for while the text is read.
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
            return try assemble(capture, frame: frame, ink: ink, style: style, markStyle: markStyle)
        }.value
        let page = await found.value
        let ms = { (date: Date) in Int(date.timeIntervalSince(started) * 1000) }
        Log.write("[live-ink] looked ms capture=\(ms(captured)) page=\(ms(page.at)) read=\(ms(assembled.at))")
        return LivePacket(frame: frame, windowID: target?.id, app: app, title: title, location: page.page?.location, page: page.page?.area,
                          lines: assembled.lines, picture: assembled.picture, detail: assembled.detail)
    }

    /// What `assemble` makes, and when it was done. Unchecked for the packet's reason: its lines'
    /// readings are read only on the main thread once the packet is built.
    private struct Assembled: @unchecked Sendable {
        let lines: [Line]
        let picture: Data
        let detail: (png: Data, box: CGRect)?
        let at: Date
    }

    /// Off the main thread: reads the text, draws the ink in, and sizes the picture for the reader.
    private static func assemble(_ capture: CGImage, frame: CGRect, ink: [Mark], style: TextStyle, markStyle: MarkStyle) throws -> Assembled {
        let lines = read(capture)
        let pixels = CGSize(width: capture.width, height: capture.height)
        guard let inked = draw(ink, on: capture, frame: frame, style: style, markStyle: markStyle) else {
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
        return Assembled(lines: lines, picture: picture, detail: detail, at: Date())
    }

    /// The text JSON of an ask: `freshPicture` false for a follow-up that sends no picture, whose text
    /// lines are the ones sent with the picture before.
    func message(note: String, ink: [Mark], new: Set<Mark.ID>, freshPicture: Bool) -> String {
        var json: [String: Any] = [:]
        if let app { json["app"] = app }
        if let title, !title.isEmpty { json["window"] = title }
        if let location { json["location"] = location }
        json["note"] = note
        json["ink"] = ink.compactMap { mark -> [String: Any]? in
            guard let extent = mark.shapeExtent else { return nil }
            var item: [String: Any] = ["kind": mark.kind == .ellipse ? "circle" : mark.kind.rawValue, "box": fractions(extent),
                                       "new": new.contains(mark.id)]
            if case .arrow(let arrow) = mark.geometry {
                item["from"] = fractions(arrow.start)
                item["to"] = fractions(arrow.end)
            }
            return item
        }
        if freshPicture {
            json["text"] = lines.map { ["id": $0.id, "text": $0.text, "box": Self.rounded($0.box)] as [String: Any] }
            if let detail { json["detail"] = ["box": Self.rounded(detail.box), "about": "the second picture is this part at full detail"] }
        } else {
            json["picture"] = "the same as the last picture; the text lines are as sent with it"
        }
        let data = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// `rect`, in global top-left points, in fractions of the picture.
    func fractions(_ rect: CGRect) -> [NSDecimalNumber] {
        Self.rounded(CGRect(x: (rect.minX - frame.minX) / frame.width, y: (rect.minY - frame.minY) / frame.height,
                            width: rect.width / frame.width, height: rect.height / frame.height))
    }

    func fractions(_ point: CGPoint) -> [NSDecimalNumber] {
        [(point.x - frame.minX) / frame.width, (point.y - frame.minY) / frame.height].map(Self.rounded)
    }

    /// A rect in fractions of the picture, in global top-left points.
    func global(_ fractions: CGRect) -> CGRect {
        CGRect(x: frame.minX + fractions.minX * frame.width, y: frame.minY + fractions.minY * frame.height,
               width: fractions.width * frame.width, height: fractions.height * frame.height)
    }

    static func rounded(_ rect: CGRect) -> [NSDecimalNumber] {
        [rect.minX, rect.minY, rect.width, rect.height].map(rounded)
    }

    /// Three decimals, written as such: `JSONSerialization` writes a `Double` in full, so 0.235 went
    /// as 0.23499999999999999, which the reader pays for in tokens.
    static func rounded(_ value: CGFloat) -> NSDecimalNumber {
        NSDecimalNumber(string: String(format: "%.3f", Double(value)))
    }

    // MARK: Pieces

    /// The topmost window under `point` that is not Vignette's, from the window server's list,
    /// which runs front to back. The Dock, the menu bar and menus are left out by their level: the
    /// Dock has a window over the whole screen at its level, and it was taken for the window under
    /// the ink.
    @MainActor
    static func window(under point: CGPoint) -> (id: CGWindowID, frame: CGRect)? {
        let own = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in windows {
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != own,
                  let level = info[kCGWindowLayer as String] as? Int, level < Int(CGWindowLevelForKey(.dockWindow)),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 40, frame.height > 40, frame.contains(point) else { continue }
            return (id, frame)
        }
        return nil
    }

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
        return ordered.prefix(maxLines).enumerated().map { index, item in
            Line(id: "t\(index + 1)", text: String(item.0.string.prefix(maxLineLength)), box: item.1, recognized: item.0)
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

    /// The capture with `ink` drawn over it, at the capture's own size.
    private static func draw(_ ink: [Mark], on capture: CGImage, frame: CGRect, style: TextStyle, markStyle: MarkStyle) -> CGImage? {
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
        return context.makeImage()
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

    /// The window's document or page, from Accessibility: its `AXDocument`, or the `AXURL` of a web
    /// area within a few levels of it. Nil when the app gives neither, or without the permission.
    /// Where a window's content comes from, and a browser's page area.
    struct Page {
        var location: String?
        var area: CGRect?
    }

    /// The window at `frame`'s document or page, from Accessibility.
    private static func page(pid: pid_t, frame: CGRect) -> Page? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        let window = windows.first { window in
            guard let position = attribute(window, kAXPositionAttribute), let size = attribute(window, kAXSizeAttribute) else { return false }
            var origin = CGPoint.zero, extent = CGSize.zero
            AXValueGetValue(position as! AXValue, .cgPoint, &origin)
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
            return abs(origin.x - frame.minX) < 2 && abs(origin.y - frame.minY) < 2 && abs(extent.width - frame.width) < 2
        }
        guard let window else { return nil }
        let document = (attribute(window, kAXDocumentAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
        var queue: [(AXUIElement, Int)] = [(window, 0)], visited = 0
        while !queue.isEmpty, visited < 200 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if attribute(element, kAXRoleAttribute) as? String == "AXWebArea" {
                let url = (attribute(element, kAXURLAttribute) as? URL)?.absoluteString
                return Page(location: url ?? document, area: area(of: element)?.intersection(frame))
            }
            guard depth < 8, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            queue += children.map { ($0, depth + 1) }
        }
        return document.map { Page(location: $0) }
    }

    /// An element's frame, in global top-left points.
    private static func area(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return extent.width > 0 && extent.height > 0 ? CGRect(origin: origin, size: extent) : nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
