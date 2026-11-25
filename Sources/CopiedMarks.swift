import AppKit

/// Marks on the clipboard, in a pasteboard type of Vignette's own: the marks as a drawing file holds
/// them, and the point and mark scales of the drawing they came from, so a paste keeps their places
/// in the screenshot's points and their sizes in drawing pt. Any app can write the type, so the marks
/// go through the same validator as a file's.
struct CopiedMarks: Equatable {
    static let pasteboardType = NSPasteboard.PasteboardType(Identity.bundleID + ".marks")

    let pointScale: CGFloat
    let markScale: CGFloat
    let marks: [Mark]

    init(pointScale: CGFloat, markScale: CGFloat = 1, marks: [Mark]) {
        self.pointScale = pointScale
        self.markScale = markScale
        self.marks = marks
    }

    /// px per pt of the screen the marks' drawing was made on.
    var screenScale: CGFloat { pointScale / markScale }

    func encoded() throws -> Data {
        try DrawingJSON.encode(CopiedMarksRecord(version: Drawing.versionWithoutPins, pointScale: pointScale,
                                                 markScale: markScale == 1 ? nil : markScale, marks: marks.map(MarkRecord.init)))
    }

    /// Nil when `data` is not copied marks this build can read, or none of its marks passes the
    /// validator. A mark that fails is dropped, with a log line.
    init?(data: Data) {
        guard let object = (try? DrawingJSON.object(from: data)) as? [String: Any],
              let version = DrawingJSON.wholeNumber(object["version"]), (1...Drawing.version).contains(version),
              let scale = DrawingJSON.number(object["pointScale"]), Drawing.pointScales.contains(scale),
              let markScale = object["markScale"] == nil ? 1 : DrawingJSON.number(object["markScale"]), Drawing.markScales.contains(markScale),
              let list = object["marks"] as? [Any] else {
            Log.write("[paste] error the clipboard's marks are not ones this build reads")
            return nil
        }
        guard !list.isEmpty else {
            Log.write("[paste] error the clipboard's marks list is empty")
            return nil
        }
        var marks: [Mark] = []
        for (index, item) in list.enumerated() {
            do { marks.append(try Mark(validating: item)) }
            catch { Log.write("[paste] dropped mark=\(index + 1): \(error)") }
        }
        guard !marks.isEmpty else { return nil }
        self.init(pointScale: scale, markScale: markScale, marks: marks)
    }
}
