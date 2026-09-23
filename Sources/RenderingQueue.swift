import Foundation

/// Where Done, Send and Copy Drawing render: one at a time, off the main thread, straight at the
/// output size. One rendering of the largest capture holds two bitmaps of about 85 MB, so two never
/// run at once.
final class RenderingQueue: Sendable {
    static let shared = RenderingQueue()

    private let queue = DispatchQueue(label: "vignette.rendering", qos: .userInitiated)

    /// Renders `drawing` over the image at `url` after every rendering asked for before it, and
    /// writes the PNG to `file` when one is given. `style` must have been made on the main thread.
    func render(_ drawing: Drawing, imageAt url: URL, writingTo file: URL?, style: TextStyle, arrowhead: ArrowheadStyle) -> PendingRendering {
        let pending = PendingRendering()
        queue.async {
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
        return pending
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
