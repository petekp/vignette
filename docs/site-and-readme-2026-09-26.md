# The site and the README, brought up to date (2026-09-26)

The landing page and the README now describe the app as it is in `main`. Both were read as someone
who has never heard of Vignette. Nothing is pushed: pushing `main` deploys the site.

**Push the site with 0.1.2, not before.** Three things the pages now describe are only in `main`:
the message you can type with Send, a note beside a box or an arrow, and freehand arrows. The
Download button still gets 0.1.1.

## What was wrong

- **Send's card described Send before 0.1.1,** and Reply was not on the page.
- **The colour claim was wrong on both.** Marks are red unless red would be hard to see on what is
  under them (`docs/editor.md`, the colour pass).
- **"Circle something":** a person cannot draw an ellipse. Only an agent can.
- **The README contradicted the app:** macOS's thumbnail "just like it used to" with "Copy, Draw,
  and Delete on hover", a button called Done, and Pete's own Dropbox path in the diagram.
- **A newcomer was not told** that Vignette replaces macOS's thumbnail, that the double tap needs
  Accessibility and a key combination does not, that it is free and notarized, or what Send needs.
- **Missing features:** screen recordings, Reply, changing an agent's marks, and dragging a card into
  a terminal (README only).
- **"Annotate"** was in the share image and its alt text. Words a user reads say draw (`AGENTS.md`).
- **`docs/agents.md`,** which the README links, described the skill offer before setup had a page
  for it.

## What changed

- **`site/index.html`:** each fix above, a Download button under the opening paragraph as well as at
  the bottom, and the install line with "Free, for macOS 14 or later", notarization, Accessibility
  and the thumbnail. The structure, the headline, the opening paragraph and the card headings are
  unchanged.
- **`README.md`:** the same facts. A plain description under the opening line, a Coding agents
  section with Send, Reply and what Send needs, and the setup steps under Get it.
- **`site/og.png`:** "annotate" became "draw on", re-rendered from `site/og/index.html`.
- **`docs/agents.md`:** the install paragraph.

Checked in Chrome at 1440 and 390 px wide: the layout holds and nothing scrolls sideways.

## Decisions for you

Recommendation first in each.

1. **When to push.** Cut 0.1.2 first, so the download matches the page. If that is more than a day
   or two away, drop the three lines above and push now.
2. **The still shows a toolbar the app no longer has** ("Send ⌄" and "Done"). Re-capture the same
   scene on the demo copy if the trailer is more than a few days away; otherwise let the trailer
   replace it.
3. **The share image's marks.** Its dark card has an ellipse drawn as yours, which a person cannot
   draw, and its chips say "from claude" in lowercase where the app says "From Claude". Redesign it
   with the trailer.
4. **The README's lead.** It opens with your 2010 line, then the new description. The alternative
   leads with the site's headline and paragraph, so a visitor from the site reads the same pitch.
5. **The Download button at the top** is new. It follows `docs/landing-page-2026-09-24.md`. Remove
   the one `<p class="download">` under the opening paragraph to undo it.
6. **The grid of nine cards stays** until the trailer and the clips exist, since the sectioned page
   was designed around clips.
