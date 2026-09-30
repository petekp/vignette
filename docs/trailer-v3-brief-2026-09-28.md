# Trailer, third version: the brief (2026-09-28)

The first two versions told one story about a cat game. Pete's review of the second found three
problems that a better take cannot fix:

- **The game suggests a game tool.** The audience is people who build software on a Mac, and a
  game level is not their work.
- **It never says what Vignette replaces.** Vignette does everything macOS's screenshot tool does,
  better. The video starts at a drawing and skips that.
- **It skips the refinements.** Copy on capture, the history, hold to draw, notes, the automatic
  colour, stitch, drag into a terminal and the queue get no screen time.

This brief starts over from what a viewer should leave with. Nothing here is recorded yet.

## Direction (fifth pass)

This section governs. The sections after it record how we got here. Where they disagree, this one
wins.

### What went wrong in the first four passes

We built the story out of a list of features. Each review made single beats make sense on their
own, with a second bug, an arrow or a note added to justify a feature. The film as a whole still
read as a tour. We reviewed on paper, so timing and readability went unjudged. Several captions
claimed things the screen never showed, such as the session pick and the stack.

### The film says one thing

**Your agent can show you things, and you answer by pointing.**

The moment it is built around: Claude's options arrive as a card in Vignette, and you answer by
drawing on them. You box B and draw an arrow from A's flag.

### Two kinds of video

- **The film, about 30 s.** One story, told only as far as the sentence needs:
  1. You capture the itinerary.
  2. You click the card and draw two marks. An arrow from the map's second stop to the
     Arashiyama day: "number the days". A box around the Oct 14 day: "make this stand out,
     options?"
  3. You send it to Claude Code.
  4. Claude's answer arrives as a picture: three versions.
  5. You point: B, with A's flag.
  6. Claude builds it.
  
  The same take makes both cuts. The README's cut ends on the end card. The landing page's cut
  loops.
- **Feature loops, 4 to 8 s each.** They are muted, loop on the site and in the README, and need no
  story:

  | Loop | Shows |
  |---|---|
  | Zoom | Zooming in on small details |
  | Recent screenshots | Your recent screenshots, recordings included |
  | Hold to draw | Double tap and hold to open the newest in the editor |
  | Stitch | Stitching several screenshots into one |
  | Any session | Choosing which Claude Code session gets a drawing |
  | Paste | A capture that is on the clipboard at once |

The arrow is there to show what drawing does that comments cannot. In Codex or Agentation you
can pin a comment to an element, or box one and write a note, but you cannot relate two things on
the page. The arrow joins a stop on the map to the day it belongs to, and the note only has to
say "number the days". Claude numbers the days on its first turn, since that has one right
answer, and the numbers are in the final shot. The reply's arrow, from A's flag into B, makes the
same point a second time.

The film carries no bug fixes and has no second page, stack, zoom, stitch or session menu. The
Postcard stage is a clean app, so the viewer sees no problems the story does not address.

### The criteria, applied on every pass

1. Every beat serves the sentence, or it is cut.
2. The screen proves each caption. Watch with captions off.
3. A first-time viewer follows it at real speed.
4. Nothing is in the film only because a feature needs showing. That is what the loops are for.
5. Cut before adding.

### How we judge it

- **In motion, before recording.** `media/trailer/storyboard/animatic.html` plays the film and each
  loop at their real timing, with the camera moves and captions. It is drawn by the same code as
  the storyboard, so a storyboard panel is a frame of the animatic. `C` hides the captions for
  criterion 2.
- **By someone new to it.** Show the animatic, with captions off, to someone who has never seen
  Vignette. Ask them what happened.
- **The bar.** Pete would post it without explaining it, and the options arriving makes someone
  react. If not, we cut or restage before recording.

## Who watches, and where

- **The audience** is a Mac user who takes screenshots all day and works with a coding agent:
  Claude Code or Codex. They know macOS's floating thumbnail and its markup window.
- **Where they see it:** the landing page's hero, muted and looping, and the README and social
  posts, where someone chooses to play it.

## What a viewer should leave with

In this order, since the first is what makes someone install it:

1. **It is the macOS screenshot tool, better.** Same shortcuts. The thumbnail it replaces is already
   on your clipboard, stays in a history, and opens a real editor.
2. **Drawing on a screenshot is instant.** Double tap, hold, draw a box, type a note, done.
3. **Your agent is part of it.** Send a drawing to Claude Code, and it can send one back.

## What macOS does, and what Vignette does instead

This is the comparison the video has to make visible. Each row is a candidate shot.

| macOS's screenshot tool | Vignette |
|---|---|
| The file appears about 5.6 s after the capture, once the thumbnail goes | The file and the clipboard are ready at once. Cmd+V works immediately |
| One thumbnail, then it is gone | Every recent screenshot, a double tap away, driven by the keyboard |
| Markup opens a separate Quick Look window | The editor opens in place, from the card, with no wait |
| Pick a colour, pick a tool | Three tools. Type after a box and a note starts. Marks pick a colour that stands out |
| One image at a time | Select several: stitch them into one, draw on each in turn, or drag them all out |
| Drag the thumbnail somewhere before it disappears | Drag any card into a terminal or a chat, with your drawing on it |
| Nothing for agents | Send to Claude Code or Codex. Your agent pushes screenshots back with its own marks |

