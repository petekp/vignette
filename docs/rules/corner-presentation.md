# Who holds the corner's keys

This file says how the corner decides between lone thumbnails and the stack, and who holds the
keys. The rest of the stack is in `stack.md`.

- `CornerPresentation`, a pure reducer, decides four things about the corner. It decides whether
  the corner shows lone thumbnails or the stack, and when the panel takes the keys and gives them
  up. It decides when the backdrop and the watch for a click outside are on. And it decides when
  the focus goes back (`FocusReturn.restore`): to the Vignette window the session began in, when
  that was Settings, setup or the tweaks, and otherwise to the app before Vignette. `CornerKeys`
  runs its effects. It holds the panel's keys, the backdrop and the `OutsideClick` privately, so
  `ThumbnailController` can only send it events (`keys.send`). `acceptsKeys` can be set only in
  `CornerKeys.swift`. Every event with effects logs one `[corner] <event> -> <mode> effects=…`
  line. `Tests/CornerPresentationTests.swift` has the table and a random-sequence test of the
  invariants. Esc, a click outside and a swipe away reach it as dismissals. Esc clears a selection first, and the
  controller does that itself. The editor is open to it exactly while the annotation run is active: the controller
  sends `editorOpened` and `editorClosed` on that edge, with the run's `RunEnding`.

  The rule is that the backdrop goes with the keys. The stack has both, and lone thumbnails have
  neither. `CornerKeys` shows the backdrop and starts the watch for a click outside whenever an
  event makes the stack, and stops both whenever one ends it, so no effect can split them. A card that arrives on its own, from a capture or an agent's push, never takes a key
  from the app the person is typing in. Only a hand makes the stack: the shortcut, a selection in
  the corner (`.selected`), or Esc out of the editor while other cards are in the corner. That Esc
  makes them the stack once the card lands (`cardLanded`). Becoming the stack by any of these takes
  the screen from live ink (`onTakesScreen`), and the corner's own cards becoming it logs
  `[stack] corner became the stack`.

  The shortcut takes the keys at the press, before the folder is listed (`holdKeys`), so an Esc
  pressed while the stack is still coming closes it. It brings the panel up if the panel is down.
  The panel can be down while the corner still counts as lone thumbnails, as after a lone card's
  editor closes. `[stack] keys held` logs the press. The next `[stack] keys … after=<ms>` line gives
  the time from the press until the stack, with its cards, takes the keys. A zoomed editor springs
  back to the fit before it closes, so the listing can finish first; the stack then focuses a card
  only once the opened card lands. Over lone thumbnails, or over a stack the corner became, the shortcut keeps
  the cards on screen that the recent listing also lists, and every shown card (`stack.md`), and brings the older ones in above them (`StackEntrance`). The next press
  closes it.

  While a card is in the annotator the panel gives up the keys so typing reaches the editor. It
  gives them up at `editorOpened`, which `perform(.prepare)` sends right after the annotator's
  window has taken them, so the keys pass from one to the other instead of being nobody's for the
  length of the flight. `RunEnding` says how the run ended, and so where the keys go next. The
  shortcut keeps them for the stack. Any other hand sends the focus back, and a stack takes the
  keys again when the card lands.
