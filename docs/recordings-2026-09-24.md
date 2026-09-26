# Staging the site's recordings (2026-09-24)

The landing page needs five short clips (`docs/landing-page-2026-09-24.md`). This is the production
plan for them: the story they tell, what is on screen down to each card in the stack, a shot list
per clip, and the tools that make every take repeatable. Nothing here has been recorded yet.

## The story

The clips follow one developer making a small browser game with Claude Code. Every clip happens in
the same world, so the page reads as one evening of work rather than five demos. Pete is deciding
the creative direction one choice at a time; this section holds what is decided.

Decided (2026-09-24):

- **The game is Mew,** a cat on rooftops at night. Mew is also a Pokémon; Pete is fine with that.
- **The look is shadow puppet,** after Lotte Reiniger's cut-paper films. Every shape is black and
  cut out: the city, the chimneys, the cat. They stand against a sky glowing from plum at the top,
  through rose, to amber at the horizon. Paper grain was ruled out for every look, because noise
  shimmers and blocks up in video.
- **The bug is a layer-order bug: the moon is drawn in front of a tower.** The moon straddles the
  tower's edge, half over the sky and half over the building, so it reads as the moon in front of
  the tower, not as a clock face. A pale disc over a black tower reads at any size.

- **You try to catch the moon.** It keeps rising just out of reach, and each level the cat climbs
  higher across the rooftops. A moon drawn in front of a tower fits a moon that won't stay put.

- **The stack holds four cards before the first take,** oldest first:
  1. The cat's sprite sheet: black silhouettes on white, the only light card in the column.
  2. The title screen, with a box you drew earlier around the logo.
  3. A card from Claude: Level 2, with Claude's arrow at a new water tower to climb.
  4. A screen recording of the cat's jump, with its length badge.

  The fifth card, the bug, is captured on camera in the first clip. The set shows a drawing, an
  agent's card and a recording in passing, without a clip having to explain them.

- **The developer's lines are playful,** with the moon treated as a character. The hand-off typed
  in Claude Code: "The moon keeps cutting in front of the tower. Put it back in its place." The note
  on Claude's screenshot: "now make it harder to catch". The earlier box on the title screen's logo
  says "bigger!".
- **Claude's side is a real session.** Claude Code makes the fix, writes its reply, and pushes its
  own marked screenshot through the Vignette skill. The prompt and a short CLAUDE.md in the game's
  folder steer it, several takes are run, and the best is kept. Only the waiting is cut; the
  terminal never shows a transcript that didn't happen.

- **The cat is a cut-out silhouette,** a classic sitting cat with a curled tail, its eye and whiskers
  cut out so the sky shows through. That is how Reiniger gave her figures expression, and it lets the
  cat look up at the moon it wants. At thumbnail size the details drop away and the plain silhouette
  still reads as a cat.

- **The title is part of the skyline.** "Mew" stands on the roofline as three black buildings,
  with a few lit windows cut out so the sky shows through, and the cat sits on the M. The windows are
  cut the same way as the cat's eye. The typeface in the sketch is a stand-in; the final letters get
  drawn to match.
- **Your earlier box on the title-screen card is around the moon,** saying "bigger!". The title is
  already large, and a bigger moon suits a game about catching it.

Still to decide: clips 4 and 5. Send's menu, which clip 4 films, was reworked on 2026-09-24 (`docs/send-menu-2026-09-24.md`), so clip 4 can be decided now. The annotator's redesign (`docs/annotator-redesign-2026-09-24.md`) would change the editor these
clips film, but it's paused, so the clips film the editor as it is.

## The set

Every take is filmed in a macOS user account made for it, **Vignette Demo**. That account is what
keeps Pete's own things off screen:

- **Its menu bar, Dock, desktop and notifications are empty.**
- **Its home folder holds the only Codex threads and herdr panes the Send menu will list.** The app
  finds `codex` and `herdr` at fixed paths in the home folder, so in Pete's account Send would list
  his real projects.

