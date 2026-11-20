import Foundation

/// A child process a responder driver speaks to in JSON lines, one object a line each way. Lines
/// and the end reach the main thread; after `stop` nothing more does.
@MainActor
final class JSONLinesProcess {
    private let process = Process()
    private let input: FileHandle
    /// Writes go here: a picture is megabytes, and the pipe takes 64 KB at a time.
    private let writer = DispatchQueue(label: "vignette.live-responder.write")
    private let relay: Relay

    var pid: Int32 { process.processIdentifier }

    /// Starts `binary`. `onLine` gets each line of its output that is a JSON object, and `onEnd` its
    /// exit status once it ends on its own.
    init(binary: String, arguments: [String], environment: [String: String], folder: URL,
         onLine: @escaping @MainActor ([String: Any]) -> Void, onEnd: @escaping @MainActor (Int32) -> Void) throws {
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.currentDirectoryURL = folder
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        input = stdin.fileHandleForWriting
        // Writing to a process that has gone would otherwise end Vignette with SIGPIPE.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let relay = Relay(onLine: onLine, onEnd: onEnd)
        self.relay = relay
        let lines = LineReader { line in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
                    relay.onLine?(object)
                }
            }
        }
        // At the end of the output, Foundation calls a handler again and again with no data until it is removed.
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { lines.append(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { relay.errorTail = (relay.errorTail + data).suffix(2000) }
            }
        }
        process.terminationHandler = { ended in
            let status = ended.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { relay.onEnd?(status) } }
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try process.run()
    }

    /// A write that fails means the process has gone, which `onEnd` reports.
    func write(_ message: [String: Any]) {
        guard relay.onLine != nil, let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        let input = input
        writer.async {
            do {
                try input.write(contentsOf: data + Data("\n".utf8))
            } catch {
                Log.write("[live-ink] responder error write \(error.localizedDescription)")
            }
        }
    }

    /// Ends the process. Its lines and its end are not reported from now on.
    func stop() {
        relay.onLine = nil
        relay.onEnd = nil
        if process.isRunning { process.terminate() }
        let input = input
        writer.async { try? input.close() }
    }

    /// The last line of standard error, cut for the log and for words about why it ended.
    var lastErrorLine: String {
        String(decoding: relay.errorTail, as: UTF8.self).split(separator: "\n").last.map { String($0.prefix(200)) } ?? ""
    }
}

/// What the pipes' handlers reach, on the main thread.
private final class Relay: @unchecked Sendable {
    var onLine: (@MainActor ([String: Any]) -> Void)?
    var onEnd: (@MainActor (Int32) -> Void)?
    /// The last of the process's standard error, as bytes, since a read can end inside a character.
    var errorTail = Data()
    init(onLine: @escaping @MainActor ([String: Any]) -> Void, onEnd: @escaping @MainActor (Int32) -> Void) {
        self.onLine = onLine
        self.onEnd = onEnd
    }
}

/// Splits a pipe's data into lines, on the pipe's own queue.
private final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    private let line: (Data) -> Void

    init(line: @escaping (Data) -> Void) { self.line = line }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        let lines: [Data] = lock.withLock {
            buffer.append(data)
            var found: [Data] = []
            while let end = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                found.append(buffer[buffer.startIndex..<end])
                buffer.removeSubrange(buffer.startIndex...end)
            }
            return found
        }
        lines.filter { !$0.isEmpty }.forEach(line)
    }
}
