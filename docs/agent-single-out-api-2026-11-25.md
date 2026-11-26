# Singling out existing screenshots: the agent API

Spec, 2026-11-25, built the same day (`docs/adr/0031-show-points-at-screenshots-and-add-refuses-the-persons-own.md`).

Pete asked on 2026-11-25 whether an outside agent, such as Claude Code or Codex, can single out
one or more past screenshots, so the person's attention goes to them. No command does that today.
This spec gives one new command, `show`, and says what it does to every part of the corner,
the stack, the annotator and Send. Pete's decisions on its open choices are in
[reuse-and-choices.md](agent-single-out-api-2026-11-25/reuse-and-choices.md#petes-decisions).

Terms are the glossary's (`docs/glossary.md`). A *card* is one screenshot in the corner. A
*lone thumbnail* is a card that comes up in the corner on its own and leaves after a few seconds.
The *recent stack* is the column the shortcut opens. The stack is *keyed* when it holds the
keyboard. A *notice* is what a card says after something happened to it, such as Copied.

## What exists today

Every agent-facing command is a `vignette://` URL. `AppDelegate.run(_:)` dispatches it, and
`Commands.swift` holds the fixed commands and the `CommandError` codes. The actions come from
`Config.actions`. This table lists each command an agent could reach for, and why none of them
singles out an existing screenshot.

| Command | Takes files | What it does to the screen today | Why it does not single out |
| --- | --- | --- | --- |
| `add?file=` from outside the folder | one, from anywhere | Copies the image into the screenshots folder and shows the copy as a lone thumbnail, or as a new card at the bottom of an open stack (`FolderWrites.add`, `ThumbnailController.show`). | A past screenshot gets a second file and a second card. |
| `add?file=` inside the folder | one | Copies nothing. It shows the file's card the same way, through the same `show(_:)`. | It changes the person's screenshot. With `agent=` it writes "From *Agent*" on it and removes its Sent record and its session (`Agent.record(agent:origin:on:)`). With or without `agent=`, it removes any agent title the call does not repeat (`Agent.record(title:on:)`) and the fingerprint Reply uses to tell nothing changed (`Agent.forgetSentDrawing`). On a card already in an open column it shows nothing new, because `insert` skips a card the column holds. |
| `last` | none | Shows the newest screenshot or recording as a lone thumbnail (`openLast`). | Newest only, and no mark says an agent asked. |
| `recent` | none | Toggles the recent stack. The stack takes the keys (`pressRecent`, `CornerPresentation`). | No files, and it takes the keyboard from the person's app. Only a hand may do that (`docs/rules/stack.md`). |
| `annotate?file=` | a list | Opens the first file in the annotator and queues the rest. | It takes the screen and the keyboard, and it starts an annotation run the person did not ask for. |
| `copy`, `open`, `paths`, `copy-annotated`, `stitch`, `trash`, `unsend` | a list | Act on the files. | They change the clipboard, the folder or a send. None is for looking. |
| `dismiss`, `cancel` | none | Close the corner, or the annotator without copying. | They take things away. |
| `state`, `help` | none | Write one `[state]` or `[help]` line to the log. | They read only. |
| `reply`, `requests` | an envelope | Take an agent's drawing back for a screenshot request, or list and clear the requests. | They answer a send. A past screenshot the person never sent has no request. |
| `live-ink-*`, `install-skill`, the labs, `tweaks`, `settings`, `restore-apple-defaults` | none | Live ink, setup and debugging. | They are not about the corner's cards. |

`add` makes a second file only when it is given a file outside the folder. Given a file inside it,
`add` shows the existing card and relabels it.
The skill (`skills/vignette/SKILL.md`) does not warn agents about this.

## The spec

The proposal is split into three files:

- [show-command.md](agent-single-out-api-2026-11-25/show-command.md): the command, its parameters, what marks a shown card and when the mark ends, and what it does to the corner in each state;
- [show-cases.md](agent-single-out-api-2026-11-25/show-cases.md): how long the cards stay, the shortcut over shown cards, cards not in the column, Send and Reply, the log and `[state]`, errors, several agents, and motion and words;
- [reuse-and-choices.md](agent-single-out-api-2026-11-25/reuse-and-choices.md): what it reuses, why it is a new command, the change to the skill, and the open choices for Pete.

## Review

One reviewer, who did not write this spec, checked it against the code. These are the changes it
led to:

- Several cards now come up through a new entry point. The draft had them come up through `post`,
  which would have brought each card in its own motion, with the first file named at the bottom.
  The draft's `putBack` comparison is gone too, since `putBack` selects the cards it brings back.
- `show` sets the corner's timer itself. Through `show(_:)`, a person's screenshot would have
  stayed 5 s, not 10, and a card already on screen would not have been renewed.
- The shown state now lives beside the card in `StackModel`, and `StackModel.removeCards` ends it.
  The draft named endings that nothing in the code would have sent. A notice with no hold would
  have stayed after the corner closed and come back on the next column.
- A card open in the annotator now gets nothing. The draft said nothing would change on screen,
  but a notice posted to it would have shown when it landed.
- `message=` reading is now stated as a change. Today it is read raw for `live-ink-ask`, not
  through the form reader `title=` uses.
- The busy predicate is now defined, with a waiting list, and it includes a converging stitch and a
  slide-out. The review found no existing predicate, and asked what a second call does while the
  first waits.
- The shortcut change now names the work in `present(cards:)` and `removeOverflow`, and the
  sentence in `docs/rules/stack.md` that it corrects.
- Smaller corrections. Selection circles on lone thumbnails show under the pointer. `agent=` takes
  any name. `add` without `agent=` still drops a title and the Reply fingerprint. A `recentCount`
  of 0 refuses every call. A Delete and Cmd+Z of a shown card are covered. The build adds an ADR.
