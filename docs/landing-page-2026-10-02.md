# The landing page, revamped (2026-10-02)

Pete asked for a landing page "that really does justice to the level of craft we put into the app,
and clearly illustrates what makes it not just a powerfully simple replacement for your everyday
screenshots, but can transform the way you collaborate with agents."

The source is `site/`. Vercel's GitHub integration deploys it to vignette.pete.design on every push
to `main`, so nothing here is pushed without Pete's approval for that step.

Each creative choice below was Pete's, picked from a few options.

## Story and structure: two acts

1. **Hero.** One headline that names both ideas, Download (free, macOS 14 or later), and the
   trailer, which shows the whole round trip.
2. **Act one: works the way you're used to.** Vignette is macOS's screenshot tool, made
   better: the same keys, with a card where macOS's thumbnail was. Six tiles follow the demo. The
   first row is what changes: on the clipboard at once, the recent screenshots, drawing on any of
   them. The second row is what Vignette adds: Stitch, dragging a card out, and screen recordings as
   cards.
3. **Act two: draw it for your agent.** Send to the session you were just in; the agent answers
   with its own drawing, in its own colour, as a card; Reply, and the loop goes on.
4. **Made to feel like part of your Mac.** The craft, named: the app you're in stays in front,
   nothing jumps, marks stand out on any screenshot, drawings stay editable, several in a row,
   and `vignette://` URLs for agents.
5. **The closer.** The app icon in front of a fan of five cards from the demos, each cropped around
   its marks, with Claude's in the middle. Then the wordmark, the headline again, Download, "Free
   and open source, for macOS 14 or later", and the GitHub and X icons.

Why: the brief has this shape. A visitor without an agent has a complete reason by the end of act
one, and the agent features, which are experimental, do not carry the whole page. The trailer at the
top keeps the agent story in view for visitors arriving from Pete's posts.

## How the acts show the app: live in the page

Each act rebuilds its moment in HTML with the app's own numbers, and the visitor drives it.

- **Act one** opens on a trip planner in Chrome. "Take a screenshot" drags a selection over the
  page, as Cmd+Shift+4 does, and the capture comes in as a card in the corner with its Copied
  notice. The cropped picture is really on the visitor's clipboard. A double tap of right Shift
  brings in the recent stack, a click flies a card into the annotator, and Copy flies it home.
  "Take another screenshot" then sets up the hold: double-tap and hold right Shift opens the new
  capture straight in the annotator.
- **Act two** opens undimmed: Claude Code on the left, the planner, and the visitor's drawing as
  the newest card. Opening it brings up the dim. Send flies it to the session, Claude answers in
  the terminal and changes the page, and Claude's card lands in the stack, marked in indigo, with
  Reply.

The trailer stays in the hero as the recording of the real app.

Why: the motion is most of the craft, and a visitor who makes it happen believes it. With Reduce
Motion on, every step changes at once, as the app does at `motion: 0`.

## Visual style: the page is drawn on

Vignette's own marks are the page's only decoration and its only colour. Your red marks act one;
in act two the agent's indigo answers it, with SF Mono notes and a Claude badge. Type is the Mac's
own. The page follows the visitor's light or dark setting.

The page sits in one large sheet on black, with iOS's continuous corners: a 64 px radius and a
12 px black margin, 40 px and 6 px on a phone. The sheet is the page colour, in light and dark
alike. The content inside keeps a gutter of 28 to 80 px, by the window's width.

Each feature is a tile with the same continuous corners. A tile's radius is the sheet's less the
gutter between them, so the two curves are concentric, and never below 28 px.

## Content in the demos

Act one's stack holds a varied, staged history: Postcard pages, a terminal, a
design frame and a chat with Maya. Act two continues the trailer's Postcard story: the highlight
day boxed with "make this pop, options?", and Claude's answer: three versions of the day, each with a note on what sets it apart.

## Headline

"Show, don't prompt."

## Design tokens

| Token | Light | Dark | Source |
| --- | --- | --- | --- |
| Page | `#ffffff` | `#1e1e1e` | macOS window background |
| Text | black at 85% | white at 85% | macOS label colour |
| Secondary text | black at 60% | white at 55% | macOS secondary label, darkened for contrast |
| Your marks | `#e03131` | same | `UITweaks.personColor` |
| Agent's marks | `#364fc7` | same | `UITweaks.agentColor` |
| Mark edge | `#ffffff` | same | `UITweaks.edgeColor` |
| Matte | `#1a1a1a` | same | `Config.matte` |

Type: SF Pro (`system-ui`) for everything the page says, SF Pro Rounded semibold for your notes,
SF Mono semibold for an agent's, as in the app. The headline is large and tightly set; body text
sits in a column of about 34 em.

Layout: text left-aligned in a narrow column. Each stage is wider than the text and is a Mac
screen at 1440 by 900 points, scaled to fit, so every size inside it is the app's own.

On a screen 600 px wide or less, each stage is square and frames part of the Mac screen, like a
camera. It springs to what matters at each step: the browser, the selection being dragged, the card
in the corner, the stack, the annotator's frame and toolbar, then the terminal and the page while
Claude answers. The whole screen at phone width is a quarter of its size, too small to read.

Motion: springs with the app's durations and bounce (`Anim.spring`, flight bounce 0.15). Flights
bow 15% of their path, at most 64 pt, and swell 7% at the middle. Nothing moves unless the visitor
started it, except the trailer.

## The build

- `site/index.html` is the page. `site/demo/site.css` holds its styles, `site/demo/vignette.js` the
  stage (springs, captures, the stack, flights, the annotator, marks, the phone camera),
  `site/demo/cards.js` the screenshots, the marks and the closer's fan, and `site/demo/page.js`
  the two acts.
- `site/og/index.html` draws the share image, `site/og.png`, from `cards.js` and the page's styles.
  Its comment says how to render it.
- Phones get `site/trailer-small.mp4`, 960 by 600 at 60 frames a second and 3.6 MB, in place of the
  10 MB trailer.
- The images in `site/demo/` are the trailer's Postcard pages, and three staged screenshots (a
  terminal, a chat with Maya and a design frame) rendered from HTML at 2x.
- Each hint under a stage is a button that takes the step it names, so the demos work on a touch
  screen and without a keyboard. It shows the keys for that step as keycaps, which go down as the
  real keys do, or a glyph for a click. When the step is a click on something in the stage, such as
  a card or Send, that thing has a breathing white ring until the step is taken. While the demo is
  busy, the hint is a line of text with a check or a spinner, and nothing to press. Red notes are
  only marks, as in the app.
- Copy in act one puts the real rendering on the visitor's clipboard.

## Still to decide

- Whether stitching gets a small live demo, or stays as text.
- The trailer's first frame, a dense terminal, is the first image anyone sees. A re-cut that opens on
  the planner would fix it; that is Pete's call, since the trailer is his.
