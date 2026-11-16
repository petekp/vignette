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

    func testTheDrawnBadgeIsNoWiderThanTheFitMeasuresAndFoldsToTheLogoAndItsGlyph() {
        let tabs: [(agent: String, label: String, glyph: String?)] = ["claude", "codex", ""].map { ($0, Agent.label(for: $0), nil) }
            + [("claude", "Sent to vignette", "paperplane.fill"), ("codex", "Sent to release notes", "paperplane.fill"),
               ("claude", Agent.label(for: "claude") + " · Replied", "checkmark")]
        for tab in tabs {
            let fit = AgentBadgeFit.of(tab.label, size: size)
            let full = NSHostingView(rootView: AgentBadge(agent: tab.agent, label: tab.label, glyph: tab.glyph, size: size,
                                                          cardWidth: 400, foldDuration: 0)).fittingSize
            XCTAssertLessThanOrEqual(full.width, fit.fullWidth, tab.label)
            XCTAssertGreaterThan(full.width, fit.fullWidth - 2, tab.label)
            for cardWidth in [CGFloat(60), 94] {
                let folded = NSHostingView(rootView: AgentBadge(agent: tab.agent, label: tab.label, glyph: tab.glyph, size: size,
                                                                cardWidth: cardWidth, foldDuration: 0)).fittingSize
                let keepsGlyph = tab.glyph != nil && fit.keepsGlyph(cardWidth: cardWidth)
                XCTAssertEqual(folded.width, keepsGlyph ? fit.foldedWidthWithGlyph : size, accuracy: 0.5, "\(tab.label) at \(cardWidth)")
                XCTAssertEqual(folded.height, size, accuracy: 0.01, tab.label)
            }
        }
    }

    func testAFoldedTabKeepsItsGlyphOnlyWhileItStaysClearOfTheSelectionCircle() {
        let fit = AgentBadgeFit.of("Sent to vignette", size: size)
        let circleTrailingEdge = AgentBadgeFit.inset + size
        for width in stride(from: CGFloat(20), through: 240, by: 0.5) where fit.keepsGlyph(cardWidth: width) {
            XCTAssertGreaterThanOrEqual(width - AgentBadgeFit.inset - fit.foldedWidthWithGlyph, circleTrailingEdge + AgentBadgeFit.inset, "\(width)")
        }
        XCTAssertTrue(fit.keepsGlyph(cardWidth: 94), "a 188 pt card at the narrowest stack")
    }
}
