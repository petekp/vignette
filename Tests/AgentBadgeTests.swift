import SwiftUI
import XCTest

@MainActor
final class AgentBadgeTests: XCTestCase {
    let size: CGFloat = 19

    func testTheWordsShowOnlyWhenTheCapsuleFitsInsideTheCardClearOfTheSelectionCircle() {
        let fit = AgentBadgeFit.of("From Claude", size: size)
        let circleTrailingEdge = AgentBadgeFit.inset + size
        for width in stride(from: CGFloat(20), through: 240, by: 0.5) {
            for wasFolded in [false, true] where !fit.folds(cardWidth: width, wasFolded: wasFolded) {
                let capsuleLeadingEdge = width - AgentBadgeFit.inset - fit.fullWidth
                XCTAssertGreaterThanOrEqual(capsuleLeadingEdge, circleTrailingEdge + AgentBadgeFit.inset,
                                            "a badge on a \(width) pt card kept its words under the selection circle")
            }
        }
        XCTAssertTrue(fit.folds(cardWidth: 94, wasFolded: false), "a 188 pt card at the narrowest stack")
        XCTAssertFalse(fit.folds(cardWidth: 188, wasFolded: true), "a card as wide as the box")
    }

    func testAFoldedBadgeWaitsForRoomToSpareBeforeItUnfolds() {
        let fit = AgentBadgeFit.of("From Claude", size: size)
        let fits = fit.cardWidthForWords
        XCTAssertFalse(fit.folds(cardWidth: fits, wasFolded: false))
        XCTAssertTrue(fit.folds(cardWidth: fits, wasFolded: true))
        XCTAssertTrue(fit.folds(cardWidth: fits + AgentBadgeFit.hysteresis - 0.5, wasFolded: true))
        XCTAssertFalse(fit.folds(cardWidth: fits + AgentBadgeFit.hysteresis, wasFolded: true))
    }

    func testTheDrawnBadgeIsNoWiderThanTheFitMeasuresAndFoldsToACircle() {
        for agent in ["claude", "codex", ""] {
            let fit = AgentBadgeFit.of(Agent.label(for: agent), size: size)
            let full = NSHostingView(rootView: AgentBadge(agent: agent, size: size, cardWidth: 400, foldDuration: 0)).fittingSize
            XCTAssertLessThanOrEqual(full.width, fit.fullWidth, agent)
            XCTAssertGreaterThan(full.width, fit.fullWidth - 2, agent)
            let folded = NSHostingView(rootView: AgentBadge(agent: agent, size: size, cardWidth: 60, foldDuration: 0)).fittingSize
            XCTAssertEqual(folded.width, size, accuracy: 0.01, agent)
            XCTAssertEqual(folded.height, size, accuracy: 0.01, agent)
        }
    }
}
