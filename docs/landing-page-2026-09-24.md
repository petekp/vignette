# The landing page, rethought (2026-09-24)

The page opens with a headline, a paragraph, one still, and nine feature cards of equal weight. A
visitor reads a lot before they see the app do anything, and the flat grid gives them no order to
follow. This plan keeps the page's minimal look (one narrow column, small type, the wordmark, wide
pictures) and changes how it tells the story, taking its cues from how Apple's product pages
communicate rather than how they look.

## What to take from Apple

Studied on apple.com/iphone-duo.

- **One idea first.** The top of the page is the product's name, one short line, and the product
  itself. Everything else waits.
- **Show, then explain.** A picture comes right after the claim it proves, before the detail.
- **One idea per section.** Each has a headline that says what you get, a short paragraph that says
  how, and a picture. A reader who stops after any section has a complete thought.
- **What is new comes first, the basics come last.** The things only this product does lead; what
  it shares with others is a short list near the end.
- **The download is at the top and the bottom,** so a visitor who is convinced early does not have
  to scroll for it.

Left behind: the size of the type, the alternating backgrounds, the pinned bar, and the carousels.

## The page

1. **Hook.** "The modern Mac screenshot tool for the agentic age." Then one short paragraph: "A
   picture is worth a thousand-word prompt. Vignette makes the screenshots you already take with
   Cmd+Shift+4 quick to find, mark up and hand to a coding agent." The download button, "Free and
   open source, for macOS 14 or later.", and the trailer, about 15 seconds of the whole loop
   (`docs/trailer-2026-09-24.md`).
2. **Your recent screenshots, a double tap away.** The stack, the keys, and the held tap. Clip: the
   stack slides in and the focus walks down the cards.
3. **Mark it up, then hand it off.** Three tools, no colour picker, Done copies, drag into Claude
   Code. Picture: the current still, `site/stack-and-editor.png`.
4. **Your agent can show you things too.** The skill, the agent's own marks, Send, and that the
   agent features are experimental and Send reaches Claude Code only inside herdr. Clip: a card
   from Claude arrives with its marks, then the Send menu.
5. **Several screenshots, one image.** Stitch, and the layout that survives Claude's 1,568-pixel
   limit. Clip: the pieces fly together into one numbered image.
6. **Also.** A short list: copies on capture, several in a row, marks kept apart from the
   screenshot, `vignette://` URLs and one settings file.
7. **The download again,** with the install line, then the footer.

A draft of this page was shown to Pete on 2026-09-24 and is not in the repo yet. It keeps the
current page's styles and adds only the section headings and the clip slots.

## The clips

Four short loops and one existing still. Each loop is muted, plays on its own, repeats, and has a
still as its poster. A visitor with Reduce Motion on sees the poster only, which is the rule the app
itself follows. MP4 and WebM, a few hundred KB each, served from `site/`.

Each clip needs:

- A test copy of the app with its own bundle id and a scratch watch folder, so none of Pete's
  screenshots appear.
- Staged content: a mock web page like the one in the current still, a Claude Code session for the
  drag, and cards from Claude and Codex.
- The screen for a minute or two, since recording posts real input and films the real display. That
  has to be a time Pete is not using the Mac.

The hook's clip overlaps the new demo video in `docs/TODOS.md`, which is Pete's to record. Either the
demo is cut down for the hook, or the hook's clip is made first and the demo grows from it.

## Open questions

- Is the hook's clip Pete's recording or a staged one?
- Until the clips exist, does the page go out with stills, or wait?
