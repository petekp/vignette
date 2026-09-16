import Foundation

/// Appends to ~/Library/Logs/<app name>.log. Simpler to read during development than the unified log.
/// Grammar: one event per line, `HH:mm:ss.SSS [tag] …`; the launch line also carries the date.
/// Embedded newlines are flattened so a line is always one event. When the file passes
/// `rotateAtBytes` it moves to `<name>.log.1`, replacing the previous one, so the log never
/// grows without bound and the last few thousand lines are always at hand.
enum Log {
    static let url = Identity.logURL
    static let rotateAtBytes = 5 << 20
    private static let queue = DispatchQueue(label: "shotnote.log")
    private static let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
    private static let dateStamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()

    static func write(_ message: String) {
        let now = Date()
        queue.async { append("\(stamp.string(from: now)) \(oneLine(message))\n", to: url, rotateAt: rotateAtBytes) }
    }

    /// The first line of a launch: the date, so a log spanning days can be read.
    static func writeLaunch(_ message: String) {
        let now = Date()
        queue.async { append("\(stamp.string(from: now)) \(oneLine(message)) date=\(dateStamp.string(from: now))\n", to: url, rotateAt: rotateAtBytes) }
    }

    /// Newlines and carriage returns become spaces; error descriptions and eval results carry them.
    static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }

    /// Appends `line` to `file`, first rotating it to `file.1` once it is `rotateAt` bytes or more.
    static func append(_ line: String, to file: URL, rotateAt: Int) {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size >= rotateAt {
            let previous = file.appendingPathExtension("1")
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: file, to: previous)
        }
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }
}
