import Foundation

extension DrawingStore {
    /// A file's top level, checked; its marks are checked one at a time by `read`.
    struct Stored {
        let key: String
        let pixels: PixelSize
        let pointScale: CGFloat
        let markScale: CGFloat
        let marks: [Any]
        /// Empty in a file with no pins; checked one at a time by `Pin.read`.
        let pins: [Any]
        /// The file's `nextPin`, unchecked, or nil when it has none.
        let nextPin: Any?
        /// What was typed in the message field for the screenshot, or "".
        let message: String
        /// The whole file, as parsed.
        let object: [String: Any]
    }

    enum Contents {
        case missing
        case unreadable(String)
        case invalid(String)
        case newer(Int)
        case stored(Stored)
    }

    func contents(of url: URL) -> Contents {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { return .unreadable(error.localizedDescription) }
        let object: [String: Any]
        do {
            guard let decoded = try DrawingJSON.object(from: data) as? [String: Any] else { return .invalid("the top level is not an object") }
            object = decoded
        } catch {
            // The debug description says where parsing stopped; the localized one says only that it did.
            return .invalid((error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? "not JSON")
        }
        guard let version = DrawingJSON.wholeNumber(object["version"]), version >= 1 else {
            return .invalid("version must be a whole number from 1")
        }
        if version > Drawing.version { return .newer(version) }
        guard let key = object["key"] as? String else { return .invalid("key must be a string") }
        guard let pixels = object["pixels"] as? [Any], pixels.count == 2,
              let width = DrawingJSON.wholeNumber(pixels[0]), let height = DrawingJSON.wholeNumber(pixels[1]),
              width > 0, height > 0 else {
            return .invalid("pixels must be two whole numbers above 0")
        }
        guard let pointScale = DrawingJSON.number(object["pointScale"]), Drawing.pointScales.contains(pointScale) else {
            let range = Drawing.pointScales
            return .invalid("pointScale must be a number from \(String(format: "%g", range.lowerBound)) to \(String(format: "%g", range.upperBound))")
        }
        let markScale = object["markScale"] == nil ? 1 : DrawingJSON.number(object["markScale"])
        guard let markScale, Drawing.markScales.contains(markScale) else {
            let range = Drawing.markScales
            return .invalid("markScale must be a number from \(String(format: "%g", range.lowerBound)) to \(String(format: "%g", range.upperBound))")
        }
        guard let marks = object["marks"] as? [Any] else { return .invalid("marks must be a list") }
        // A file written before pins were kept has none.
        guard let pins = object["pins"] == nil ? [] : object["pins"] as? [Any] else { return .invalid("pins must be a list") }
        // A file written before the message was kept has none.
        let message = (object["message"] as? String).map { String($0.prefix(MarkFields.maxTextLength)) } ?? ""
        return .stored(Stored(key: key, pixels: PixelSize(width: width, height: height), pointScale: pointScale, markScale: markScale,
                              marks: marks, pins: pins, nextPin: object["nextPin"], message: message, object: object))
    }
}
