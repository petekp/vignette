# Decisions and measurements behind the native editor (2026-09-23)

This note records why Vignette's drawing editor moved from a web page to Swift, the decisions made
on the way, and the measurements behind them. It is history. The code, `AGENTS.md` and
`docs/editor.md` say what is true now, and where they differ from this note, they win.

The web editor was tldraw, running in a WKWebView served from 127.0.0.1. Its license allows a public
download only with a production key. An annual key that expires hides the editor in every copy
already downloaded, and Vignette has no updater. So the first download waited on a native editor.

The work ran in steps, which the tables name. 4a built the editor view. 4b put it in the annotator
and deleted the web editor. 4c drew the marks on cards and flights. 4d made the editor's sizes live
tweaks and added its `[state]` section. The measurements come from the builder's report for each
step, which are not in the repository.

## Numbers the rules quote

**The flight's wait for `loaded`,** measured in 4b. Each time is after `annotate`:

| Case | `loaded` | `shown` |
|---|---|---|
| Hovered, so the decode was cached (three opens) | 1, 5 and 17 ms | 213 to 234 ms |
| By URL, not cached: 1400×1000 px | 21 ms | 224 ms |
| By URL, not cached: 3024×1964 px, full screen | 50 ms | 219 ms |
| Motion 0 | 47 ms | 13 ms |

At motion 1 the editor always had its image before the window came up. At motion 0 the flight
arrived 34 ms before the image, so a flight lifted at its arrival would have shown an empty editor.
That is why the lift still waits for `loaded`.

**A text's outline.** Stroking all of a text's letters as one path took 240 ms for 2,000
characters. Stroking each letter's outline on its own, then filling every letter, takes 61 ms.

**Text bitmaps.** Core Animation copied a `CGImage` on the main thread at the commit that showed
it: up to 22 ms for a text the size of the view, and as much memory again. An `IOSurface` is shown
as it is.

**Memory before the switch.** With the web editor, the app used 57 MB at idle, and WebKit's three
processes 132 MB.

## Decisions made while planning the switch

| Decision | Why |
|---|---|
| The transition reducer's `parking` phase stays. | Park still waits for the zoom to spring back to fit, so the card flies home from the fitted frame. Without a zoom, park answers in the same turn. |
| The annotator's window still comes up invisible at `prepare`. | It holds the keys during the flight, so Esc during the flight turns the card around. |
| The flight's wait for `loaded` stays, with the editor as its source. | At motion 0 the flight arrived 34 ms before the screenshot's decode. |
| `dismiss` sets `slidingOut` before it sends the event. | A park that answers in the same turn otherwise ends the card's flight offscreen. |
| A drawing made from agents' marks keeps the stored drawing's point scale. A new one takes the main screen's, inside `Drawing.pointScales`. | It is Decision 8's best guess in `docs/editor.md`, for when no annotator is open. |
| Replies waiting at launch are imported as soon as their records load. | The web editor's `ready` used to start them. A build no longer waits for anything. |
| `FocusReturn` is created at launch by `AppDelegate`. | The web view's preload was the only thing that created it early enough to record the frontmost app. |
| The drafts folders are removed at every launch they exist, with no flag. | Once they are gone, the check costs one lookup. |
| Cards draw marks live over the image, rather than keeping a composited image. | A card is current the moment its drawing parks and sharp at any size, with nothing to invalidate. |

## Decisions made while building the editor view and the switch

| Decision | Why |
|---|---|
| Rectangles, ellipses and arrows are shape layers built from `Mark.shape`, the paths the renderer draws. | They stay sharp at any zoom with nothing redrawn. A bitmap per mark cost 20 ms per drag step when zoomed in, and 25 MB for a rectangle that spans the image. |
| Texts are bitmaps the renderer draws on a serial queue of their own, off the main thread. | A long text held the main thread for up to 1.9 s. Done, Send and Copy Drawing use another queue, so a long export never delays the screen. |
| Text bitmaps are IOSurfaces. No text bitmap has more pixels than the view, and a text holds at most two. | Core Animation copied a `CGImage` on the main thread, up to 22 ms, and doubled its memory. The cap bounds memory at any zoom. |
| When typing ends, the text view stays until the text's bitmap is on screen. | The words never vanish for a frame. |
| The selection and hover outline runs outside the mark's ink, and the handles sit on its corners. | On the stroke, the outline's light edge hid the mark's colour. |
| The renderer strokes each letter's outline on its own, then fills every letter. | Stroking all the letters as one path took 240 ms for 2,000 characters. Now it takes 61 ms. |
| A Command key the core has no command for, such as Cmd+W, goes to the app's menu. | The editor otherwise took Cmd+W, Cmd+Q and Cmd+, away from the menu. |
| The clipboard is read in this order: copied marks, a file, text, a URL, an image. | Finder puts a file's name as text beside its URL. Pasting a copied file must not add its name as a text mark. |
| The editor opens at `prepare`, before the screenshot's decode arrives. | Its keys work during the flight, so Esc turns the card around. An agent's push while the card flies joins the open drawing. |
| `abandon` parks and writes the drawing. | A key pressed during the flight can change it. |
| A toast is a small dark capsule at the bottom centre of the frame. | It shows where the eye already is, and nothing in the toolbar moves for it. |
| A plain scroll pans a magnified picture. The zoom keys and smart zoom do nothing during the flight. | tldraw panned on scroll. A zoom during the flight would move the frame the card is landing on. |
| Cmd+C with nothing selected gives Done's clipboard, and writes the `-annotated.png`. | Decision 10 in `docs/editor.md` says it is the same PNG as Done's. |
| Card previews were deleted in 4b. | They existed only to show drafts. |
| Reply receipts keep the codes `draft-failed` and `draft-store-failed`. | They are part of the reply protocol. |
| The editor, the cards and the flights draw marks with one drawer, `MarkLayers`. A flight and the editor share text bitmaps. | One implementation of what a mark looks like on screen, and nothing steps when the flight hands over to the editor. |
| A card's marks live in its existing `DragSource` view, rasterized at the card's size at rest and scaled while the stack narrows. | SwiftUI updates every AppKit view in the stack on every animation frame. One view per card, rasterized, cost the least main-thread time measured. |
| A stitch draws each piece's marks into its pixels, and has no drawing of its own. Pete decided the first part on 2026-09-23. | A stroke is a fixed 3.5 pt, so marks copied into a new drawing would look thicker wherever a piece is scaled down. |
| A stitch is composed off the main thread. | It used to run on the main thread. |
| The editor's sizes, the text's weight and line height, and the arrowhead's proportions are live tweaks. The weight snaps to the nine named weights, 100 to 900. | The rounded system font draws only its nine named weights. |
| `textDragDelay` is a threshold, not motion, so the motion scale does not shorten it. | Scaling it would change what a gesture means: at `motion: 0` every Text press followed by a sideways drag would set a width. |
| Done, Send, Copy Drawing and `add?marks=` lay text out with the live tweaks. | A copy breaks its lines where the person saw them break. |
