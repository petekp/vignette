import CoreGraphics
import Foundation

// MARK: - The file's encoding

/// A mark as a drawing file and a paste write it: flat fields, without the ones its type does not
/// use, and without `bend`, `via`, `wrap`, `agent` and `agentName` at their defaults. A text's `size`
/// is always written. A mark's colour is not: it follows from `agent`.
struct MarkRecord: Encodable {
    let type: MarkKind
    let x: CGFloat
    let y: CGFloat
    var w: CGFloat?
    var h: CGFloat?
    var x2: CGFloat?
    var y2: CGFloat?
    var bend: CGFloat?
    var via: [[CGFloat]]?
    var text: String?
    var wrap: CGFloat?
    var size: CGFloat?
    var agent: Bool?
    var agentName: String?

    init(_ mark: Mark) {
        switch mark.geometry {
        case .rectangle(let frame), .ellipse(let frame):
            x = frame.minX
            y = frame.minY
            w = frame.width
            h = frame.height
        case .arrow(let arrow):
            x = arrow.start.x
            y = arrow.start.y
            x2 = arrow.end.x
            y2 = arrow.end.y
            bend = arrow.bend == 0 ? nil : arrow.bend
            via = arrow.via.isEmpty ? nil : arrow.via.map { [$0.x, $0.y] }
        case .text(let text):
            x = text.origin.x
            y = text.origin.y
            self.text = text.text
            wrap = text.wrap
            size = text.size
        }
        type = mark.kind
        agent = mark.agent ? true : nil
        agentName = mark.agentName
    }
}

struct DrawingRecord: Encodable {
    let version: Int
    let key: String
    let pixels: [Int]
    let pointScale: CGFloat
    /// Left out at 1.
    let markScale: CGFloat?
    let marks: [MarkRecord]
    /// Left out with no pins.
    let pins: [PinRecord]?
    /// Left out at 1.
    let nextPin: Int?
    /// Each as [x, y, w, h] in px. Left out when there are none.
    let pieceNumbers: [[CGFloat]]?
}

struct CopiedMarksRecord: Encodable {
    let version: Int
    let pointScale: CGFloat
    /// Left out at 1.
    let markScale: CGFloat?
    let marks: [MarkRecord]
}

/// Reading and writing the JSON that drawings and copied marks travel in.
enum DrawingJSON {
    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// The decoded object. JSONSerialization refuses a whole document over one number past a Double's
    /// range, such as `1e999`; such a number is read as null, so the validator drops only its mark.
    static func object(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: nullingOverflow(data))
    }

    /// A finite number JSONSerialization decoded, or nil for anything else. It hands `true` over as
    /// an NSNumber, which `as? Double` would read as 1.
    static func number(_ raw: Any?) -> CGFloat? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    /// Rectangles written as [x, y, w, h] with a width and a height above 0. Anything else in the list
    /// is left out, and anything but a list gives none.
    static func rects(_ raw: Any?) -> [CGRect] {
        ((raw as? [Any]) ?? []).compactMap { item in
            guard let values = item as? [Any], values.count == 4 else { return nil }
            let numbers = values.compactMap(number)
            guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
            return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }
    }

    /// A whole number JSONSerialization decoded, or nil for anything else.
    static func wholeNumber(_ raw: Any?) -> Int? {
        guard let number = number(raw), number == number.rounded(), abs(number) < 1e15 else { return nil }
        return Int(number)
    }

    /// `data` with every number outside strings that a Double cannot hold replaced by `null`.
    static func nullingOverflow(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var out = Data(capacity: bytes.count)
        var inString = false, escaped = false
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            if inString {
                if escaped { escaped = false } else if byte == UInt8(ascii: "\\") { escaped = true } else if byte == UInt8(ascii: "\"") { inString = false }
            } else if byte == UInt8(ascii: "\"") {
                inString = true
            } else if byte == UInt8(ascii: "-") || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
                var end = i + 1
                while end < bytes.count, "0123456789+-.eE".utf8.contains(bytes[end]) { end += 1 }
                let token = bytes[i..<end]
                if let value = Double(String(decoding: token, as: UTF8.self)), value.isInfinite {
                    out.append(contentsOf: "null".utf8)
                } else {
                    out.append(contentsOf: token)
                }
                i = end
                continue
            }
            out.append(byte)
            i += 1
        }
        return out
    }
}