The alternative is Pete's own account, cropped below the menu bar. It would also need a debug-only
setting in the app to point Send at staged sessions. That's a code change, and his Dock, desktop and
notifications would still need hiding for each take.

| Detail | Choice | Why |
|---|---|---|
| Display | Built-in, "looks like" 1352 × 878 | Bigger than the default 1512 × 982, so text survives the shrink to page width. The source is 2704 × 1756 px, which leaves room to zoom in 1.7× without losing sharpness at 1600 px out. |
| Framing | Crop out the menu bar; deliver 16:10 at 1600 × 1000 | The menu bar holds the notch and nothing the story needs. 16:10 matches the screen and the page's current still. |
| Appearance | Open (see the decisions) | The game is dark either way. Light macOS chrome would frame it; dark chrome would let it fill the frame. |
| Wallpaper | A soft, low-contrast gradient in one hue | The stack's backdrop blurs what is behind it, and a gradient shows that off. Busy wallpaper competes with the cards. |
| Dock | Hidden (auto-hide, long delay) | It adds nothing and shifts the stack's bottom. |
| Desktop | No icons, no widgets, Stage Manager off | Nothing on screen that isn't part of the story. |
| Focus | Do Not Disturb | No banner can land mid-take. |
| Pointer | 1.25× size | It stays visible at page width without looking like an accessibility setting. |
| Screenshot sound | Off | The clips are silent anyway, but a take can be watched live without it. |
| Windows | Claude Code on the left 40%, Safari on the right 60% | The stack slides in over Safari's right edge. A card dragged from it to Claude Code crosses the whole frame, so the viewer sees the trip. |
| Safari | One window, one tab, `localhost:5173` | A localhost URL tells a developer this is their own game. |
| Terminal | Ghostty in herdr, 16 pt, light theme, prompt `~/mew ❯` | Send reaches Claude Code only inside herdr, which the page says. 16 pt keeps the prompt readable at page width. |
| Claude Code | Signed in, a fresh session in `~/mew`, the Vignette skill installed | The replies are real. Only the wait for them is cut. |

## The clips

The top of the page is now a trailer (`docs/trailer-2026-09-24.md`), decided 2026-09-24 after the
first cut of clip 3 ran too slow for a visitor's first seconds. The clips below are the detailed
ones further down the page.

Times are from the first frame. **Keys** are keycap overlays added afterwards. **Camera** is a move
of the crop over the 2x source, eased, never faster than 0.8 s, and never during Vignette's own
animation.

### 1. Hand it off (the hero, about 14 s)

Decided 2026-09-24. It ends as Claude starts working; the agent clip further down pays it off.

| s | What happens | Camera | Keys |
|---|---|---|---|
| 0.0 | Mew's Level 3 in Safari: the cat on a rooftop, the moon drawn across the tower's edge. Claude Code waits on the left. | Wide | |
| 0.8 | macOS's crosshair; a region is dragged around the tower and the moon. | Wide | ⌘ ⇧ 4 |
| 1.8 | Vignette's thumbnail slides into the corner. | Wide | |
| 2.3 | The stack slides in and the new card lifts into the editor. | Eases in on the editor | ⇧ ⇧, held |
| 3.6 | A box goes around the moon where it covers the tower. | Holds | |
| 4.6 | Done: the card flies home with its copied mark. | Eases back to wide | ↩ |
| 5.6 | The card is dragged across Safari into Claude Code. | Wide | |
| 7.0 | "The moon keeps cutting in front of the tower. Put it back in its place." is typed at a brisk human speed, about 6 s. | Eases in on the prompt | |
| 13.0 | Enter. Claude Code starts working. | Holds | ↩ |

### 2. Your recent screenshots (about 9 s, loops)

Decided 2026-09-24. It opens a card by key, and ends on its own first frame, so it loops.

