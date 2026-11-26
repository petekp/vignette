import AppKit

extension AppDelegate {
    /// Connects stored drawings before request recovery or the watcher can update cards.
    func startDrawings() {
        thumbnail.drawings = drawings
        drawings.open = annotator.editor
        drawings.onChange = { [weak self] key, drawing in self?.thumbnail.setDrawing(drawing, for: key) }
        annotator.onDrawing = { [weak self] drawing, message, history, reason in
            self?.drawings.handOver(drawing, message: message, history: history, reason: reason)
        }
        annotator.onMessage = { [weak self] message, drawing, history in self?.drawings.keepMessage(message, for: drawing, history: history) }
        annotator.storedHistory = { [weak self] key, pixels, drawing in
            self?.drawings.history(of: key, pixels: pixels, drawing: drawing) ?? EditorHistory()
        }
        annotator.storedNumbering = { [weak self] key, pixels in self?.drawings.numbering(of: key, pixels: pixels) }
        annotator.storedMessage = { [weak self] key, pixels in self?.drawings.message(of: key, pixels: pixels) ?? "" }
        drawings.onWriteFailed = { [weak self] key in self?.thumbnail.showNotSaved(Screenshot(key: key)) }
    }

    /// The screen an agent's new drawing is sized for: the main screen, the best guess with no
    /// annotator open.
    static var newDrawingScreen: DrawingScreen { DrawingScreen(NSScreen.main ?? NSScreen.screens[0]) }

    /// Agents' marks and pins joining a screenshot's drawing: the one open in the editor, or the stored
    /// one. `done` answers once the drawing is written, with how many joined it. A new drawing is
    /// sized for the main screen, the best guess with no annotator open, by `rule`.
    func addMarks(_ additions: AgentAdditions, to key: ScreenshotKey, rule: MarkScaleRule,
                  done: @escaping (Result<Drawings.Joined, Drawings.Failure>) -> Void) {
        // A turn later, so callers can set their own state after asking.
        Task {
            do {
                done(.success(try drawings.add(additions, to: key, style: settings.data.ui.textStyle,
                                               newScreen: Self.newDrawingScreen, rule: rule)))
            } catch let failure as Drawings.Failure {
                done(.failure(failure))
            } catch {
                done(.failure(Drawings.Failure(code: .writeFailed, description: "\(error)")))
            }
        }
    }
}
