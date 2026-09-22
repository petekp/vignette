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

## Order

The public download is blocked on the tldraw Hobby key, so nothing here reaches a user until that
arrives. That window is the room to do this in the right order.

1. Items 1, 2 and 4, plus the launch reconcile. Small, and they fix the capture that decides whether
   a new user keeps the app.
2. The video gap, before the first download. Shipping 1 and 2 without it would take away the only UI
   recordings have and give nothing back.

Between the two, a recording is silent. Nobody has a build, so nobody meets that.
