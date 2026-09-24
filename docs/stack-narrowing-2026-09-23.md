# What a frame of the stack's narrowing costs (2026-09-23)

When a card opens in the editor, the recent stack narrows to make room for it, and it widens again
when the editor closes. The `AGENTS.md` rule on the stack narrowing describes the mechanism. This
note measures what each frame of that motion costs, because the long commits left in opening and
closing a card come from it. It ends with five options, the builder's recommendation, and Pete's
decision to leave it for now.

Hover is the biggest single cost of a narrowing frame, then the layout of every card in the column.

## What a frame costs

The traces are Time Profiler with Core Animation Commits on the final 4e build, driving step 4c's
sequence: the stack slides in and scrolls, then card 20 opens and closes, then card 16. Card 20 is
the one whose editor narrows the stack. Each figure covers two narrowings of about 0.8 s each. Every
row but the first is a prototype made with settings only, no code. "7 cards" means
`recentCount = 7`. "Pointer away" means the drive moved the pointer off the column before opening a
card.

| Stack | Median commit | Main thread in commits, per narrowing | Commits over 8.3 ms, open 20 + close 20 |
|---|---|---|---|
| 21 cards, pointer over the column (today) | 4.5–4.9 ms | about 570 ms | 21, 19 |
| 7 cards, pointer over | 2.9–3.2 ms | about 500 ms | 14, 16 |
| 21 cards, pointer away | 2.6–2.8 ms | about 400 ms | 4 |
| 7 cards, pointer away | 1.4–1.9 ms | about 210–290 ms | 4 |
| Opening card 16, no narrowing (per open; long commits in open 16 alone) | 2.1–2.9 ms | about 190–215 ms | 1–3 |

A narrowing or a widening keeps commits over 3 ms coming for about 0.75 s. That is the spring's
tail, well past `ui.relayoutDuration`, which is 0.2 s by default.

The main thread is about 70% busy for the whole narrowing. With 21 cards and the pointer over the
column, 574 ms of each 0.8 s narrowing went to commits. The slower commits also make fewer frames:
about 105 per narrowing, against about 150 with the pointer away.

This is where the main thread goes, in samples of 1 ms each over two narrowings, for 21 cards:

| | Pointer over | Pointer away |
|---|---|---|
| All main-thread samples | 1039 | 774 |
| SwiftUI render of the hosting views | 807 | 536 |
| Attribute-graph update, which is the layout | 441 | 210 |
| Pushing geometry and contents to layers | 310 | 325 |
| Of that, geometry | 155 | 143 |
| Of that, each card's `NSImage` drawn again at its new size (`ImageLayer.update`) | 52 | 74 |
| View bodies (`DynamicBody`) | 123 | 13 |
| Of that, `CardView.body` | 71 | 12 |
| Hover requests (`didRequestHoverUpdate`) | 76 | 1 |
| Hover dispatch | 39 | 0 |

Two things make a frame expensive:

- **Every card follows the stack's width.** A card's size comes from `model.widthScale`, so the
  spring moves every card's frame. SwiftUI lays out the column's `VStack` on every frame, and that
  `VStack` holds every card: 21 here, and up to `recentCount`, 30 by default. Only about 6 are in
  view. Each card's roughly 12 modifiers are laid out again, and its layers get new geometry, a new
  shadow and an `NSImage` drawn again at the new size.
- **Hover runs on every frame.** When the pointer is over the column, the cards slide under a still
  pointer. SwiftUI hit-tests hover on every frame, and the hovered card's state changes:
  `model.hoveredCard` and the click hint's `pointer` in `CardView`. That runs card bodies and their
  part of the graph again. After a click on a card, the pointer is always over the column, so this
  is the usual case.

## Options

**A. Freeze hover and clicks on the column while it narrows or widens.**

- Code: `ThumbnailController.makeRoom` sets a flag on the model for the length of the spring
  (`Anim.settle`). `StackView` applies `.allowsHitTesting(false)` to the column while the flag is
  on. A lighter version has `CardView`'s hover handlers ignore changes while the flag is on. That
  keeps clicks, but it also keeps SwiftUI's hover hit test on every frame, about 115 of the 1039
  samples.
