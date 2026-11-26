# The `show` command: dwell, shortcut, Send, log, errors and motion

Part of [Singling out existing screenshots: the agent API](../agent-single-out-api-2026-11-25.md), 2026-11-25. It follows [show-command.md](show-command.md). Pete's decisions are in [reuse-and-choices.md](reuse-and-choices.md#petes-decisions).

## How long the cards stay

Lone thumbnails leave on the corner's timer (`leaveCorner`), and the newest call sets the time.
An agent's push stays twice as long as a capture (`ui.thumbnailSeconds` × 2, 10 s by default),
since it is something to read. `show(_:)` picks the dwell from the card's `agent`, which is nil on
a person's screenshot, so it would give a shown card 5 s. `show` therefore sets the timer itself:
every call ends with `leaveCorner(after: ui.thumbnailSeconds * 2)`, cards already on screen
included, so a card with one second left gets the whole dwell again. The pointer over a card holds
the corner, as it does today. A card in the stack stays until the stack closes. The dim over the
other cards lasts the same dwell, from the newest call.

## The shortcut over shown cards

Today the shortcut over lone thumbnails keeps the cards that the recent stack also lists and drops
the rest (`StackEntrance`, `present`). A screenshot from last week that an agent just showed would
vanish at the press, which is the moment the person reached for it.

The shortcut keeps every card in a shown state on screen, as well as the recent ones.
Shown cards stay where they are drawn, at the bottom of the column, under the newest recent card,
and the recent cards enter above them. The column is then out of date order at its bottom until it
closes. The next shortcut lists the folder as usual.

The change reaches into `present(cards:)` as well as `StackEntrance`. `present` builds the new column from the
recent cards alone and removes every other card on screen, and `keptLift` and the entrance ranks
assume that order. So `openRecent` hands `present` the shown cards first (`keptShown`), below the
recent ones, and makes no second card for a shown file the listing also lists. `removeOverflow` skips a card in a shown state, as it skips cards in the annotator or a
stitch, so the limit never drops a card an agent showed. `docs/rules/stack.md` says the shortcut
"keeps the cards on screen" over lone thumbnails. Today that holds only for cards the recent
listing also lists, which every capture is. That sentence, now in `docs/rules/corner-presentation.md`,
says so.

Selecting lone thumbnails already makes the corner a stack of exactly those cards
(`stack(recent: false)`), so the person can Copy, Draw or Stitch the shown cards without the
shortcut.

## Cards not in the column

A screenshot older than the column's loaded cards (`OlderShots`) has no card yet. `show` makes
one and it joins as above. A later chunk of older cards skips a file that already has a card
(`addOlder`), so it never appears twice. In the recent stack it sits at the bottom, out of date
order, like a card `show` brought into the lone thumbnails before the shortcut.

A shown card that the person deletes leaves the column, and its shown state ends. Cmd+Z puts the
file back (`putBack`), and its card returns with no notice and no shown state. The agent's ask was
about the card the person deleted.

## Send and Reply on a shown card

A shown card offers what it offers today. A card with an origin, meaning an agent's push, a
published reply or a live ink note card, keeps Reply to that origin
(`ScreenshotRequests.origin(of:)`). `show` does not change where Reply goes.

A person's own screenshot has no origin, and Send there starts on the destination choice
(`DestinationChoice`, `docs/rules/send-start.md`). `show` adds one fact to that choice.
When an opening starts on a card whose shown state names a session, the opening keeps that
session as a fact for its Send, and the shown state ends. When the listing finds that session,
Send starts on it. That is the session that asked the person to look. Send's target settles once and never changes under the
pointer, so a `show` during an opening does not move that opening's target. Like the kept pick,
it lives in memory only. It comes before the kept pick, which says where the person has been
sending lately, since this session asked about this very image.

A send of a shown card writes the Sent record as any send does, and the card's tab then says
"Sent to *session*".

## The log and `[state]`

The command answers once:

```text
[show] ok files=["<name>","<name>"] agent=claude session=<id> joined=1 inColumn=1 inEditor=0 marks=2 after=0ms tag=<tag>
[show] warning <name>: its message is longer than 60 characters and was cut
[show] waits for drag
[show] ended <name> by=opened
[show] kept marks=2 <name>
[show] cleared marks=2 <name>
```

`files=` is a JSON array of names, as `[annotate] done files=` is, since screenshot names hold
spaces and U+202F. `joined` counts cards that came up or joined the column. `inColumn` counts
cards already on screen, which only got the notice. `inEditor` counts the card open in the
annotator. `marks` counts the agent's marks put on top. `kept` and `cleared` follow the person's
Keep and Clear.

`[state]` gives each card in `stack.cards` a `shown` field: `{"agent", "session", "message", "at"}`,
or null, and `agentMarks`, the count of the agent's marks on top. `stack.showsWaiting` counts the
calls waiting for the hand, and `stack.dimsUnshown` says whether the other cards are dimmed. The `shown` notice appears in the card's notice field like every other notice.

## Errors

Each error uses a code from `CommandError`. `show` runs the checks the actions run in
`AppDelegate.run(_:)`: the folder policy, then reserved replies, then missing files. It adds one
of its own: the card's header must read (`makeCard`). That check fits a recording too.
`Commands.isReadableImage`, which `annotate` uses, refuses one.

| Case | Answer |
| --- | --- |
| No `file=` | `missing-file no file given` |
| A file not in the folder, or gone | `missing-file <path>` |
| An agent reply that is not imported yet (`requests.isVisible`) | `missing-file <path>: an agent reply that is not imported yet` |
| A path outside the screenshots folder | `outside-watch-folder <path>` (`debug` lifts it, as for the actions) |
| A file whose header does not read (`makeCard` answers nil) | `unreadable-image <path>` |
| More files than `recentCount` | `too-many-files needs at most <n>, got <m>`, a new case in `CommandError` |
| Bad `marks=`, marks on a recording, or marks none of which can be drawn | `invalid-marks <reason>` |
| `session=` that is not a session of `agent=` | `ok`, after a `[show] warning` line, as `add` does |

A screen recording is allowed. It is a card like any other, and a click opens it in its app. An
iCloud file not downloaded yet comes up with its placeholder and downloads, as any card does
(`Thumbnailer.lookUp`).

## Several agents and sessions

Each call adds to the corner. None takes away cards an earlier call showed. When two sessions show
the same card, the newer call's notice and shown state win, as the newest notice does. A Codex
thread and a Claude Code session showing cards at once work the same way: each card names the
agent that showed it last. A call that arrives while an earlier one's cards are still shifting up
adds to the lift they have left (`shift`, `liftLeft`), as two captures in a row do.

## Motion and words

Every movement is one the corner already has: the slide-in, `shiftUp`, the scroll spring, the
slide-out, and the dim's fade. Each runs through `Settings.motionUI`, so `ui.motion` scales it and Reduce Motion makes
it 0. The dwell is time, not motion, so it is not scaled. Nothing appears or leaves in one frame.
The notice fades in and out as the other notices do.

There is no toast. What happened is said on the cards themselves. Every string is in
`docs/voice.md`, under "An agent showing a screenshot".
