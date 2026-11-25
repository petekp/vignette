import AppKit

extension UITweaks {
    var inkHandFeel: InkHand.Feel {
        InkHand.Feel(width: inkHandWidth, speed: inkHandSpeed, thinnest: inkHandThinnest, widest: inkHandWidest,
                     memory: Int(inkHandSpeedMemory.rounded()), smoothing: Int(inkHandWidthSmoothing.rounded()),
                     startTaper: inkHandStartTaper, startWidth: inkHandStartWidth, endTaper: inkHandEndTaper, endWidth: inkHandEndWidth)
    }

    var editorMetrics: EditorMetrics {
        EditorMetrics(dragDistance: dragDistance, hitMargin: hitMargin, cornerHitSize: cornerHitSize, edgeHitSize: edgeHitSize,
                      smallSide: smallSide, handleSize: handleSize, dotRadius: dotRadius, dotHitRadius: dotHitRadius,
                      smallestRectangle: smallestRectangle, shortestArrow: shortestArrow, textDragDelay: textDragDelay,
                      textDragDistance: textDragDistance, newTextSize: newTextSize, selectionOutlineWidth: selectionOutlineWidth)
    }

    /// The style every text is set in. The system font draws only its nine named weights, whatever
    /// weight it is asked for (measured on macOS 15), so a weight picks one: 100 is the first.
    var textStyle: TextStyle {
        func named(_ value: Double, _ fallback: Double) -> NSFont.Weight {
            let weights: [NSFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
            let weight = value.isFinite ? min(max(value, 100), 900) : fallback
            return weights[Int((weight / 100).rounded()) - 1]
        }
        return TextStyle(personFont: textFont, personWeight: named(textWeight, UITweaks().textWeight),
                         agentFont: agentTextFont, agentWeight: named(agentTextWeight, UITweaks().agentTextWeight),
                         lineHeight: textLineHeight, padTop: notePaddingTop, padBottom: notePaddingBottom, padSide: notePaddingSide,
                         widthCap: noteMaxWidth, badgeInset: badgeInset, badgeOverlap: badgeOverlap, agentSize: agentTextSize / 100)
    }

    /// How big a new drawing's marks are on its screenshot.
    var markScaleRule: MarkScaleRule {
        MarkScaleRule(power: markScalePower, smallestNoteText: smallestNoteText, newTextSize: newTextSize)
    }

    /// How big the marks are on a card live ink makes: full size on any picture, since the card shows
    /// a window as live ink drew on it, at the screen's own size. An agent's note keeps its floor.
    var liveInkMarkScaleRule: MarkScaleRule {
        MarkScaleRule(power: 0, smallestNoteText: smallestNoteText, newTextSize: newTextSize)
    }

    /// How every mark is painted. A colour that is not `#rrggbb` takes the default's, as `validated`
    /// has already reported.
    var markStyle: MarkStyle {
        func color(_ path: KeyPath<UITweaks, String>) -> SRGB { SRGB(hex: self[keyPath: path]) ?? SRGB(hex: UITweaks()[keyPath: path])! }
        return MarkStyle(strokeWidth: strokeWidth, edgeWidth: edgeWidth, personColor: color(\.personColor), agentColor: color(\.agentColor),
                         edgeColor: color(\.edgeColor), wordColor: color(\.noteTextColor), shadowOpacity: shadowOpacity,
                         arrowheadLength: arrowheadLength, arrowheadWidth: arrowheadWidth, pin: pinStyle)
    }

    var pinStyle: PinStyle {
        PinStyle(side: pinSize, numberSize: pinNumberSize, numberWidth: pinNumberWidth, clusterOverlap: clusterOverlap,
                 clusterPadding: clusterPadding, farthestMove: pinFarthestMove, listNarrowest: commentListNarrowest,
                 listWidestBelow: commentListWidestBelow, listWidthBeside: commentListWidthBeside,
                 listRowPadding: commentListRowPadding, listWordsGap: commentListWordsGap,
                 listParagraphSpacing: commentListParagraphSpacing)
    }
}