- Cost: about half a day.
- Saves: the pointer-away rows measure this. Long commits during the narrowings drop from about 20
  to 4. The median commit drops from 4.5–4.9 ms to 2.6–2.8 ms. Main-thread time per narrowing
  drops by about 30%.
- What a person sees: for about 0.75 s while the column moves, the hover state stays as it was when
  the move began. That covers the hover scale, the dim, the corner buttons and the click hint. Cards
  sliding under the pointer do not light up one after another, and the state catches up when the
  column stops. In the full version, a click on a card during those 0.75 s does nothing, which is
  the rule a press on a card flying home already follows.

**B. Lay out only the cards in view.**

- Code: `StackView.column` builds only the cards whose slot meets the viewport, plus one on either
  side. It places them with `StackLayout`'s own arithmetic, `cardFrame(index:cards:…)` and
  `contentHeight(cards:showsBar:)`, where a `VStack` holds every card today. The scroll offset moves
  that set. The slide-in stagger, the slide-out, the insert and remove transitions, the drag-select
  sweep and scroll-to-reveal all need checking again.
- Cost: 1 to 2 days.
- Saves: the work per frame follows the number of cards drawn. With the pointer away, going from 21
  cards to 7 took the median commit from 2.6–2.8 ms to 1.4–1.9 ms, and main-thread time per
  narrowing from about 400 ms to about 250 ms. It also makes opening the stack, scrolling and every
  other relayout cheaper.
- What a person sees: nothing. The layout and the frames are the same.

**C. Make each card cheaper to draw again.**

- Code: show the thumbnail as layer contents with an aspect-fill gravity, through a `CGImage` or a
  small representable like `MarksView`. A size change is then a bounds change, and the `NSImage` is
  not drawn again. Give the shadow a path.
- Cost: half a day.
- Saves: drawing the image again is 52 to 74 of the 536 to 807 render samples, about 9 to 14%.
  Shadows are about 2%.
- What a person sees: nothing.

**D. Transform the column during the motion.**

- Code: lay the column out once at the new width, and animate a scale on it, anchored at the bottom
  trailing corner, from the old width to the new.
- Cost: about 1 day, including the scroll that follows the column and the mask.
- Saves: nearly all the layout per frame. Not measured, because it needs a build.
- What a person sees: in mid-motion, everything in the column scales together. That is the corner
  radius, the ring's width, the shadow, the gaps between cards, the agent tab, the recording badge,
  the selection circle, the copied mark, the hover buttons and the click hint. Whatever does not
  follow the width today steps in size at one end of the motion. Right after a narrowing starts,
  badges and buttons would show about 23% larger, which is 1 / 0.81.

**E. Move the column into Core Animation.**

- Code: cards become layers, with contents, corner, border, `shadowPath` and the marks layer, laid
  out by `StackLayout`. The narrowing becomes a `CASpringAnimation` on each card's bounds and
  position, which the render server interpolates. Hover, buttons and badges move to AppKit.
- Cost: several days. `StackView.swift` is 709 lines of behaviour.
- Saves: nearly all the main thread's work per frame.
- What a person sees: nothing, if the bounds animate rather than a transform.

**The builder recommends A, then B.**

- A first. Hover is the largest single cost, and A is the cheapest change that removes it. Hover
  held still in mid-motion is arguably better to look at than cards lighting up one after another
  under a still pointer.
- Then B. It removes most of what is left without changing anything a person sees, and it helps
  every other relayout.
- Together, on the proxy of 7 cards with the pointer away, a narrowing's median commit is 1.4 to
  1.9 ms. That is below opening a card with no narrowing, at 2.1 to 2.9 ms. Both keep the SwiftUI
  stack as it is.
- E stays in reserve, for the case where A and B still drop frames.

The traces were taken as the `AGENTS.md` section on measuring a stutter describes. The scripts that
summed them only read traces, and they were not committed.

## Decision

Pete, 2026-09-23: left for now, to take up later. Nothing was built. `docs/TODOS.md` lists it.