| s | What happens | Camera | Keys |
|---|---|---|---|
| 0.0 | Mew in Safari, no stack. | Wide | |
| 0.6 | The stack slides in with all five cards: sprite sheet, title screen, Claude's Level 2, the jump recording, the bug. | Eases toward the stack | ⇧ ⇧ |
| 1.6 | The focus ring walks up the column, 0.45 s a card, past the recording's length badge and Claude's tab, to the title screen. | Holds | ↑ ↑ ↑ |
| 3.2 | Return: the title screen flies into the editor, with your earlier "bigger!" box on the moon. | Eases in on the editor | ↩ |
| 4.8 | Esc: it flies home. | Eases back to the stack | esc |
| 6.2 | A double tap closes the stack. | Eases back to wide | ⇧ ⇧ |
| 7.4 | Hold on the first frame's state. | Wide | |

### 3. Mark it up (about 7 s)

Decided 2026-09-24: a new screenshot, Level 4, with marks over both the amber sky and the black
buildings. The colour pass gives each mark the colour that stands out against what is under it, so
marks in different places come out in different colours, which shows "no colour picker" without a
word. Rehearsal records which colours the pass actually picks.

Tight on the editor for the whole clip:

1. A box around a gap between two roofs, then the text "too far!" beside it.
2. An arrow from the open sky to a water tower, then the text "add a ladder?".
3. Done: the card flies home with its copied mark.

Keys: T, ↩ (ends the first text), A, T, ⌘ ↩ (ends the second text and is Done). The editor opens
with the Rectangle tool, so the box needs no key. Poster: all four marks on.

### 4. Your agent draws back (draft, not decided)

Waited on Send's menu, which now lists the five sessions used last, each with its project and
agent (`docs/send-menu-2026-09-24.md`). The clip is open again. What is settled so far:

- Claude names no colour for its marks. The colour pass picks, as it does for yours, because colour
  is there for contrast. Telling Claude's marks from yours by typeface is a separate TODO; if it is
  built before recording, this clip shows it.
- The draft beats: Claude Code finishes its reply; Claude's card slides into the corner, with the
  moon behind the tower and Claude's marks; a held double tap opens it; "now make it harder to catch"
  is typed beside Claude's mark; Send, and the Claude Code session is picked; the editor closes and
  Claude Code shows the new prompt with the image.

### 5. Stitch

Not discussed yet.
The palette has red, yellow, light blue, white and violet, and no green. Only Claude has a logo in
`Resources/agents/`.

## How takes are made

Every take is a script, so a take can be repeated until it's right, and a fix to one beat does not
mean re-performing the others.

- **Reset.** A stage script empties the demo watch folder, copies in the four cards with their
  times and drawings, sets the windows' frames with AppleScript, and puts the pointer at its mark.
- **Input.** `scripts/input.sh` today drags in 12 even steps over about a third of a second, which
  reads as a robot. It needs two commands: a move and a drag that follow an eased curve with a
  slight arc, at 120 steps a second, over a set duration, and typing at a set rate with small
  variations. The keys and hotkeys it already sends are fine.
- **Recording.** `screencapture -v` of the whole display, with the pointer, at 60 frames a second.
  If its encoding smears the stack's blur, a small ScreenCaptureKit recorder writes ProRes instead.
- **Rehearsal** checks what this plan assumes but nobody has watched: that Claude Code shows a
  dragged card as an image in its prompt, and that Send's menu lists the staged sessions.
- **Takes.** Three or more per clip. Pick the one whose timing is closest to the table.

## After the take

- **Camera moves** are keyframed crops over the 2x source, rendered by a script so they can be
  re-timed without re-recording. No move starts while Vignette is animating, so the app's own
  motion is never mixed with a pan.
- **Keycaps** are small rounded keys, system font, centred near the bottom. Each appears 0.15 s
  before its key and fades 0.4 s after. A double tap is two caps, and a held one stays lit. Nobody
  can see a key being pressed, and without them the stack seems to appear by itself.
