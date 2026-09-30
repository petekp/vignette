# Trailer v3, the overnight run (2026-09-29)

Pete asked, before going to sleep, for five things. This file is the task list and the record of
what was done, decided and left. The story and its reasons are in
`docs/trailer-v3-brief-2026-09-28.md`; the recording pipeline is in
`docs/trailer-pipeline-2026-09-26.md`.

His words:

- Revamp the mock app to bring its level of polish up significantly. Nothing cheap or vibecoded.
- Move the trip from Japan to Tuscany, Italy.
- Refine the transitions between scenes: a rhythm and beat everything moves to, nothing arbitrary,
  no jank or missing animations, the product shining.
- A much slicker outro with the Vignette logo and app icon, choreographed with intro and exit
  animations.
- Update GitHub and the landing page with this video.

"This video" is read as the real trailer, recorded live from the app by `media/trailer/trailer.py`
and following the animatic. The site says the trailer is "Recorded live", and the brief's plan
was always a real take after the animatic.

## Tasks

1. **Postcard, redesigned for Tuscany.** A new look for `media/trailer/stage/postcard/`: the
   itinerary, Stays and Packing pages, the map, the day pictures and the type. Same structure, so
   the story's marks still land on a map stop, a day card and the highlight day.
2. **The story's content moves to Tuscany.** Days, map stops, the arrow's stop, Claude's lines,
   the variants, the stage `CLAUDE.md`.
3. **Storyboard and animatic assets re-rendered** from the new pages: the itinerary before, after
   Claude's first turn, and final; Stays; the crops the loops use; Claude's three variants.
4. **The outro.** An end card with the app icon and the wordmark, with an entrance and an exit,
   in the animatic first and then in the cut (`cut.swift`).
5. **The rhythm pass.** One tempo for the film. Clicks, landings, caption changes, camera moves
   and dissolves fall on its beats. Every motion the app makes is present in the animatic, and
   nothing appears or leaves in one frame.
6. **The real take.** `drive.py`, `beats.toml` and `trailer.py` move from the mew game to Postcard
   and perform the film's beats. Record, cut, review frame by frame, and repeat until it holds up.
7. **Publish.** The cut goes to `site/trailer.mp4`, `site/trailer.webm` and
   `site/trailer-poster.jpg`, and the README and landing page point at it. Only the video's lines
   of `README.md` and `site/index.html` are committed: their other uncommitted lines describe the
   plugin and the updater, which no release has yet. Pushing `main` deploys the site.

## Progress

All seven tasks are done. The trailer is live on vignette.pete.design and in the README, in
commit `8bc1aad` on `main`. It runs 60 seconds, from take `2026-09-29-002838`.

- **Postcard.** A light, warm look: paper background, white cards, Iowan Old Style headings,
  terracotta for what matters and olive for status. The brand mark is a postage stamp. The map is
  drawn, with hills, the Arno, a dotted route and three numbered stops. Each day card has its own
  drawn picture: Florence at dusk, the Chianti vineyards, and a cypress avenue at sunrise.
- **The story in Tuscany.** The arrow runs from the map's second stop, Greve, to the Chianti day,
  with the note "number the days". The box goes around the Oct 14 day, Val d'Orcia at sunrise,
  with "make this pop, options?". Claude's three versions are A tinted, B with a Highlight flag,
  and C with the picture filling the card. The answer is a box around C and an arrow from B's flag.
- **The notes are the app's real size.** A person's note is 24 pt, not the 18 the old storyboard
  drew, so the day cards got shorter and both notes fit on one line.
- **Claude's marks are violet.** Its old colour, white, would vanish on the light page.
- **The outro.** The film scales down, blurs and fades to the background. The icon springs up,
  the wordmark wipes on from the left, then the tagline and the footer. They leave in reverse
  order. The first frame dissolves back in, so the film loops. `cut.swift` renders it and the
  animatic matches it.
- **The rhythm.** One beat is 0.5 s (`[rhythm]` in `beats.toml`). The driver presses and clicks on
  beats. The cut starts and ends each span on a beat, rounds dissolves to half beats, and puts
  caption changes and camera moves on half beats.
- **The take.** `drive.py` performs the Postcard story. It measures the page's parts with headless
  Chrome rather than using numbers typed in, so a change to the page moves the marks with it.
  Five takes, four fixes:
  - Take 1 stopped before recording. The trailer's Claude Code asked whether to follow the files
    your own `~/.claude/CLAUDE.md` imports. The driver now answers no before the take, so the
    session never reads your private rules.
  - Take 2: Claude Code answered its first prompt before the driver started watching. The
    driver now reads the transcript for the answer.
  - Take 3: headless Chrome sometimes printed the page before the measuring script ran, because
    the script waited a frame after `load`. It now measures as it runs.
  - Take 4: the driver drew the pick box without choosing the rectangle tool, so the Return that
    should have ended the note sent a Reply. It now picks R first, and it presses Return only
    while a note is being typed.
  - Take 5 ran end to end.
- **Left alone.** `media/trailer/stage/mew`, the old game, is no longer used and is still there.
  The feature loops (zoom, recent stack, stitch and the rest) were not re-recorded.

## The cut

| Caption | Seconds |
|---|---|
| Take a screenshot ⌘ ⇧ 4 | 0.0 to 3.8 |
| Click to draw on it | 3.8 to 9.5 |
| Explain what you want, visually | 9.5 to 23.5 |
| Send it over ⌘ ↩ | 23.5 to 26.8 |
| Your agent can show you things, too | 26.8 to 36.0 |
| Mark it up and send it back ↩ | 36.0 to 50.0 |
| Claude builds it | 50.0 to 54.5 |
| End card | 54.5 to 60.0 |

- **Three spans, two dissolves.** The first dissolve covers Claude's first turn. The second lands
  on the finished page, because Claude changes the page a file at a time and the flag shows
  unstyled for about a second in between.
- **Checked frame by frame at 2 and 10 frames a second.** Every large change between two frames
  comes from the app, a camera move or a planned dissolve.
- **The files:** `trailer.mp4` is 18.9 MB and `trailer.webm` 11.9 MB, the same rate as v2's.

## For you to decide

- **Length.** The film is 60 seconds; the animatic was 41. Claude's real time is cut, but the
  hand's pace and the app's flights play at real speed. A take with shorter waits in `drive.py`
  (the `rest=3` pauses before each drawing) would save a few seconds. Claude's options might
  come out differently in a new take, and these came out well.
- **Session names.** Vignette names a Claude Code session only by the title Claude Code writes
  (`ai-title`). A name given with `claude -n` or `/rename` is recorded as `custom-title`, which
  Vignette ignores, and such a session has no `ai-title`, so Send lists it as "New session in
  <project>". The trailer's session is no longer named for that reason. The toolbar shows the
  project, so the film never showed it. Fixing it is a change to `AgentConnection.swift`.
- **Not committed.** The trailer pipeline, the storyboard and these docs are still uncommitted.
  The pipeline depends on the agent plugin, which `main` does not have yet.
- **The stray `site/stack-and-editor.png`** is no longer used by the page and is still deployed.
