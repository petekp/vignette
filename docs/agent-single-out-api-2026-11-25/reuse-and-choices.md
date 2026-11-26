# The `show` command: what it reuses, the skill, and the open choices

Part of [Singling out existing screenshots: the agent API](../agent-single-out-api-2026-11-25.md), 2026-11-25.

## What it reuses, and why it is a new command

`show` reuses:

- `ThumbnailController.post` and `CardNotices` to put the mark on;
- `present(cards:)` and `shiftUp(to:entering:scrollsHome:)` for every movement;
- `scrollToReveal` for the scroll;
- `Agent.clean` and `Agent.pushOrigin` for `agent=` and `session=`;
- the actions' file checks in `AppDelegate.run(_:)` (policy, reserved replies, missing files).
  Today they live inline in the `default:` branch. They move into one function that the actions
  and `show` both call, so the two never disagree about which files a command may name.

It adds:

- one entry point, `ThumbnailController.show(_ call: ShowCall)`. The one-card
  `show(_:)` cannot serve: each call brings one card in its own motion, and each joins the bottom,
  so a list would arrive as separate slides with the first file named at the bottom. `post` brings
  a card up through that same `show(_:)`, so `show` posts the notice only to cards already in the
  column. `putBack` cannot serve either: it runs only on an open stack, and it selects the cards
  it returns and moves the focus to them;
- the shown state in `StackModel`, ended in `StackModel.removeCards` and at an opening's start;
- `ThumbnailController.handInCorner` and the list of calls waiting on it (`ShowQueue`);
- the second group of cards in `present(cards:)`, and the skip in `removeOverflow`;
- `CommandError.tooManyFiles`.

It replaces nothing in the code. It supersedes `add` as the way to point at a file already in the
folder: the skill says to use `show` for that. A new URL command is a contract scripts will rely
on, so the change that builds it also adds an ADR in `docs/adr/`. `last` stays as it is. Folding it into `show` with
no files would change a working contract for no gain to anyone.

`show` is a fixed command in `Commands.fixed`, not an action in `Config.actions`. An action is
something a person does to the selected cards, with a place in the strip, on the cards or under a
key. It receives only the screenshots (`ShotAction.run`), so it cannot read `agent=`, `session=`
or `message=`.

Each existing command fails a current need that `show` meets:

- `add` cannot point at a file without rewriting it. Its in-folder path exists to re-push an
  agent's own image, as with new marks, and the rewrite is right for that. Changing `add` to
  sometimes not record would give one command two meanings, decided by where the file is.
- `annotate` takes the screen and the keys and starts a run. Looking is a smaller ask than
  drawing.
- `recent` takes no files, and it takes the keys, which only a hand may do.

## Changes to the skill

`skills/vignette/SKILL.md` gets a section "Point the user at screenshots they already have". It
gives the `show` URL, the parameters above, and the `[show]` answer. It says to use `show`, never
`add`, for a file already in the screenshots folder, since `add` relabels the person's
screenshot as the agent's and drops its title. It says the answer can come later than usual while
the person's hand is in the corner. The skill's version goes up by one.

## Pete's decisions

Pete answered the open choices on 2026-11-25. The build follows these answers where they differ
from the recommendations above.

1. `show` carries the agent's words. `message=` holds up to 60 characters, cut at a word. It also
   takes `marks=`, in `add`'s format and limits, drawn on the first file named. The marks sit on
   top of the person's drawing until kept, in the agent's colour, on the card and in the editor.
   One click keeps them, joining the drawing as one undo step, or clears them. The file is untouched
   until Keep. The controls are the system's own buttons: Clear in the bordered style and Keep in
   the prominent one. They follow the marks (Pete, 2026-11-25: "Buttons wherever the marks show"):
   on the card's notice, on a band of their own once the notice has gone, and in a bar at the top
   of the editor.
2. The headline is "From Claude", the words of the agent's tab. A card never says the same words
   twice: while the notice's headline repeats the tab, the tab gives way (`CardView.repeatsNotice`).
3. A shown card wears the notice, and the corner's other cards dim while shown cards are up. The
   dim's amount and its fade are `ui.shownDim` and `ui.shownDimFade`, in the tweaks panel's
   "Shown by an agent" group. The fade is a spring through `Settings.motionUI`.
4. Lone thumbnails stay 10 seconds, as an agent's push does, and the pointer over a card holds them.
5. The shortcut keeps shown cards at the bottom of the recent column, and the overflow never drops
   them.
6. Send starts on the session that showed the image first, before the kept pick
   (`docs/rules/send-start.md`).
7. `add` refuses a file in the folder that has no agent attribute, with an error that names `show`.
8. `show` waits while a press, drag, sweep, swipe, stitch or slide-out is under way, then runs the
   waiting calls in order.