## The subject on screen

**Recommended: a web app the viewer could be building.** A small product in a browser, such as a
settings page or a dashboard, running from a dev server, with Claude Code in a terminal beside it.
Every shot is then something the viewer does in their own day: capture a bug, mark it, hand it over.
The pipeline already serves a local site to Chrome and renders it headless for Claude, so the game
is replaced rather than the machinery.

The alternative is no single app: each shot uses whatever suits it, such as a Slack thread for
paste and a design file for stitch. That reads as real use, but the viewer loses a thread to follow.

## Structure

**Recommended: chapters, each one feature, with one app running through them.** About 60 to 75 s.

| # | Chapter | Caption | What happens | Replaces in macOS |
|---|---|---|---|---|
| 1 | Capture | Take screenshots as usual ⌘⇧4 | A region of the app. Vignette's thumbnail slides in | the floating thumbnail |
| 2 | Paste | It's already on your clipboard | Cmd+V into Claude Code's prompt, at once | the 5.6 s wait |
| 3 | History | Double-tap right Shift for your recent screenshots | The stack slides in. Arrow keys walk it, and the app stays in front | nothing |
| 4 | Draw | Hold to draw | Hold the double tap: the newest card lifts into the editor. A box, a typed note, an arrow. Red, or a colour that stands out | Markup |
| 5 | Many | Select several | Space selects three. Stitch makes one numbered image. Or drag them into the terminal | nothing |
| 6 | Send | Send it to your agent ⌘↩ | A message and Send. The drawing lands in Claude Code, and it fixes the app | nothing |
| 7 | Reply | Your agent draws back | Claude pushes a screenshot of its fix with its own marks. You change one and reply | nothing |
| 8 | End | Vignette. Free for macOS 14 or later | The wordmark and the site | |

**The hero loop** is a second, shorter cut of the same take: chapters 1, 3, 4 and 6, about 25 s.
A muted loop has to make its point in the first few seconds. The long cut is for someone who
pressed play.

The alternative is one continuous story, as in the first two versions. It shows the loop with an
agent best but leaves little room for the refinements, which was problem three.

## A before-and-after opener

Showing macOS's own thumbnail first, then Vignette's, would make point 1 in two seconds. It needs
macOS's thumbnail turned on for the take, which means changing the real `com.apple.screencapture`
defaults on this Mac and putting them back after. That can be done safely: Vignette records the
original values, and the take can restore them. It needs Pete's approval, since it touches his own
settings. Without it, the captions carry the comparison.

## Decisions (Pete, 2026-09-28)

- **Subject:** a web app in development, in Chrome from a dev server, with Claude Code beside it.
- **Structure:** chapters, with a short hero cut from the same take.
- **No macOS opener.** The captions and the paste chapter carry the comparison, and nothing touches
  this Mac's screenshot settings.
- **Chapters:** all of them, plus zoom and a screen recording, plus the session picking in Send.
  - **Session picking:** the toolbar starts on the Claude Code session you used last, and its menu
    lists the others. The stage runs two Claude Code sessions in two projects so the menu has a
    choice. Codex stays out: listing Codex threads on this Mac would show Pete's real ones.

## The storyboard and the animatic

Both are in `media/trailer/storyboard/`, and both draw from the same files:

| File | Holds |
|---|---|
| `story.js` | Every shot of the film and the loops. Each shot says what the screen and the caption are at any moment |
| `scene.js`, `scene.css` | The drawing of the screen: Chrome, Claude Code, and Vignette's cards, editor and toolbar |
| `index.html` | The storyboard. Each shot at one marked moment, with its camera, action, timing and transitions |
| `animatic.html` | The player. Every shot in motion at real speed. `C` hides the captions |

A change to a shot goes in `story.js`, and both pages show it. The screen positions are measured
from the last take.

The app is Postcard, a trip planner with a dark theme, in `media/trailer/stage/postcard`. It shows
a week in Kyoto. Since the fifth pass it is a clean app with no bugs on screen. The Oct 14 day,
Fushimi Inari at sunrise, is the trip's highlight. It looks like the other two days, which is
what the film's note asks about.

## The story, second pass (after the storyboard review)

Pete's review of the storyboard found two chapters that are demos, not story:

- **"It shows you what it changed."** You asked for the fixes and can see them in Chrome. A
  screenshot of them tells you nothing new.
- **The stitch.** Nobody would stitch those two images and drag them to Claude.

The rule for this pass: every shot happens because the person needs it at that moment. Lumen is
now dark.

### What Claude sends back

1. **Options to choose from. Recommended.** Your first drawing has two bugs and one matter of
   taste: a box on the Team card, "make this stand out". Claude fixes the bugs. For the taste
   request it renders three versions of the card side by side, labels them A, B and C, and asks
   "Which one?". You box B, add "but keep it purple", and reply. The bugs had one answer, so it
   fixed them. Taste has several, so it asked, in pictures, and you answered by pointing, which
   text does badly.
