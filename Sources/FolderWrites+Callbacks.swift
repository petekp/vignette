import AppKit

extension FolderWrites {
    struct Callbacks {
        /// The watch folder, as AppDelegate reads it from the settings.
        var folder: () -> URL = { FileManager.default.temporaryDirectory }
        /// Shows an added file's card, or opens it in the editor when `annotate` (AppDelegate.present).
        var present: (Screenshot, _ annotate: Bool) -> Void = { _, _ in }
        /// Shows a published reply's card. A reply never goes through `present`, which treats a file as a capture.
        var showCard: (Screenshot) -> Void = { _ in }
        /// Agents' marks joining the screenshot's drawing; answers with how many joined.
        var joinMarks: ([AgentMark], _ agent: String?, ScreenshotKey, @escaping (Result<Int, Drawings.Failure>) -> Void) -> Void = { _, _, _, done in
            done(.failure(Drawings.Failure(code: .writeFailed, description: "nothing stores drawings")))
        }
        /// The name the session list gives a session, on the main thread, nil when it has none
        /// (`SessionListing.senderName`).
        var senderName: (AgentAddress, @escaping @MainActor (String?) -> Void) -> Void = { _, answer in answer(nil) }
        /// The file's sender was recorded or removed, after its card may have been made.
        var senderRecorded: (Screenshot) -> Void = { _ in }
        /// A screenshot's drawing as the editor would open it.
        var storedDrawing: (ScreenshotKey) -> Drawing? = { _ in nil }
        var removeCards: ([Screenshot]) -> Void = { _ in }
        var removeDrawings: ([ScreenshotKey], _ observedAt: TimeInterval) -> Void = { _, _ in }
        var fileRemoved: (Screenshot) -> Void = { _ in }
        /// Files renamed inside the folder: their cards keep their place and selection and take the new file.
        var renameCards: ([Rename]) -> Void = { _ in }
        /// Files renamed inside the folder: their stored drawings, and the one open in the editor, follow.
        var renameDrawings: ([Rename]) -> Void = { _ in }
        /// Files renamed inside the folder: the request and reply records that name them follow.
        var renameRequests: ([Rename]) -> Void = { _ in }
        /// ScreenshotRequests.isVisible: whether every listing shows a file by that name.
        var isVisible: (URL) -> Bool = { _ in true }
        /// Drawings.sweep: removes the drawings of files a listing confirms absent.
        var sweepDrawings: (ScreenshotWatcher.Inventory) -> Void = { _ in }
        /// ScreenshotRequests.reconcile: marks published replies a listing confirms absent as removed.
        var reconcileRequests: (ScreenshotWatcher.Inventory) -> Void = { _ in }
        var rescan: (_ reason: String) -> Void = { _ in }
    }
}
