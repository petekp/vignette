import Foundation

/// Where Done, Send and Copy Drawing render: one at a time, off the main thread, straight at the
/// output size. One rendering of the largest capture holds two bitmaps of about 85 MB, so two never
/// run at once.
final class RenderingQueue: @unchecked Sendable {
    static let shared = RenderingQueue()

    /// When a rendering runs. `first` goes ahead of every rendering that has not started: Done's
    /// clipboard is promised, and a paste in another app waits for it on this app's main thread.
    enum Order { case inTurn, first }

    private let queue = DispatchQueue(label: "vignette.rendering", qos: .userInitiated)
    // Guarded by `lock`. Every `render` adds one job and one block on `queue`, and a block runs
    // whichever job is next when it starts, so a `first` job overtakes the ones already waiting.
    private let lock = NSLock()
    private var firstJobs: [@Sendable () -> Void] = []
    private var jobs: [@Sendable () -> Void] = []

    /// Renders `drawing` over the image at `url` in `order`, and writes the PNG to `file` when one
    /// is given. Renderings of the same order run in the order asked. `style` must have been made on
    /// the main thread.
    func render(_ drawing: Drawing, imageAt url: URL, writingTo file: URL?, style: TextStyle, arrowhead: ArrowheadStyle,
                order: Order = .inTurn) -> PendingRendering {
        let pending = PendingRendering()
        let job: @Sendable () -> Void = { Self.run(drawing, imageAt: url, writingTo: file, style: style, arrowhead: arrowhead, into: pending) }
        lock.withLock { if order == .first { firstJobs.append(job) } else { jobs.append(job) } }
        queue.async { [self] in
            let next = lock.withLock { firstJobs.isEmpty ? jobs.removeFirst() : firstJobs.removeFirst() }
            next()
        }
        return pending
    }

    private static func run(_ drawing: Drawing, imageAt url: URL, writingTo file: URL?, style: TextStyle, arrowhead: ArrowheadStyle,
                            into pending: PendingRendering) {
        do {
            let png = try Rendering.png(of: drawing, imageAt: url, style: style, arrowhead: arrowhead)
            guard let file else { return pending.finish(png: png, file: nil, failure: nil) }
            do {
                try png.write(to: file, options: .atomic)
                pending.finish(png: png, file: file, failure: nil)
            } catch {
                pending.finish(png: png, file: nil, failure: .writeFailed("could not write \(file.lastPathComponent): \(error.localizedDescription)"))
            }
        } catch let failure as Rendering.Failure {
            pending.finish(png: nil, file: nil, failure: failure)
        } catch {
            pending.finish(png: nil, file: nil, failure: .writeFailed("\(error)"))
        }
    }
}

/// A rendering that has been asked for. It can be waited for from any thread, which is what a paste
/// that comes before it finishes does, or heard on the main thread.
final class PendingRendering: @unchecked Sendable {
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

    init() { done.enter() }

    func finish(png: Data?, file: URL?, failure: Rendering.Failure?) {
        lock.lock()
        guard output == nil else { lock.unlock(); return }
        output = Output(png: png, file: file, failure: failure)
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
