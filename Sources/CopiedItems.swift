import AppKit

/// Marks and pins on the clipboard, in a pasteboard type of Vignette's own: as a drawing file holds
/// them, with the point and mark scales of the drawing they came from, so a paste keeps their places
/// in the screenshot's points and their sizes in drawing pt. Any app can write the type, so they go
/// through the same validator as a file's. Marks alone are written as version 1, so a build from
/// before pins still pastes them. With pins they are version 2, which such a build refuses, pasting
/// the plain text beside them as a note instead.
struct CopiedItems: Equatable {
    static let pasteboardType = NSPasteboard.PasteboardType(Identity.bundleID + ".marks")

    let pointScale: CGFloat
    let markScale: CGFloat
    let marks: [Mark]
    /// Each with its comments, and the number it had where it was copied, whose order a paste keeps.
    let pins: [Pin]

    init(pointScale: CGFloat, markScale: CGFloat = 1, marks: [Mark], pins: [Pin] = []) {
        self.pointScale = pointScale
        self.markScale = markScale
        self.marks = marks
        self.pins = pins
    }

    /// px per pt of the screen the marks' drawing was made on.
    var screenScale: CGFloat { pointScale / markScale }

    func encoded() throws -> Data {
        try DrawingJSON.encode(CopiedItemsRecord(version: pins.isEmpty ? Drawing.versionWithoutPins : Drawing.version,
                                                 pointScale: pointScale, markScale: markScale == 1 ? nil : markScale,
                                                 marks: marks.map(MarkRecord.init), pins: pins.isEmpty ? nil : pins.map(PinRecord.init)))
    }

    /// Nil when `data` is not copied items this build can read, or none of its marks and pins passes
    /// the validator. One that fails is dropped, with a log line, and pins past `Pin.maxCount` too.
    init?(data: Data) {
        guard let object = (try? DrawingJSON.object(from: data)) as? [String: Any],
              let version = DrawingJSON.wholeNumber(object["version"]), (1...Drawing.version).contains(version),
              let scale = DrawingJSON.number(object["pointScale"]), Drawing.pointScales.contains(scale),
              let markScale = object["markScale"] == nil ? 1 : DrawingJSON.number(object["markScale"]), Drawing.markScales.contains(markScale),
              let list = object["marks"] as? [Any], let pinList = object["pins"] == nil ? [] : object["pins"] as? [Any] else {
            Log.write("[paste] error the clipboard's marks are not ones this build reads")
            return nil
        }
        guard !list.isEmpty || !pinList.isEmpty else {
            Log.write("[paste] error the clipboard holds no marks and no pins")
            return nil
        }
        var marks: [Mark] = []
        for (index, item) in list.enumerated() {
            do { marks.append(try Mark(validating: item)) }
            catch { Log.write("[paste] dropped mark=\(index + 1): \(error)") }
        }
        var pins: [Pin] = []
        for (index, item) in pinList.enumerated() {
            do {
                guard pins.count < Pin.maxCount else { throw MarkProblem("a screenshot holds at most \(Pin.maxCount) pins") }
                pins.append(try Pin(validating: item))
            } catch { Log.write("[paste] dropped pin=\(index + 1): \(error)") }
        }
        guard !marks.isEmpty || !pins.isEmpty else { return nil }
        self.init(pointScale: scale, markScale: markScale, marks: marks, pins: pins)
    }
}
