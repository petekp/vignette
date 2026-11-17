# Live ink's result cards

`docs/live-ink.md` has the rest of live ink's rules.

When a session's turn ends with no reply, Vignette looks at the window again (`LiveNoteCards`,
`LiveChange`).

- **The before picture.** The note's own capture gives the part of the window round the ink: the
  ink's shapes with 64 pt round them, inside the web page when there is one (`LiveNoteCards.before`).
- **The comparison.** At the turn's end it captures the window twice, half a second apart, and
  compares that same part of the window on a grid of 3 pt cells of colour. A cell counts when its
  red, green or blue moved more than 24 of 255 and did not move between the two later captures.
  That leaves out a caret or a spinner. Grey alone missed a green button turned red, since the
  two are about as bright. Only the cells under the ink, its shapes with a 12 pt margin, decide.
  The ink's part changed when at least 2% of those cells counted, and at least 4.
- **Changed.** The window as it is now becomes the result card, from the session
  (`[live-ink] result card`, with `notes=` for the notes on that window it answers). The notes it
  answers say nothing more, whether or not their own part changed, and each takes a late answer
  on the card. An answer that comes after it, for as long as a turn may run (30 minutes), is
  drawn on that card, each mark at the words it names in the card's picture,
  with no page to keep the words to. It joins the card's drawing rather than making a second card.
- **Changed, in a window in front.** No result card when the window is the frontmost window of
  the frontmost app, on the screen, as the change is measured: the person is using it and sees the
  change (`LiveNoteCards.isInFront`, `[live-ink] no result card: the window is in front`). The notes
  the card would have answered say Done in *project*, as when nothing changed. An answer that comes
  after it, for as long as a turn may run, is drawn on a fresh capture of the window, as an answer
  during the turn is. A minimized window, or one on another Space, is not in front, so its card
  still comes.
- **Unchanged, or can't tell.** No result card. The note's card says Done in *project*
  (`[live-ink] done with no result card`). A window that closed, was minimized or changed size
  can't be told.
- **Vignette stopped waiting.** Nothing more. The card already said Sent to.
- **One known gap.** The part compared stays at its place in the window. So content the session
  moved away counts as a change there, and so does content the person scrolled.
- **The log.** `[live-ink] landed changed=` or `[live-ink] nothing changed under the ink` gives
  the outcome.
