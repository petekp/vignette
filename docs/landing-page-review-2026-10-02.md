# Landing page review (2026-10-02)

A close read of the revamped page in `site/`, at 1440 and 390 px wide, in light and dark, with
Reduce Motion on and off, and with both demos driven through to the end. The plan is in
`docs/landing-page-2026-10-02.md`.

## Where each item stands

| Item | Status |
| --- | --- |
| Issues 1 to 8 | Fixed. The share image is new, drawn from the closer. |
| Copy 1 to 4 | Fixed. |
| Visual 1, act two opens dark | Fixed. It opens undimmed; opening the drawing brings the dim. |
| Visual 2, act one unbalanced | Fixed. The browser is centred, and a capture fills the corner. |
| Visual 3, the trailer's first frame | Open. The trailer is Pete's to re-cut. |
| Visual 4, phones | Fixed. A square stage with a camera that follows each step. |
| Visual 5, the phone fan | Fixed. It fits inside the sheet. |
| Visual 6, notes in Chrome | Kept. SF Pro Rounded's licence does not allow serving it as a web font, so Chrome without it installed sets notes in SF Pro. |
| Opportunities 1 to 5 | Done: phone camera, act two undimmed, the capture, the share image, a 3.6 MB trailer for phones. |
| Code note 1 | Fixed. The tile's radius comes from the sheet's. |

## Issues

Things that are wrong now.

1. **Light mode's secondary text is too faint to read comfortably.** Paragraphs, tile text and the
   download line use black at 50% on white, a contrast of about 3.9 to 1. The usual floor for body
   text is 4.5 to 1. Black at 60% gives about 5.7. Dark mode passes.
2. **In light mode the icon in the Download button disappears.** The icon is black and so is the
   button, so only the silver stroke shows. A hairline ring around the icon, or a light button in
   light mode, would fix it.
3. **The arrow keys stay captured after you scroll away from act one.** With the stack open, a
   visitor who scrolls down and presses an arrow key gets nothing: the stage still holds the keys
   and blocks the page from scrolling. The stage should let the keys go, and close its stack, when
   it leaves the screen.
4. **The last hint in act one is too long for a note.** "Copied. Hold right Shift on the second tap
   to open your newest screenshot." wraps to two lines at most widths, and a two-line pill reads as
   a mistake. It needs to be one short line, or two notes.
5. **The fan's crops cut through notes.** The chat card shows "Day 3. We lea" and the design card
   shows "pacing", from "use this spacing". Each crop should hold its note whole.
6. **The notes are punctuated two ways.** "Recorded in the real app." ends with a period, while
   every hint and every note in the app has none.
7. **The shortcut is named three ways.** The act one paragraph says "Tap right Shift twice", the hint
   says "Press right Shift twice", and the README says "double-tap right Shift".
8. **The share preview still shows the old page.** `og.png` has the old tagline ("an easier way to
   draw on and share screenshots with agents") on a cream background, so a link posted on X shows
   neither the new headline nor the new look.

## Copy

1. The hero paragraph and act one's heading both say "a double tap away". The second one lands
   weaker for it.
2. Act two's "its marks in a different colour from yours" is a clumsy clause. "and marks it in its
   own colour" says the same thing more simply.
3. The note on experimental features sits under the Send hint, where it reads as an afterthought.
   It belongs under act two's paragraph, or in the act two tile list.
4. "Several screenshots in one image" never names Stitch until the body. A heading such as "Stitch
   several into one" puts the feature's name where a skimmer looks.

## Visual

1. **Act two opens dark and blurred.** It starts with the annotator open, so the dim covers the
   whole screen and the Claude Code window is unreadable until after Send. That is how the app
   looks, but the first impression of the agent act is a muddy screen.
2. **Act one's screen looks unbalanced at rest.** The browser window sits left of centre, leaving an
   empty band on the right for a stack that isn't there yet.
3. **The hero video opens on a dense terminal.** Its first frame is the agent's notes on the
   page's architecture, small and busy. It's the first image anyone sees.
4. **Phones get a stage too small to read.** At 390 px the screen is drawn at a quarter of its size,
   so the cards, notes and toolbar are specks, while the hint notes below them are full size. Many
   visitors will arrive from X on a phone.
5. **On a phone the fan's outer cards touch the sheet's edges** and are clipped by them.
6. **In Chrome, notes may not be in SF Pro Rounded.** `ui-rounded` works only in Safari. Chrome
   showed SF Pro Rounded on this Mac because the font is installed here. On a Mac without it,
   Chrome sets notes in SF Pro.

## Opportunities

1. **Let phones see the demos up close.** On a narrow screen, frame each stage on the part that
   matters: the stack and the annotator in act one, the frame and toolbar in act two. The hints keep
   working as buttons.
2. **Open act two undimmed.** Show the Claude Code window and the browser first, with your drawing
   as a card in the corner. A hint opens it, so the visitor watches the dim come up as the card
   flies in.
3. **Show the card in the corner in act one.** A "Take a screenshot" hint flashes the screen and
   slides a card into the corner, already copied. That makes "Copied as you take it" something the
   visitor sees, and fills the empty band.
4. **Make a new share image** from the closer: the fan of cards, the icon and the headline. It
   would make posts on X match the page.
5. **Make the hero video lighter.** The trailer is about 10 MB and starts loading at once. A
   smaller encode for narrow screens would cut that on phones.

## Code notes

1. The tile's radius is computed from a fixed 64 px rather than the sheet's own radius, so on a
   phone, where the sheet's radius is 40 px, it isn't derived from the sheet. It works out the same
   today because of the 28 px floor.
