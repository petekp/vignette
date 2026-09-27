# Recording the trailer again, by script (2026-09-26)

The trailer in `docs/trailer-2026-09-24.md` is made by one command, `media/trailer/trailer.py all`.
It builds a copy of the app from the current source, sets the stage, performs every beat while it
records the screen, and cuts the trailer from the recording. It takes about three minutes.
Captions, timing and framing live in `beats.toml`, so rewording or retiming needs only
`trailer.py cut`, which takes half a minute.

The current cut is in `media/trailer/out/cut/`: `trailer.mp4` (4.1 MB), `trailer.webm` (2.4 MB) and
`poster.jpg`, 20.8 seconds at 1600 × 1000 and 60 frames a second. Nothing is committed or pushed.

The stage has since moved to a desktop, with real Claude Code in a terminal and the game in
Chrome beside it (`docs/trailer-desktop-2026-09-26.md`). The sections below say where that changed
how a take works. The cut table and the decisions describe the second cut, which was recorded
on the old full-screen stage. No take has been recorded on the desktop yet.

It is the second cut. The first joined its beats with hard cuts, and Pete found them sudden: at
13 seconds it jumped from Claude's card, close up, to the empty game, and then showed something
else. The second plays the take continuously and dissolves only where it skips time.

## Where it lives

`media/trailer/`, in the repo. `out/` is ignored by Git.

| File | What it is |
|---|---|
| `trailer.py` | The command: `build`, `claude`, `record`, `cut`, `events`, `all` and `restore`. |
| `beats.toml` | The spans of the take the cut keeps; each beat's caption, keys and camera; the stage; the marks. The file to edit. |
| `drive.py` | The performance: sets the stage and drives each beat. |
| `cut.py` | Turns a take and `beats.toml` into a plan of frames, then encodes the trailer with ffmpeg. |
| `record.swift` | Records the screen with ScreenCaptureKit and stamps the first frame's time. |
| `stage.swift` | The desktop's wallpaper, placing a window, a check of which window is under a point, and saving the pasteboard. |
| `cut.swift` | Renders the plan: crops, dissolves, captions and key caps, into a ProRes master and the poster. |
| `stage/mew/` | The game, copied from `~/Code/mew`, so the trailer does not depend on that folder. Its `CLAUDE.md` tells the trailer's Claude Code how level 4's layout works. |
| `out/` | The stage copy of the app, the helpers, the takes and the cut. |

`trailer.py events` lists a take's events with their times, which are what `beats.toml` writes
times against.

## How it works

- **The app is a stage copy.** `build` copies the source to `out/app` and builds it as
  "Vignette Demo" with the bundle id and URL scheme from `project.yml` plus `.demo` and `-demo`. So
  it has its own settings, log, drawings and URLs, and never touches yours.
- **The stage copy talks only to the trailer's herdr session, and no Codex.** `build` points the
  app's herdr path at `out/stage/bin/herdr`, which runs herdr with `--session vignette-trailer`.
  That session's one pane runs the trailer's own Claude Code. The Codex path list is empty. So Send
  and Reply reach a real Claude Code, the toolbar shows none of your sessions, and nothing reaches
  one of them.
- **The trailer's Claude Code has its own config.** `trailer.py claude` puts it in
  `out/stage/claude` (`CLAUDE_CONFIG_DIR`), with the skill patched for the stage copy's URL scheme
  and herdr's hook, and signs it in once. It never reads your `~/.claude`.
- **The whole performance is one take.** The plan had one take per beat. Reaching beat 7's state
  needs beats 1 to 6 anyway, so a take performs them all and the cut picks
  each beat's span from it by the events. A failed check ends the take with its reason, and the
  next command runs it again from the start.
- **Every action is checked first.** Before a click, the window under the point must be the stage
  copy's. Before a key, the stage copy's editor must hold the keys. Every `[state]` read must come
  from the stage copy's bundle and settings file.
- **Times come from one clock.** The recorder stamps its first frame with the host clock, and the
  driver logs each action on the same clock, `time.monotonic()`. App log lines are converted from
  wall-clock time.
- **The cut is spans of the take, with dissolves between them.** `beats.toml` lists the four
  spans the cut keeps. Inside a span the take plays at its own speed. Where the cut skips ahead,
  the next span dissolves in over the end of the one before. A skip over a still picture at the
  same framing does not show, so the cut skips only where the picture is still, or where the
  change is the point: the two marks that appear while the camera pulls back, and the scene that
  fills in while Claude works.
- **The beats lie over the spans.** A beat is a caption and camera moves, placed by events. The
  camera and the captions run on the cut's own clock, so neither jumps at a span's edge. A caption
  turns into the next: the pill changes width, the old words fade out, and then the new ones fade
  in.
- **The camera** is a crop of the recording. Each move eases from wherever the camera is, as a
  zoom: the point the two rects share stays put, and the width changes by the same ratio in each
  step. Each rect is made 16:10 and kept inside the game. It is never narrower than 800 points, so
  no recorded pixel is enlarged. The editor already fills about 80% of the screen, so the camera
  goes closer only on one mark, on Claude's sketch and on Claude's card.
