# The intro's pour into the menu bar icon

When setup closes, a picture of its window pours into the menu bar icon (`MenuBarIntro`), the way
macOS's genie effect pours a window into the Dock. `ui.introFunnel` sets how strongly: at 0 the
picture flies as one piece on a bowed path, shrinking and fading into the icon; at 1, the default,
it pours.

## What it borrows from the genie

- The window bends instead of scaling as one piece. Each row of the picture moves on its own
  schedule.
- The edge nearest the icon leads. The top row starts at once and the bottom row last, so the
  shape points at the icon before anything reaches it. The menu bar is always above the window, so
  the top edge always leads.
- Each row narrows to the icon's width faster than it travels, so the picture forms a funnel whose
  mouth is the icon.
- The content drains into the icon. Each row fades over the last part of its travel
  (`ui.introFunnelFade`), so rows that reach the icon never pile up over it, and the last row is
  gone as it arrives. A version that faded the whole picture over the last tenth of the flight
  left a dark column under the icon, which vanished in three frames.

`introFunnel` sets the stagger between the first and last row (up to 60% of the flight) and how
far the narrowing leads the travel.

## How it is drawn

- The card (picture, outline and rim) is drawn into one bitmap, which a SwiftUI view shows across
  the screen-wide panel the flight uses.
- `layerEffect` runs `funnel` (`Sources/IntroFunnel.metal`) for every pixel. For each point on
  screen it finds the row of the picture there by halving, and its signed distance to the bent
  shape's edge.
- That distance does three things. It fades the edge over one device pixel. It rounds the corners
  on screen, from the window's own radius to `ui.introFunnelCorner` as their rows leave, whatever
  the rows have done to the picture's own corners. And it draws the shadow.
- The shadow is drawn in the shader because SwiftUI's `.shadow` drew nothing under this effect: at
  the handover, what was behind the window got 44% brighter, which is exactly the window's own
  shadow going away. The shader's is a soft edge fitted to the window's measured shadow on macOS
  15: strength 0.67, spread 20 pt, dropped 15 pt. It darkens what is behind it by the same amount
  as the window's at 2, 10 and 22 pt beside the window (take 18: a brightness ratio of 1.00 at all
  three).
- Each row eases in and out (`ui.introFunnelSmoothing`), so the sides curve without a kink where
  moving rows meet rows that have not started.
- A squeezed row averages the picture across the stretch each screen point covers
  (`ui.introFunnelSmear`), so squeezed text softens along the flow instead of breaking into streaks.
- `ui.introFunnelRim` lights the bent edges of rows that have left.
- The highlight behind the icon comes up as the first row reaches the icon, at the icon's width.
  The pop, the sheen and the popover keep their moments, and `ui.introDuration` sets the length.
  The panel leaves three frames after the last row is gone, so a frame drawn late draws nothing.

## Tuning it

The Intro Lab (`IntroLab.swift`, the tweak panel's Intro button, or `vignette://intro-lab` with
`debug` on) draws the pour over a picture of the screen at any moment, loops it slowed down, and
plays the real intro into the menu bar icon from a stand-in for setup's window. Its sliders are the
`ui` settings above.
