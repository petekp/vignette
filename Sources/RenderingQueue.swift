import Foundation
import Darwin

/// Where Done, Send and Copy Drawing render: one at a time, off the main thread, straight at the
/// output size. One rendering of the largest capture holds two bitmaps of about 85 MB, so two never
/// run at once.
final class RenderingQueue: @unchecked Sendable {
    static let shared = RenderingQueue()

    /// When a rendering runs. `first` goes ahead of every rendering that has not started: Done's
    /// clipboard is promised, and a paste in another app waits for it on this app's main thread.
    enum Order { case inTurn, first }
    enum Output: Equatable { case bytes, file }

    private let queue = DispatchQueue(label: "vignette.rendering", qos: .userInitiated)
    // Guarded by `lock`. Every `render` adds one job and one block on `queue`, and a block runs
    // whichever job is next when it starts, so a `first` job overtakes the ones already waiting.
    private let lock = NSLock()
    private var firstJobs: [@Sendable () -> Void] = []
    private var jobs: [@Sendable () -> Void] = []

    /// File results have distinct paths beside their source and remain until the person deletes them.
    /// `style` must have been made on the main thread. Results of the same order run in request order.
    func render(_ drawing: Drawing, imageAt url: URL, output: Output, style: TextStyle, markStyle: MarkStyle,
                order: Order = .inTurn) -> PendingRendering {
        let file = output == .file ? Self.resultURL(beside: url) : nil
        let pending = PendingRendering(file: file)
        if output == .file, file == nil {
            pending.finish(png: nil, failure: .writeFailed("could not name a rendering beside \(url.lastPathComponent)"))
            return pending
        }
        let job: @Sendable () -> Void = { Self.run(drawing, imageAt: url, style: style, markStyle: markStyle, into: pending) }
        lock.withLock { if order == .first { firstJobs.append(job) } else { jobs.append(job) } }
        queue.async { [self] in
            let next = lock.withLock { firstJobs.isEmpty ? jobs.removeFirst() : firstJobs.removeFirst() }
            next()
        }
        return pending
    }

    private static func resultURL(beside source: URL) -> URL? {
        let folder = source.deletingLastPathComponent()
        let nameLimit = pathconf(folder.path, _PC_NAME_MAX)
        let pathLimit = pathconf(folder.path, _PC_PATH_MAX)
        let suffix = "-\(UUID().uuidString.lowercased())\(Config.annotatedSuffix).png"
        var result = folder.appendingPathComponent(suffix)
        guard let pathBytes = result.withUnsafeFileSystemRepresentation({ path in path.map { strlen($0) } }) else { return nil }
        var longestPathBytes = pathBytes
        // Foundation's symlink resolution keeps /var aliases; realpath counts their full spelling.
        if let physicalFolder = realpath(folder.path, nil) {
            let bytes = strlen(physicalFolder)
            longestPathBytes = max(pathBytes, bytes + (bytes == 1 ? 0 : 1) + suffix.utf8.count)
            free(physicalFolder)
        }
        // PATH_MAX includes the terminating NUL; the URL's bytes include the directory separator.
        let available = min((nameLimit > 0 ? Int(nameLimit) : Int(NAME_MAX)) - suffix.utf8.count,
                            (pathLimit > 0 ? Int(pathLimit) : Int(PATH_MAX)) - 1 - longestPathBytes)
        guard available >= 0 else { return nil }
        var prefix = ""
        for character in source.deletingPathExtension().lastPathComponent {
            let next = prefix + String(character)
            let candidate = folder.appendingPathComponent(next + suffix)
            guard let bytes = candidate.withUnsafeFileSystemRepresentation({ path in path.map { strlen($0) } }),
                  bytes - pathBytes <= available else { break }
            prefix = next
            result = candidate
        }
        return result
    }

    private static func run(_ drawing: Drawing, imageAt url: URL, style: TextStyle, markStyle: MarkStyle,
                            into pending: PendingRendering) {
        do {
            let png = try Rendering.png(of: drawing, imageAt: url, style: style, markStyle: markStyle)
            guard let file = pending.file else { return pending.finish(png: png, failure: nil) }
            do {
                try png.write(to: file, options: .atomic)
                pending.finish(png: png, failure: nil)
            } catch {
                pending.finish(png: png, failure: .writeFailed("could not write \(file.lastPathComponent): \(error.localizedDescription)"))
            }
        } catch let failure as Rendering.Failure {
            pending.finish(png: nil, failure: failure)
        } catch {
            pending.finish(png: nil, failure: .writeFailed("\(error)"))
        }
    }
}

/// A rendering that has been asked for. It can be waited for from any thread, which is what a paste
/// that comes before it finishes does, or heard on the main thread.
final class PendingRendering: @unchecked Sendable {
    let file: URL?
    /// What a rendering left: the PNG when it rendered, the file when it was also written, and why
    /// either did not happen. A PNG with a failure is a rendering whose file could not be written.
    struct Output {
        let png: Data?
        let file: URL?
        let failure: Rendering.Failure?
    }

    // `output` is written once, under `lock`, before `done` is signalled.
    private let lock = NSLock()
    private let done = DispatchGroup()
    private var output: Output?

    init(file: URL? = nil) {
        self.file = file
        done.enter()
    }

    func finish(png: Data?, failure: Rendering.Failure?) {
        lock.lock()
        guard output == nil else { lock.unlock(); return }
        output = Output(png: png, file: png != nil && failure == nil ? file : nil, failure: failure)
        lock.unlock()
        done.leave()
    }

    /// The output once the rendering is done, or nil when it is not done within `timeout`.
    func wait(timeout: TimeInterval) -> Output? {
        guard done.wait(timeout: .now() + timeout) == .success else { return nil }
        lock.lock(); defer { lock.unlock() }
        return output
    }

    /// Calls `handler` on the main thread once the rendering is done.
    func whenDone(_ handler: @escaping @MainActor @Sendable (Output) -> Void) {
        done.notify(queue: .main) { [self] in
            lock.lock()
            let output = self.output
            lock.unlock()
            guard let output else { return }
            MainActor.assumeIsolated { handler(output) }
        }
    }
}