- **The trailer loops without a jump.** Its last 0.8 seconds dissolve back into its first frame,
  and the last caption turns back into the first.
- **Nothing is sped up.** The cut removes time only between spans. Inside a span, the app and the
  pointer move at the speed they moved in the take.

## What a take changes on this Mac

A take takes over the screen, the pointer and the keyboard for 5 to 8 minutes, most of it Claude
working. Do not use the Mac while it runs.

- **The Dock hides** for the take, since it covers the bottom of the game, and shows again after.
- **The pasteboard** is saved before the take and put back after, since Send and copying replace it.
- **Your own Vignette keeps running.** The take never sends it a URL, a key or a click.

If a take is interrupted, `trailer.py restore` shows the Dock again, puts the pasteboard back,
stops the stage copy, and closes the take's Chrome, Ghostty and herdr session.

## The cut

| Caption | Seconds | What plays |
|---|---|---|
| Take screenshots as usual ⌘ ⇧ 4 | 0.0–4.2 | The region drag, the thumbnail, and a click that lifts it into the editor. The camera follows it toward where the moon goes. |
| Mark it up | 4.2–7.9 | The moon's box and its note, close up. The camera pulls back while the other two marks dissolve in. |
| Send it to your agent ⌘ ↩ | 7.9–9.2 | Send, and the editor closes. |
| It builds what you marked | 9.2–10.8 | The scene fills in through a dissolve, which stands for Claude's working time. |
| It sketches the next step | 10.8–13.8 | Claude's card slides in and the camera moves in on it. Most of its five seconds are skipped while it is still. It slides away as the camera pulls back. |
| Double-tap right Shift to get it back ⇧ ⇧ | 13.8–16.7 | The stack slides in, and Claude's card flies into the editor. |
| Change what you don't like | 16.7–18.3 | The middle ledge dragged onto the water tower. |
| Send it back ↩ | 18.3–20.8 | Reply, and the card flies home. Then the dissolve back to the start. |

Beat 4, the card dragged into Claude Code, is off: it needs a real terminal on screen.

The cut was checked frame by frame. Every large change between two frames comes from the app or
macOS: the capture, the two flights into the editor, the editor closing after Send, and the flight
home after Reply. None comes from the cut.

## Decisions for you

Each is one line in `beats.toml` unless it says otherwise. Recommendation first.

1. **Beat 3 sends with ⌘↩ instead of copying.** With a session to send to, ⌘↩ is Send now, not
   Done as in the storyboard. Sending shows both directions of the loop and needs no terminal, so
   beat 4 is not needed. After Send the card flies home, as it does after Done, without the Copied
   mark.
2. **Beat 9 is Reply, on Return.** Claude's card names the session it came from, so its toolbar
   offers Reply, not Send and a menu of sessions. This also keeps a session list off screen.
3. **Length: 20.8 seconds against the storyboard's 15.** The app's own motion at real speed and a
   hand's pace take the rest. Each span's `from` and `to` trims it.
4. **The history opens by URL, not a real double tap.** The keycaps say ⇧ ⇧. The stage copy is not
   trusted for Accessibility, and a real double tap would also reach your own Vignette when its
   shortcut is the double tap. The stack slides in the same way either way.
5. **Captions sit top left, 34 px at 1600 wide,** as in the storyboard. At phone width they come out
   at about 8 px. That is still your open decision 1 in the storyboard.
6. **The poster is the editor with all three marks,** just before Send, once the caption has
   settled.
7. **"a city behind" is typed with the Text tool.** A note typed after its box would go to the right
   of the box and across the water tower's box.
8. **The scene fills in through a dissolve,** 0.6 seconds long. The page swaps in one frame in the
   take, and the dissolve is where Claude's working time is skipped. A hard change there read as
   sudden. `dissolve` on the third span sets it.
9. **The trailer loops by dissolving back to the start.** The scene loses the moon, the city and
   the water tower as it goes. `loop = 0` ends on the last frame instead.
10. **A new take would give two moments more room.** The drawing is fully on screen for about
    0.5 seconds before Send, and the moved ledge for about 0.5 seconds before Reply. A take with a
    longer pause before each would hold them longer without slowing anything.

## Seen in the app, not changed

- **Reply falls back to Send when a session id is uppercase.** `add` lowercases `session=`
  (`Agent.cleanSession`), and `ToolbarOffer` compares it with herdr's ids as herdr gives them. Real
  Claude Code ids are lowercase, so this shows only with an id typed by hand, as the stage's first
  one was.
- **Send from a lone thumbnail closed the editor in one frame.** Fixed on 2026-09-26: `close`, which
  Send and Esc share, now flies the card home from a lone thumbnail as well as from the stack.
- **After Send, the toolbar's button says "Send ⌘↩" again while it fades out.** It said
  "Sending…" until the editor closed.

## Needed for the final cut

A take on the desktop stage, then `beats.toml` tuned against its events.
