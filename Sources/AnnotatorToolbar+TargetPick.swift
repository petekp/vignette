import SwiftUI

// MARK: A pick from the target's menu

extension AnnotatorToolbar {
    /// A pick from the target's menu applies to the image the menu opened on (`Model.targetMenuImage`),
    /// and is dropped once another image opened or the bar left.
    func takeTargetMenuPicks() {
        targetMenuActions.onPick = { [weak self] destination, menuLine in
            let image = self?.model.targetMenuImage
            // A turn later, once the menu's own event loop has ended.
            DispatchQueue.main.async {
                guard let self else { return }
                Log.write("[send] picked \(destination.address.description) project=\(destination.detail) role=\(destination.role ?? "none")")
                if let menuLine { Log.write(menuLine) }
                guard self.model.shown, self.model.imageNumber == image else { return Log.write("[send] pick dropped") }
                // Before the pick changes the offer, which may offer the field the keys as on open.
                self.onPick?()
                withAnimation(Anim.spring(0.35 * Settings.shared.motionScale)) { self.model.pick(destination) }
                self.typeAfterPick()
            }
        }
    }
}
