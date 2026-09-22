# Vignette owns what happens after a capture

Installing Vignette means Vignette replaces Apple's post-capture behavior. There is no supported
state where both thumbnails exist. This note says what follows from that, and what has to be built
before it is true.

## The measurement

Apple's floating thumbnail does not overlay a file that is already written. macOS withholds the
write until the thumbnail expires.

| `com.apple.screencapture show-thumbnail` | File complete on disk after the drag ends |
|---|---|
| off | 0.08s, 0.06s, 0.05s |
| on | 5.63s, 5.60s, 5.58s |

Three interactive Cmd+Shift+4 captures per condition, same drag, driven by `scripts/input.sh`,
measured 2026-09-22. The poll watched the watch folder every 20ms and waited for the file's size to
stop growing.

Vignette reads the folder, so every on-capture behavior inherits that 5.6 seconds. **Copy New
Screenshots is the one that breaks rather than lags:** the clipboard is filled when the watcher
reports the file, so a Cmd+V inside the gap pastes what was on the clipboard before. Not late,
wrong.

## What follows

1. **First run turns Apple's thumbnail off.** Not a question. `Settings.fromSystem()` currently
   copies whatever macOS has, which is on.
2. **The "Show the macOS thumbnail" toggle comes out of Settings.** It is an escape hatch into a
   state that is not a mode, it is a broken install.
3. **Video recordings become Vignette's job.** Removing the thumbnail removes the only UI Cmd+Shift+5
   has today. That is a gap in this product, not a reason to keep the hatch.
4. **"Restore macOS Screenshot Settings…" is the only way back,** because it is the disable path,
   not a preference. It already exists and already restores location, thumbnail, shadow, and format
   from `appleOriginal`.

## The rule this replaces

AGENTS.md states that Apple's defaults are "never [written] on first run", and
`first-run-journey-2026-09-21.md` calls that a good rule. The reasoning was that first run should
not touch the user's machine before they ask.

Choosing to install a screenshot tool and picking its shortcut is the ask. The rule was written
before the setup window existed, when nothing in the app had asked the user anything. It is replaced
by: Vignette writes the capture defaults it owns on first run, records what was there in
`appleOriginal`, and says so in the setup window.

## Keeping it off

`pushToApple` only writes a key when the app's own value changes, so a value changed outside the app
is never reconciled. A user who flips `show-thumbnail` in System Settings silently gets the 5.6
second delay and a broken clipboard, and blames Vignette.

Launch should reconcile: if settings.json says the thumbnail is off and Apple's default says on, push
it. This is not fighting a preference. While Vignette is installed, that combination has no meaning.

Only the keys whose drift breaks the app. `show-thumbnail` always, and `location` when
`syncAppleSaveLocation` is on, since a save location pointing elsewhere means Vignette sees nothing
at all and that toggle already promises the two stay in step. `type` and `disable-shadow` are left
alone: both values work, and the reason someone picked JPEG has nothing to do with this app.

The reconcile says nothing when it fires. A launch toast would interrupt the person who flipped the
setting by accident, and the person who did it deliberately is asking a question they will take to
Settings. So the explanation lives where the toggle used to be: the caption stays as a plain
statement, a few rows above the restore button that undoes it.

`appleThumbnail` stays as a key in settings.json with no UI. The file is a documented editing
surface, and `restoreAppleDefaults()` writes Apple's old value back into it, which is what makes the
restore stick. Without the key, restore would set Apple's default and the next launch would undo it.

## The video gap

macOS screen recording has no Vignette equivalent. Today Apple's thumbnail covers it; after this
change nothing does. The recording lands in the folder and neither app says anything.

First version: a card appears, clicking it hands the file to macOS the way the system would open it,
and Copy and Delete work as on any card. No drawing, no frame extraction, no stitching.

Trim and share are not lost. Apple's thumbnail offered them, and so does whatever app macOS opens
the recording in. Vignette says the capture happened and gets out of the way.

What recordings are for beyond that is
[recordings-north-star-2026-09-22.md](recordings-north-star-2026-09-22.md).

### How a recording card behaves

Decided 2026-09-22, built, and checked in the running app against a scratch folder.

