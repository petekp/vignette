import AppKit

extension UITweaks {
    var inkHandFeel: InkHand.Feel {
        InkHand.Feel(width: self.inkHandWidth, speed: self.inkHandSpeed, thinnest: self.inkHandThinnest, widest: self.inkHandWidest,
                     memory: Int(self.inkHandSpeedMemory.rounded()), smoothing: Int(self.inkHandWidthSmoothing.rounded()),
                     startTaper: self.inkHandStartTaper, startWidth: self.inkHandStartWidth, endTaper: self.inkHandEndTaper, endWidth: self.inkHandEndWidth)
    }

    var editorMetrics: EditorMetrics {
        EditorMetrics(dragDistance: self.dragDistance, hitMargin: self.hitMargin, cornerHitSize: self.cornerHitSize, edgeHitSize: self.edgeHitSize,
                      smallSide: self.smallSide, handleSize: self.handleSize, dotRadius: self.dotRadius, dotHitRadius: self.dotHitRadius,
                      smallestRectangle: self.smallestRectangle, shortestArrow: self.shortestArrow, textDragDelay: self.textDragDelay,
                      textDragDistance: self.textDragDistance, newTextSize: self.newTextSize, selectionOutlineWidth: self.selectionOutlineWidth)
    }

    /// The style every text is set in. The system font draws only its nine named weights, whatever
    /// weight it is asked for (measured on macOS 15), so a weight picks one: 100 is the first.
    var textStyle: TextStyle {
        func named(_ value: Double, _ fallback: Double) -> NSFont.Weight {
            let weights: [NSFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
            let weight = value.isFinite ? min(max(value, 100), 900) : fallback
            return weights[Int((weight / 100).rounded()) - 1]
        }
        return TextStyle(personFont: self.textFont, personWeight: named(self.textWeight, UITweaks().textWeight),
                         agentFont: self.agentTextFont, agentWeight: named(self.agentTextWeight, UITweaks().agentTextWeight),
                         lineHeight: self.textLineHeight, padTop: self.notePaddingTop, padBottom: self.notePaddingBottom, padSide: self.notePaddingSide,
                         widthCap: self.noteMaxWidth, badgeInset: self.badgeInset, badgeOverlap: self.badgeOverlap, agentSize: self.agentTextSize / 100)
    }

    /// How big a new drawing's marks are on its screenshot.
    var markScaleRule: MarkScaleRule {
        MarkScaleRule(power: self.markScalePower, smallestNoteText: self.smallestNoteText, newTextSize: self.newTextSize)
    }

    /// How big the marks are on a card live ink makes: full size on any picture, since the card shows
    /// a window as live ink drew on it, at the screen's own size. An agent's note keeps its floor.
    var liveInkMarkScaleRule: MarkScaleRule {
        MarkScaleRule(power: 0, smallestNoteText: self.smallestNoteText, newTextSize: self.newTextSize)
    }

    /// How every mark is painted. A colour that is not `#rrggbb` takes the default's, as `validated`
    /// has already reported.
    var markStyle: MarkStyle {
        func color(_ path: KeyPath<UITweaks, String>) -> SRGB { SRGB(hex: self[keyPath: path]) ?? SRGB(hex: UITweaks()[keyPath: path])! }
        return MarkStyle(strokeWidth: self.strokeWidth, edgeWidth: self.edgeWidth, personColor: color(\.personColor), agentColor: color(\.agentColor),
                         edgeColor: color(\.edgeColor), wordColor: color(\.noteTextColor), shadowOpacity: self.shadowOpacity,
                         arrowheadLength: self.arrowheadLength, arrowheadWidth: self.arrowheadWidth, pin: pinStyle)
    }

    var pinStyle: PinStyle {
        PinStyle(side: self.pinSize, numberSize: self.pinNumberSize, numberWidth: self.pinNumberWidth, clusterOverlap: self.clusterOverlap,
                 clusterPadding: self.clusterPadding, farthestMove: self.pinFarthestMove, listNarrowest: self.commentListNarrowest,
                 listWidestBelow: self.commentListWidestBelow, listWidthBeside: self.commentListWidthBeside,
                 listRowPadding: self.commentListRowPadding, listWordsGap: self.commentListWordsGap,
                 listParagraphSpacing: self.commentListParagraphSpacing, gradient: self.pinGradient, bottomShade: self.pinBottomShade, rimWidth: self.pinRimWidth,
                 shadowRadius: self.pinShadowRadius, shadowOffset: self.pinShadowOffset, shadowOpacity: self.pinShadowOpacity,
                 logoSize: self.pinLogoSize, answerSize: self.pinAnswerSize,
                 gelBevel: self.pinGelBevel, gelDome: self.pinGelDome, gelDeep: self.pinGelDeep, gelRod: self.pinGelRod,
                 gelHandle: self.pinGelHandle, gelHandleCore: self.pinGelHandleCore,
                 gelHandleRounding: self.pinGelHandleRounding, gelHandleCoreShadow: self.pinGelHandleCoreShadow,
                 gelRing: self.pinGelRing, gelRingGap: self.pinGelRingGap, gelRim: self.pinGelRim, gelFaceShadow: self.pinGelFaceShadow)
    }
}
