# Screenshot comments: the 11-11 proposal

Part of [the screenshot comments plan](../screenshot-comments-2026-11-24.md).

Codex wrote a proposal for screenshot comments on 2026-11-11
(`screenshot-comments-proposal-2026-11-11.md`), and a review of it. Neither was committed. This plan
replaces both. This page says what the plan keeps from them and where it departs, so the two files
can be deleted.

## What this plan keeps

- Comment as a tool beside the existing ones, with the gesture that starts a note after a box or an
  arrow left as it is.
- A click for a point and a drag for an area, with the composer opening on release.
- Several comments on one place, and a number that stays the same as comments are added.
- Numbers that are never reused. Undo brings back the same number, and an empty new pin takes none.
- Pins that keep one size on screen, clusters that open into a list, and a list that reaches every
  pin, including pins on the same point.
- A drawing that holds only comments surviving close, reopen, rename and export. Step 1 does this by
  moving the 33 places that read "no marks" as "no drawing".
- Copy as one PNG with a list, beside a tall screenshot or below a wide one, the picture's pixels
  unchanged, colliding numbers moved apart with short lines. Pete chose this on 2026-11-25.
- The same output for the editor's Copy, the stack's Copy Drawing and a drag. A drawing with marks
  only keeps its size, and the stack's Cmd+C still copies the original.
- A failed rendering that keeps the drawing editable and says what failed.
- Stitch moving each piece's comments into the stitch with its own numbering, keeping piece numbers
  apart from pin numbers, and writing the comments before the card appears. Pete chose this on
  2026-11-25. A stitch whose pieces hold pins also stops when a piece cannot be read, rather than
  dropping its comments.
- A reply drawn on a picture without burned-in pin numbers, so a reply card's live pins do not sit
  on top of numbers in its pixels. Step 4 stores `base.png` for this.
- The toolbar's message as the request about the whole screenshot.
- Its survey of other products, summarized below.
- Its check before shipping: a copy pasted into a chat and an issue, matched to its places by
  someone who did not write it, again after deleting a pin and with long comments on a small
  screenshot, and the usual copy, terminal paste, reopen, Stitch and reply in Claude Code and Codex.
  Step 3's check uses it.

### What other products do

| Product | What this plan takes from it |
|---|---|
| [Figma](https://help.figma.com/hc/en-us/articles/360041068574-Add-comments-to-files) | A click for a point and a drag for an area. Pins that cluster as the view zooms out, and a list that reaches every comment. The teardrop shape Pete chose. |
| [Frame.io](https://help.frame.io/en/articles/9105251-commenting-on-your-media) | Showing a comment's exact area when it is read, without keeping every outline on screen |
| [Ziflow](https://help.ziflow.com/hc/en-us/articles/30725221397396-Review-proofs-on-mobile-devices) | What the editor shows is separate from what an export holds. Copy and Send always draw every area's outline. |
| [Shot and Tell](https://shotandtell.robgough.net/) | A Mac app whose Copy makes one PNG with a numbered list, the closest example of Choice 4. It renumbers after a deletion, which this plan does not. |
| [Acrobat](https://helpx.adobe.com/acrobat/desktop/share-and-review-documents/review-documents/add-shapes-drawings.html) | Printed comment summaries that match comments to places by number or by a leader line |
| [CleanShot X](https://cleanshot.com/screenshots) | Comments through a shared web link. Vignette keeps to a PNG that pastes anywhere. |

These come from each vendor's documentation. They describe how each product works. Step 3's check
measures how fast people write comments on Vignette and how well a pasted image reads.

## Where this plan departs

The proposal was written against the editor of 11-11. Since then the editor keeps its undo history
and message in the drawing file, and shares one undo timeline with the stack. Its toolbar carries a
message and a session control, and double-click editing is changing.

- It kept unfinished comments as drafts with an indicator, and had Copy and Send ask whether to
  include them. Vignette keeps what was typed when typing ends, and asks no questions
  (`docs/no-toasts-2026-09-30.md`). Here a comment posts whenever its typing ends.
- It saved with Cmd+Return and broke lines with Return. In Vignette Cmd+Return sends, and Return
  finishes a note and sends from the message field. Here Return posts, and Cmd+Return posts and
  sends.
- It said to reuse the editor's history. A history step names a mark by its index, and the file
  checks its history against a hash of the marks and message (ADR 0028). Pins need a step that names
  them by `id`, and the hash has to cover them.
- It predates ADR 0029. Pin steps are editor steps, so Cmd+Z at an opening's start closes the
  screenshot as it does now. The timeline does not change.
- It said nothing about an older build writing over a file with pins. Here such a file is version 2,
  which an older build leaves alone.
- It checked the picture's content so a replaced image could not inherit comments. Marks already
  follow the size and key checks, and pins follow the same ones. A content check would cover pins
  and not marks.
- It stored a file of anchors with a request, and named that file in the line. Here the words
  themselves go in the line, after the person's message, and `pins.json` is for agents' answers.
- It added Copy Markup Only, Copy Comments and a switch to hide badges. Each is one more choice
  before sharing. Clusters and the list keep the picture readable, and Send carries the words as
  text. A person who wants a picture without pins can delete them.
- It called the place a badge, and its entries comments in a thread. In the glossary a badge is an
  agent's name on a note, "comment" is an avoided name for a note, and a thread is a Codex thread.
- Its mocks showed a checkout page in a generic light style. The mocks Pete chose from used one of
  his own screenshots and Vignette's look.

## Not in this plan

- Resolving a pin, or hiding resolved pins. With one person and an agent, deleting a pin does the
  same job. It could follow step 4, when an agent's answer might mark a pin done.
- Comments on screen recordings, which are never drawn on.
- Pins in live ink, whose note is already words about one place.