2. **What you can't see.** Claude checks the page at phone width, finds the invoice table
   breaking, and sends that screenshot boxed with "stack the rows, or scroll?". It shows the
   agent looking at states you are not. Weaker: the viewer never saw the phone view, so there is
   nothing to compare.
3. **Where should it go.** You ask for a monthly and yearly switch. Claude marks three possible
   places, numbered, and you box one. A spatial question with a spatial answer, but a smaller
   payoff than choosing between finished options.
4. **Which did you mean.** Your "line these up" could mean top or bottom. Claude shows both.
   Closest to your own drawing, but it reads as Claude not understanding you.

### Decisions (Pete, second pass)

- **Claude sends back options.** Your first drawing has two bugs and one matter of taste. Claude
  fixes the bugs and sends three versions of the Team card. You box B, write "this one, all
  purple", and reply.
- **The stitch is one request made of two drawings.** The pale pills are a shared style, so they
  are on the Team page too. You draw on the Billing capture, capture and draw on the Team page,
  stitch the two, and send them to Claude as one image.

What follows from them, all drawn in the storyboard:

- **History, then hold.** The first drawing starts from the stack with Return, which shows the
  history. The second uses the shortcut: hold the double tap and the newest capture goes
  straight into the editor.
- **Paste has no action of its own.** Shot 1c's caption says the capture is on the clipboard
  while Claude Code's footer shows its clipboard hint. Pasting into Claude Code and clearing it
  was a detour, so it goes. Pete can still ask for a real paste.
- **Drag goes.** Nothing in the story needs it.
- **The Team price bug goes.** The Team card is the taste request instead. Lumen's Team page now
  has role pills as pale as Billing's Paid pills, from the same `.status` style.
- **Lumen's CLAUDE.md** now tells Claude to fix marks with one right answer and to send three
  versions, labelled, for a matter of taste.

### The app (Pete, third pass)

Pete asked for an app that does not look like the work people do all day, and chose a trip
planner. Postcard replaces Lumen, and the story keeps its shape:

| Lumen | Postcard |
|---|---|
| Billing page | Itinerary, `index.html` |
| Team page | Stays, `stays.html` |
| Usage page, in the earlier captures | Packing, `packing.html`, and crops of the itinerary |
| The Pro card's button | The Arashiyama day's Details button |
| The Paid and role pills | The Booked pills, in the trip summary, the day cards and Stays |
| The Team card, the taste request | The Oct 14 card |
| Your note on B: "this one, all purple" | "this one, less pink" |
| Sessions `lumen` and `lumen-api` | `postcard` ("Itinerary page") and `postcard-api` ("Booking sync") |

The zoom now lands on the "8 booked" pill in the trip summary, which has room beside it for the
note. Postcard's CLAUDE.md carries the same instructions for fixes and options as Lumen's did.

### Review against the story rule (fourth pass)

A review of the Postcard storyboard found beats that existed to show a feature. Pete approved
all ten fixes:

1. **The Stays page has its own bug.** Its Add a stay button is cut off by the first row. The
   faint pills alone were one shared style, so a Stays drawing told Claude nothing new, and the
   stitch had no reason. Now each drawing asks for something different.
2. **No session menu.** Opening the menu to pick what was already picked contradicted "Vignette
   picks the session you were in". The shot holds on the target instead.
3. **The hero cut makes sense alone.** Its Send clip starts as the editor closes, so the stitched
   image is only a small card, and it shows only the itinerary's fixes.
4. **Paste is out.** The story sends through Vignette, and a paste would hand Claude the picture
   without the drawing.
5. **The first drawing starts from the card in the corner.** The stack first appears with the
   hold in chapter 3 and stays up for the selection in chapter 4.
6. **The recording is background** in the stack. Send can't take one.
7. **The Oct 14 card has a plain button,** so "make this stand out" asks for something it lacks.
8. **The reply points across the options.** You box B, write "this one, with that flag", and draw
   an arrow from A's Highlight flag. Claude builds B with A's flag.
9. **Captions name who acts:** "Vignette picks the session you were in", "Claude fixes what you
   marked".
10. **The options are asked for.** The note reads "make this stand out, options?", and Postcard's
    CLAUDE.md makes options only when a note asks for them.

## What changes to make it

Nothing below starts until Pete has watched the animatic and approved it.

- **The stage app** is `media/trailer/stage/postcard`, in place of `media/trailer/stage/mew`. It is
  done.
- **`drive.py` gets the film's beats:** capture, click the card, box and note, Send with no
  message, the options arriving, open them, box, note and arrow, Reply, and the page changing. The
  events it logs are the ones each shot in `story.js` names.
- **Each loop is its own short take,** from its own starting state: its own files in the watch
  folder, and for the session loop, a second Claude Code session.
- **The cut** makes two outputs of the film, one ending on the end card and one that loops, and one
  output per loop.
- **The camera** follows each shot's `camMove` in `story.js`: hold before moving, settle over about
  2 s, and wide when two windows matter.