- **Speed is never changed.** How fast Vignette moves is part of what the clips are selling. Only
  the agent's thinking time is cut, and only between beats.
- **Encoding:** MP4 (H.264) and WebM at 1600 × 1000, 60 frames a second, each with a still as its
  poster. The target is under 2 MB for the longest clip.
- **On the page:** a clip plays once, muted, when it scrolls into view, then rests on its last frame
  with a replay control. With Reduce Motion on, the page shows the poster and a play button.

## Who does what

Pete, once:

- Create the Vignette Demo account and sign in there.
- Sign Claude Code in, and install herdr.
- Grant Accessibility and Screen Recording to the terminal the scripts run from, and Accessibility
  to Vignette in that account.
- Be away from the Mac while takes run, since they post real input.

Claude:

- Build Mew and the states the clips need: the bug and the fix, and whatever else the shot lists call for.
- Render the four cards, and stage Codex threads and the herdr session in the demo account.
- Add the eased move, drag and typing to the input tool, and write the stage and shot scripts.
- Run the takes, then do the post-processing, the encoding and the page changes.

## Decisions for Pete

Creative choices are made one at a time with Pete (see The story). The production choices still
open:

1. **The demo account,** or Pete's own account with a debug setting for Send?
2. **Light appearance for macOS,** or dark? The game itself is dark either way.
3. **Play once and rest,** or loop every clip?
4. **Keycap overlays,** yes or no?

## First cut of clip 3 (2026-09-24)

Made for Pete's feedback: `.scratch/demo-takes/clip3-v1.mp4`, 1600 × 1000, 60 fps, 14 s, 800 KB.

**Where the pieces are**

- **Mew** is in `~/Code/mew`, which isn't a Git repository yet. `cat.js` is the cat, `scene.js` the
  sky, skylines and rooftop details, and `levels.js` Levels 2, 3 and 4. `index.html?level=4` shows a
  level. During takes it's served on `127.0.0.1:5190`, because Pete's Paddock dev server holds 5173.
- **The take tools** are in `.scratch/demo-takes`. `take.py` stages Level 4, records one take and
  cleans up. `backdrop` shows the game over the whole screen. `owner` names the window under a point,
  and the take checks it before every click. `pasteboard` saves Pete's pasteboard before a take and
  puts it back after.
- **`scripts/input.sh`** has three new commands for takes: `glide`, `glidedrag` and `type`.

**Choices made without Pete, for review**

- **A demo copy of the app in Pete's account,** not the demo account. It's a Release build with its
  own bundle id (`com.petepetrash.vignette.demo`), URL scheme (`vignette-demo`), log, settings file
  and watch folder, so it never touches Pete's Vignette. Clip 3 doesn't use Send, so the account
  question can wait for clip 4.
- **The game fills the screen in a borderless window,** not Safari. The clip never shows a browser.
- **The stack holds two earlier cards:** Level 2 from Claude with its arrow, and Level 3 with your
  box on the moon. The sprite sheet, the title screen and the recording aren't built yet.
- **One fixed frame and no keycaps.** The crop sits between the menu bar and the Dock, flush right,
  so the editor and the stack column both fit.
- **Dark appearance,** because that's how this Mac is set.

**What the take showed**

- **The flight home after Done starts with a blank.** For 133 to 150 ms, 8 to 9 frames, the
  editor's picture is gone and only the dimmed screen shows. Then the picture comes back and flies
  home. It happened in both takes, in Debug and in Release. The editor window is ordered out in
  the same turn the flight starts, but the flight's first frame reaches the screen about 125 ms
  later. The log also shows `parked` arriving 23 ms after `finish`, where
  `docs/native-editor-2026-09-23.md` expects the same turn at zoom 1.
- **The clip runs 14 s against the planned 7.** The typing is at 11 characters a second, and
  checking the state before each beat adds short pauses.
- **The colour pass is visible.** Each mark appears red, then takes its colour about 0.3 s later.
  The box and the arrow came out yellow, and "too far!" light blue.