- The card shows the first frame and a badge with a video glyph and the length, to the nearest
  second and never 0:00, so a poster frame is not mistaken for a screenshot.
- A click, or Return, opens it in the app macOS uses for `.mov`, which is QuickTime Player unless the
  user chose another. The hint that follows the pointer says Open instead of Draw.
- Every action declares the kinds of file it takes, and an action is offered only when it takes every
  card in the selection: Copy, Copy Paths and Delete take both; Draw, Copy Drawing and Stitch take
  screenshots; Open takes recordings. The strip greys a row that cannot run. Draw and Open share
  Return, so they share one row, which shows whichever can run. A key whose action cannot run on
  the selection beeps, the way a disabled menu item's shortcut does.
- A new recording is copied as a file when Copy New Screenshots is on, with no pixels read, and
  shows its card even when Draw on New Screenshots is on.
- The hold gesture and Draw on Last Screenshot take the newest screenshot and pass over newer
  recordings, since both promise drawing. A URL action with no `file=` takes the newest file it can
  act on.

**A greyed row draws its reason.** No system tooltip appeared on any strip row after 2.5 seconds of
hover. AppKit shows a window's tooltips only while its app is active, unless the window sets
`allowsToolTipsWhenApplicationIsInactive`, and the stack never makes Vignette active. So a greyed
row draws its reason under itself while the pointer is on it, in the click hint's style: "Screenshots
only", "Recordings only", or "Select 2 or more". Checked on screen. Setting that window flag instead
would be one line, but it would also turn on the stack's other tooltips, which repeat the labels the
rows already show, and each would wait for the system's hover delay.

### What a recording is

Measured 2026-09-22 against the real Cmd+Shift+5 interface, driven through `screencaptureui`'s
accessibility buttons, and cross-checked against `screencapture -v -p`. Both produce the same thing.

| | |
|---|---|
| Name | `Screenshot 2026-09-22 at 8.50.03 AM.mov` |
| Extension | `mov` |
| UTI | `com.apple.quicktime-movie`, conforming to `public.movie` and `public.audiovisual-content` |
| Example | 4.05s, 840x908, 60fps, 0.64 MB |
| On disk | 0.27s after the recording stops |

**Detect by extension or UTI, never by name.** The prefix is
`defaults read com.apple.screencapture name`, it is the user's to change, and screenshots and
recordings share it: on this machine both are `Screenshot`. The timestamp also carries U+202F, a
narrow no-break space, before AM and PM rather than an ordinary space.

The file lands promptly, so recordings have none of the delay problem this note is otherwise about.

A poster frame costs about 90ms: 84ms for the 4 second capture above and 95ms for a 39 second,
1562x1620 one, both at a 416 point limit. That tracks resolution rather than duration, and it is far
too slow for the main thread, so it belongs on the same asynchronous path `Thumbnailer` already uses
for images.

### What breaks if `mov` simply joins `candidateExtensions`

1. `waitUntilComplete` requires `isCompleteImage`, which no recording satisfies. Every one would
   spend ten seconds failing and log `never-stable`. This is the one that makes a naive change look
   like nothing happening at all.
2. `Clipboard.copyFiles` reads the first file whole to build an image item. A long recording would
   go into memory for no reason.
3. `Thumbnailer` is ImageIO throughout, so there is no poster frame.
4. `ShotAction` has `minimumCount` but nothing that says an action does not apply to a card, so
   Draw, Copy Drawing and Stitch would be offered on a recording.
5. `annotateOnCapture` would send a recording to the editor.

`Screenshot` is `{ url: URL }`, so it needs no new field: the kind follows from the extension.

An existing folder gains its history at once. This Mac's watch folder holds 127 recordings beside
1404 images, of which one falls inside the newest thirty, so the stack barely changes here. Another
folder could differ.

## Order

The public download is blocked on the tldraw Hobby key, so nothing here reaches a user until that
arrives. That window is the room to do this in the right order.

1. Items 1, 2 and 4, plus the launch reconcile. Small, and they fix the capture that decides whether
   a new user keeps the app.
2. The video gap, before the first download. Shipping 1 and 2 without it would take away the only UI
   recordings have and give nothing back.

Between the two, a recording is silent. Nobody has a build, so nobody meets that. Both are built as
of 2026-09-22.
