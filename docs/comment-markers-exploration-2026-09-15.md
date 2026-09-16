# Comment markers: an exploration

A tool that drops a numbered marker on the screenshot and attaches a short comment to it, the
way Figma comments and the Codex app's browser annotations work, and a way to hand the result to
an LLM. Nothing here is built; this is the shape of the work.

## What the Codex app does

The Codex desktop app's in-app browser has an Annotate mode (top right, or Cmd+.). You click an
element on the page, type a note, and repeat; each note becomes a marker. Send puts the notes
into the task together with a screenshot of the page, and Codex receives the words with the
image of what was clicked. An "advanced" mode also lets you change fonts, colors, and spacing on
the page and preview them before sending. The app itself is proprietary, so the exact payload is
not public.

What is public is how Codex packages context around a request. The CLI and the desktop app share
one convention (`codex-rs/tui/src/ide_context/prompt.rs`): context is rendered as markdown
sections (`## Active file: …`, `## Active selection range:` with 1-based positions) and placed
before a fixed marker, `## My request for Codex:`, in the same text item as the user's words.
Images travel as separate input items (`UserInput::LocalImage { path }`, turned into a base64
data URL at request time) in the order the user submitted them. Every surface strips back to the
last marker when it shows the transcript. So "context first, request after a known heading,
images alongside" is the pattern to match.

Sources: the Codex issue asking for preview annotation
(<https://github.com/openai/codex/issues/35502>), OpenAI's Codex app introduction
(<https://openai.com/index/introducing-the-codex-app/>), and the CLI source above.

## What Shotnote would add

A fourth kind of mark next to shapes, arrows, and text: a **comment**. Placing one is one click.
The click drops a numbered pin; a small text field opens next to it; Return commits; Escape
removes an empty pin. The pin is the number in a filled circle with a short tail, the same accent
color as the selection ring, so it reads as UI and not as a drawing. Pins renumber by creation
order, top to bottom is not attempted. A pin can be dragged, its text edited on click, and it is
deleted like any shape.

In tldraw this is a custom shape (`ShapeUtil` subclass, type `comment`) with props `{ n, text }`
and a fixed size, rendered as an HTML overlay so the text field is a real input. It lives in the
same document as the other shapes, so drafts, park, and export need no new plumbing: the
snapshot carries it, `DraftStore` stores it, and the draft badge shows it.

Export changes in one way: the PNG must show the pins with their numbers, and the comments
must travel with it as text. That is the packaging question.

## Packaging for an LLM

The receiving model needs three things: the image, the numbers on it, and the text for each
number. Everything else is convenience.

**Image.** The exported PNG with pins burned in, exactly as today's export works. The numbers on
the image are what let the model connect a comment to a place; coordinates alone are much
weaker for a vision model than "see pin 3".

**Text.** A markdown block, one line per comment, in pin order:

```
## Screenshot comments
Image: Screenshot 2026-09-15 at 10.08.24 PM-annotated.png (1512×982)
1. (x 41%, y 12%) The header should not scroll with the list.
2. (x 78%, y 63%) This button is the wrong blue; use the accent from the sidebar.
```

Percent positions are the pin's anchor in the image, so they survive any resize the receiving
side does. The block ends with a line the user did not write, so the request stays theirs.

**Where it goes.** Three destinations, in order of usefulness:

1. The clipboard, as one item with two flavors: the PNG (and the file URL) plus the markdown as
   plain text. Pasting into Claude Code, Codex, ChatGPT, or Cursor gives the app whatever flavor
   it takes; most take both. This is the same shape as today's Copy Annotated, plus text.
2. A sidecar file next to the annotated PNG: `<name>-annotated.md`. Agents that read the
   screenshot folder get the comments with the image, and `Copy Paths` already hands over paths.
3. A URL command, `shotnote://comments?file=<path>`, printing the block to the log for agents
   that drive the app without the clipboard.

The Codex convention suggests one refinement for the clipboard text: put the block first and end
it with `## My request:` on its own line, so the paste lands as context and the user types the
request after it. Codex will treat that as its own marker; other apps see a heading.

## What it would take

- Page: the `comment` shape util, a `comment` tool in `TOOLS` with a key (`c` is taken by nothing
  on the canvas; `n` for note is free), pin rendering in `exportDrafts` (HTML shapes need an SVG
  fallback for `toImage`, tldraw's `toSvg` on the util), and `park` returning the comment list.
- Bridge: `ParkResult` and `ExportResult` gain `comments: [{ n, x, y, text }]` with x and y as
  fractions of the image; protocol bump.
- App: `Clipboard.copy` with an added text flavor; the sidecar file next to `writeAnnotated`;
  a `comments` command in `Commands`; a `comments` count in the state report.
- Tests: bridge decoding of the new fields, a render test that a pin shows in the export, and a
  commands test for the URL.

Roughly two days of work. The custom shape is most of it; the packaging is small.

## Open questions

- Whether pins should also carry a crop of the region under them (Codex sends the clicked
  element). A 200 px crop per pin as extra images is cheap and helps small targets, but the
  clipboard can only carry one image. The sidecar folder could hold them.
- Whether a comment without a drawing should still write `-annotated.png`, or a plain copy of the
  original with pins. Same file either way; the name is the question.
- Numbering by creation order versus reading order. Creation order is stable under edits and is
  what Figma does.
