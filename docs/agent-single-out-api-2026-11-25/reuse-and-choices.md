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

- one entry point, `ThumbnailController.show(_ shots: [Screenshot], by: Shown?)`. The one-card
  `show(_:)` cannot serve: each call brings one card in its own motion, and each joins the bottom,
  so a list would arrive as separate slides with the first file named at the bottom. `post` brings
  a card up through that same `show(_:)`, so `show` posts the notice only to cards already in the
  column. `putBack` cannot serve either: it runs only on an open stack, and it selects the cards
  it returns and moves the focus to them;
- the shown state in `StackModel`, ended in `StackModel.removeCards` and at an opening's start;
- `ThumbnailController.isBusy` and the list of calls waiting on it;
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

## Open choices for Pete

1. **Whether `show` carries the agent's words.** The choice is a `message=` of up to 60
   characters on each card's notice, or no words. Recommendation: carry them. A card that comes up
   without a reason sends the person back to the terminal to find out why. One line on the card
   says it where they are looking.
2. **The headline's words.** Candidates are "Shown by Claude", "Claude pointed this out" and
   "From Claude". Recommendation: "Shown by Claude". It says what happened in three words, claims
   nothing about what the agent wants, and does not borrow "From", which the tab uses for where a
   card came from.
3. **How a shown card looks.** This is a visual choice, to mock as 2 to 4 variants through Vignette
   before building:
   - (a) the notice alone: the agent's logo, the headline and the message, on the card the way a
     send's notice sits;
   - (b) the notice, plus a ring in the agent's indigo that grows out of the card's resting
     border, as the focus ring does. It risks a third ring colour beside the accent for selected
     and the white for focused;
   - (c) the notice, plus one spring lift of the card as it arrives or is marked in place;
   - (d) the notice, plus a dim over the corner's other cards while shown cards are up, for a
     corner that already holds several.
4. **How long shown lone thumbnails stay.** The choice is the agent push's dwell (10 s, held by
   hover), or longer. Recommendation: the push's dwell. It is the corner's existing rule for
   "something to read", and the person can bring the cards back with the shortcut (choice 5). A
   longer dwell would also need a new tuned default in `UITweaks`.
5. **The shortcut over shown cards.** The choice is to keep them at the bottom of the recent column,
   or to let them go as the code does today. Recommendation: keep them. The shortcut is how the
   person reaches for cards in the corner, and losing the ones an agent just raised breaks that.
6. **Where the shown session sits in Send's choice.** It can come before the kept pick or after it.
   Recommendation: before. The kept pick says which session the person has been sending to lately.
   The shown state says which session asked about this very screenshot, which is the more specific
   fact. It changes the rule that the kept pick comes first. That rule's point, one rule that says
   where Send starts, still holds with one more fact in it.
7. **Whether `add` should refuse to relabel a person's capture.** Today `add?file=<in-folder
   capture>&agent=claude` turns a person's screenshot into "From Claude" and drops its Sent record.
   Recommendation: a separate change after `show` ships. `add` would answer `unsupported-type`
   for a file that has no agent attribute, naming `show`. It changes `add`'s contract, so it needs
   its own yes.

8. **Whether `show` waits while the person's hand is in the corner.** The choice is to wait, as
   above, or to run at once as a capture does. Recommendation: wait. A card that slides in under a
   drag or a sweep moves what the person is reaching for. Captures have that gap today. The
   cost is the busy predicate and the waiting list, and an answer that can come seconds late.
