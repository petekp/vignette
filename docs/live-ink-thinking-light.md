# The thinking light

Part of live ink (`docs/live-ink.md`). The code is `LiveThinkingLight.swift` (the band and the
sheen), `LiveRimLight.swift` (the rim) and `LiveMarksLayer.think` in `LiveInkOverlay.swift`, which
lays and removes them.

While an ask waits, for the responder or for its turn, the ink and the note it is about carry the
thinking light: a soft band of light runs along each stroke every 1.15 s, and a sheen crosses the
note a third of a beat later. The band is brightest and widest at its middle and fades towards its
ends, in a glow. On gel ink its width is a share of the gel's width (`ui.inkGelWidth`).

On an arrow the band runs from tail to head and rests off the head before the next pass, so it
points the way the arrow does.

On a loop, a circle or a box, the band laps once a beat with no rest, and crosses the point where
the hand began and ended with no cut. A hand's loop overshoots its start or stops short of it, and
live ink draws a loop past its start, so the band's path is cut to one turn where the line comes
back nearest its start, and closed. That turn is laid twice end to end, and the band runs from the
first turn into the second, so its jump back at each beat lands where it already is. A band is at
most half its loop long, so a small loop still shows where the band is.

Every band counts from one start, so marks that began waiting at different moments move together.
The light fades in and out over 0.2 s. With motion off the ink brightens and holds.

A popover waiting on an answer, the sent note and then its conversation, carries the light round
its rim (`RimLight`): a soft light that leaves from under the arrow and goes round clockwise once
every two beats, seen through a thin ring at the body's edge and a fainter, wider one for its glow.
It is white on a dark popover and the ink's light colour (`ui.inkGelLight`) on a light one, where
white would not show. It keeps time with the band on the ink, so the note and the conversation that
takes its place show the light at the same point. With motion off the whole rim glows at 35% of its
brightness and holds.

The band's brightness, length, width and glow, and the rim's brightness, are the tweak panel's
Live ink "Thinking light" rows (`ui.thinkingBrightness`, `thinkingLength`, `thinkingWidth`,
`thinkingGlow`, `thinkingRimBrightness`).
