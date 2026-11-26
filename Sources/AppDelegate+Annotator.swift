import AppKit

extension AppDelegate {
    /// The corner and the annotator hand each other the image, its frame and its flight.
    func connectAnnotator() {
        connectAgentMarks()
        thumbnail.onAnnotatorPrepare = { [weak self] shot, opening, frame, room in
            guard let self else { return }
            self.annotator.prepare(shot, opening: opening, in: frame, room: room)
            self.refreshDestinations(for: shot)
        }
        thumbnail.onAnnotatorRenamed = { [weak self] shot, opening in self?.annotator.renamed(to: shot, opening: opening) }
        annotator.onFrame = { [weak self] frame in self?.thumbnail.annotatorFrameMoved(frame) }
        thumbnail.onAnnotatorRefit = { [weak self] frame, room in self?.annotator.refit(in: frame, room: room) }
        annotator.onRefit = { [weak self] frame in self?.thumbnail.annotatorRefitted(frame) }
        thumbnail.onAnnotatorShow = { [weak self] watches in self?.annotator.show(watchesClickOutside: watches) }
        thumbnail.onAnnotatorLanded = { [weak self] in self?.annotator.landed() }
        thumbnail.onAnnotatorLifted = { [weak self] in self?.annotator.lifted() }
        thumbnail.annotatorBelow = { [weak self] in self?.annotator.spaceBelow ?? 0 }
        thumbnail.annotatorAbove = { [weak self] shot, wrap in self?.annotator.spaceAbove(for: shot, wrap: wrap) ?? 0 }
        thumbnail.annotatorMarks = { [weak self] in self?.annotator.editor.marks }
        thumbnail.annotatorTitle = { [weak self] key in self?.annotator.takeTitle(of: key) }
        thumbnail.onAnnotatorHide = { [weak self] hidden in self?.annotator.hide { hidden() } }
        thumbnail.onAnnotatorAbandon = { [weak self] in self?.annotator.abandon() }
        thumbnail.onAnnotatorPress = { [weak self] event, key in self?.annotator.take(event, for: key) }
    }
}
