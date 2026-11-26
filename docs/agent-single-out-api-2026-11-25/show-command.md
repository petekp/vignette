# The `show` command: parameters, mark and corner states

Part of [Singling out existing screenshots: the agent API](../agent-single-out-api-2026-11-25.md), 2026-11-25. The open choices are in [reuse-and-choices.md](reuse-and-choices.md#open-choices-for-pete).

## The proposal: one command, `show`

```sh
open -g -a "<app>" "vignette://show?file=<path>&file=<path>&agent=claude&session=$CLAUDE_CODE_SESSION_ID&message=<words>"
```

`show` brings existing screenshots to the corner and marks each one as shown by the agent. It
changes no file, no extended attribute and no drawing. Everything it sets lives in memory and ends
on its own.

### Parameters

| Parameter | Required | Meaning and limits |
| --- | --- | --- |
| `file=` | yes, one or more | Screenshots or screen recordings inside the screenshots folder, in the order the agent wants them read. A file named twice counts once, at its first place. At most `recentCount` files (30 by default, 0 to 1000), the most the corner's column keeps (`removeOverflow`). At 0, every call answers `too-many-files`. |
| `agent=` | no | The agent's name, read by `Agent.clean` as `add` reads it: any name up to 64 characters, with the vendor's logo for `claude` and `codex`. It names the agent on the mark. Without it the cards come up with no mark, which is `last` for the files named. |
| `session=` | no | The agent session showing them, read by `Agent.pushOrigin` as `add` reads it. Only a UUID of the client `agent=` names counts. Anything else logs a warning and `show` still answers `ok`. It decides where Send starts on these cards (see Send in [show-cases.md](../show-cases.md#send-and-reply-on-a-shown-card)). |
| `message=` | no | One line from the agent to the person. It is cut at a word to 60 characters, the length of a notice's second line (`docs/voice.md`), and a cut logs a warning. Open choice 1 asks whether to have it. Today `Commands.parse` reads `message=` raw for `live-ink-ask`, while `title=` goes through the form reader (`Commands.text`), which reads `+` as a space. The change moves `message=` to the form reader for both commands. `live-ink-ask` needs `debug`, and its callers encode with `encodeURIComponent`, which writes a plus as `%2B`, so they see no change. A caller that writes a space as `+`, as Python's `urlencode` does, now gets a space there, as it already does for `title=`. |
| `tag=` | no | Echoed in the answer, as `state` echoes it, so an agent can find its own line. |

The command answers with one line, as every command does: `[show] ok …` or
`[show] error <code> …`. It checks every file before it shows any. One bad file means no card
comes up, and the error names that file. The actions check files the same way, and an agent can
fix the one path and send the call again.

### What marks a shown card

Each named card gets a new notice, `shown`, which names the agent with its logo and, when given,
carries the agent's message as its second line.

| | What it is |
| --- | --- |
| Headline | "Shown by *Agent*", such as "Shown by Claude"; "Shown by an agent" for `agent=` with no name. Open choice 2 has the wording. |
| Second line | The `message=`, when there is one. |
| Tab | Unchanged. A person's screenshot keeps no tab or its Sent tab, and an agent's push keeps "From *Agent*". The tab says where a card came from and where it went, and `show` changes neither. |
| Look | Not chosen. Open choice 3 lists the variants to mock. |
| VoiceOver | The card's accessibility label leads with the headline. Vignette posts one announcement per call, such as "Claude showed you 3 screenshots". |

The notice follows the CardNotices rules (`docs/card-notices-2026-10-02.md`). It is one notice per
card, and the newest wins. A Copied, a send or a later `show` replaces it. A send still waiting
for its answer gets that answer after the `shown` notice took the card, so no failure is lost.

The *shown state* is what Vignette keeps about a shown card: the agent, the session, the message
and when it was shown. It is kept beside the card in `StackModel`, so it exists only while the card
is in the corner's column, and it follows a rename with the card. It ends at the first of these:

- the card leaves the column. Every removal goes through `StackModel.removeCards`: the slide-out's
  cleanup, the overflow, a stitch, a Delete, and the file leaving the folder. That one place ends
  the state, logged `by=left`;
- the card opens in the annotator. The opening reads the state for Send as it starts (see Send in
  [show-cases.md](show-cases.md#send-and-reply-on-a-shown-card)), and the state ends, logged `by=opened`;
- a later `show` of the same card replaces it with the newer agent, session and message, logged
  `by=replaced`.

The `shown` notice has no hold of its own, as a send waiting for its answer has none
(`CardNotices.post`), so no timer takes it down. It goes when the shown state ends, or earlier
when a newer notice takes the card. A notice the newer one replaced does not come back when that
one expires. The state stays, and still decides where Send starts.

A notice on a card keeps that card built in the long column (`StackModel.keptBuilt`). Because the
state ends whenever the card leaves the column, a `shown` notice never outlives its card and never
reappears on a later column.

### What it does to the corner, in each state

The rule throughout is the corner's own: a card that arrives on its own never takes a key from the
app the person is typing in, and only a hand makes the stack (`docs/rules/stack.md`,
`CornerPresentation`). `show` is not a hand. It never sends `.selected` or `.shortcut`, never
makes the panel key, and never activates an app. `scripts/check-app-activation.py` needs no
change, since `show` makes none of the calls it counts.

| Corner when `show` arrives | Cards | Order and scroll | Selection and focus | Keys |
| --- | --- | --- | --- | --- |
| Nothing showing | The named cards come up together as lone thumbnails, in one `present(cards:)`, sliding in staggered from the edge as a column does. | The first file named is at the top and the last at the bottom, so the column reads top to bottom in the agent's order. | None: lone thumbnails have no selection or focus. With two or more, a card's selection circle appears under the pointer, as on any lone thumbnails (`offersSelection`, `CardView.showsCircle`). | The person's app keeps them. |
| Lone thumbnails showing | Named cards already there stay in their slots and get the notice. The others join the bottom together in one `shiftUp(to:entering:scrollsHome:)`, in the order named. | The column drops back to the bottom as it does for a capture. | None. | Kept by the person's app. |
| The recent stack, keyed | Named cards in the column stay in their slots, in date order, and get the notice. The others join the bottom, as a capture joining an open stack does. | When none of the named cards is in view, the column scrolls to the first named card on the `relayoutDuration` spring (`scrollToReveal`), as an arrow key's focus move does. A card joining the bottom brings the column home, as a capture does. | Left alone. The person's selection is theirs, and `show` neither replaces it nor adds to it. The focus stays where it was. The focused card follows the pointer, so moving onto a shown card focuses it as usual. | The stack keeps them. |
| A stack made of the corner's own cards | As the keyed stack. | As the keyed stack. | As the keyed stack. | The stack keeps them. |
| The annotator open | A new shot never closes the annotator: the run answers `join` (`ThumbnailController.show`). The cards join the corner, which is narrowed beside the annotator when it is the stack. A lone card that is in the annotator has left the panel, so the cards come up beside the annotator as a capture's would. | As above. | As above. | The annotator keeps them. |
| The card itself in the annotator | Nothing is posted and no shown state is kept. A notice posted to a card in the annotator would travel home with the card and show when it lands (`isSeen`), and a lone card wearing a notice does not leave at once (`leavesAtOnce`). The person is already looking at this screenshot. The answer counts it under `inEditor`. | — | — | — |
| The corner sliding out | `show` waits until the slide-out ends, then runs on the empty corner. Today a capture that arrives mid-slide-out and is not one of the sliding cards goes through `present`, which removes the sliding cards with animations off. That looks like a one-frame disappearance. It has not been checked on screen. | — | — | — |
| A stitch converging | `show` waits until the converge ends. A card inserted while the pieces fly moves the slot they fly to ([corner-8](../state-machines/plausible-findings-run-to-toolbar.md#corner-8)). | — | — | — |

#### When the person's hand is in the corner

While the corner is busy, `show` waits. No one predicate says that today, so the change adds
one, `ThumbnailController.isBusy`. It is true while any of these holds:

- a card is pressed (`model.pressedCard`), or a flight is pressed (`FlightPress`);
- a card is dragged out (`model.draggedCard`);
- a drag-select is under way (`model.sweepCard`);
- a swipe has moved the column (`StackSwipe` not idle);
- a stitch is converging (`model.forming` not empty);
- the corner is sliding out (`model.slidingOut`).

Calls that arrive while it is true wait in a first-in, first-out list, and each runs in turn once
it is false. A second call waits behind the first, and never replaces it. A call that waited runs
against the corner as it is then, so a corner that closed meanwhile gets lone thumbnails. Each
wait logs `[show] waits for <press|drag|sweep|swipe|stitch|slide-out>`. The `ok` line comes when
the cards are up, with the wait as `after=<ms>`. A gesture ends when the person lets go, so the
wait has no limit of its own.

An agent's show is never urgent to the second. A card that moves while the person's hand is on the
column makes them miss or drop what they were reaching for. Today a capture that arrives mid-gesture does not wait: `insert` ends a
drag-select at once (`sweep.end()`). That gap is the same for captures, and this spec does not
change it. Open choice 8 asks whether to wait.

#### Live ink

Lone thumbnails do not hold the screen (`holdsScreen`), so `show` never stops live ink, as a
capture does not. A `show` that lands in a keyed stack changes nothing about who holds the screen.
How a lone thumbnail looks while the person is inking has not been checked. Check it with the
build.
