import CoreGraphics
import Foundation

/// The editor's sizes and timings that a person tunes by feel, given at open from the tweaks.
/// Sizes are in screen pt unless they say otherwise; `standard` holds the numbers `docs/editor.md`
/// gives.
struct EditorMetrics: Equatable {
    /// How far a press travels before it is a drag.
    var dragDistance: CGFloat
    /// Added to a stroke's half-width on screen to make its hit band.
    var hitMargin: CGFloat
    /// A corner handle's hit area: a square this wide, centred on the corner.
    var cornerHitSize: CGFloat
    /// An edge handle's hit area: a strip this wide along the whole side.
    var edgeHitSize: CGFloat
    /// A mark shorter than this along an axis has its handles' hit areas outside it on that axis.
    var smallSide: CGFloat
    /// The drawn corner square.
    var handleSize: CGFloat
    /// An arrow dot's drawn radius and its hit radius.
    var dotRadius: CGFloat
    var dotHitRadius: CGFloat
    /// A new rectangle's shortest side and a new arrow's shortest length.
    var smallestRectangle: CGFloat
    var shortestArrow: CGFloat
    /// A Text tool press becomes a wrap-width drag after this wait, in seconds, and this much
    /// sideways travel.
    var textDragDelay: TimeInterval
    var textDragDistance: CGFloat
    /// The size a new text starts at, typed or pasted, in pt.
    var newTextSize: CGFloat
    /// The selection outline's whole width on screen, its light edge included. It runs this far
    /// outside a mark's ink, so the mark's colour shows.
    var selectionOutlineWidth: CGFloat

    /// The tweaks' defaults.
    static let standard = UITweaks().editorMetrics
}
