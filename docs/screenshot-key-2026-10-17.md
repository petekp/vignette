# A screenshot's key, and renames: design, 2026-10-17

Status: built. This is foundation 2 of [the architecture review](architecture-review-2026-10-17.md),
weakness 1.

## The problem

A screenshot is identified by its path string, and every store spells that path its own way.

- **A rename deletes the drawing.** The watcher reports a rename as a removal and an arrival.
  The removal reaches `Drawings.remove`, which deletes the drawing's file. The new name arrives as
  a new capture: it can be copied, and with Instant Draw on it opens in the editor.
- **Entry points re-spell paths.** `Commands.inWatchFolder` turns `/tmp/x.png` into the folder's
  spelling so it reaches the same drawing. Nothing in the types says a path has been through it.
- **The request record keeps only the basename.** A failed-reply notice rebuilds the source path
  from the current folder (`AppDelegate.swift:1110`).

## The key

`ScreenshotKey` is a screenshot's path as the watch folder spells it: the folder's setting,
as stored, plus the file's name as the listing gives it. Two initializers make keys:

- **`ScreenshotKey(folder:name:)`**, from the folder and a file name: the watcher's listings, and
  the files Vignette names itself, a stitch and an agent's push. The watcher reports keys, never
  URLs.
- **`ScreenshotKey(resolving:in:)`**, for a path from outside: a URL command's target and a
  reply's file. It resolves symlinks on both sides, spells the result by the folder as stored,
  and answers nil for a path outside the folder.

`ScreenshotKey(asGiven:)` reads a key back as it was stored: a drawing's, a request record's
source, a reply's reserved location. It also names a file outside the folder for a debug-mode
command, which is the one path that has no key of the folder's.

`Screenshot` carries its key, and has no initializer that takes a URL. The drawings, the cards, `AnnotationRun` and `Opening`,
`CardNotices` and the capture origin take a `ScreenshotKey` where they take a path string today.

A drawing's file is still named by a hash of the key's path, so every existing drawing opens
under its key with no migration. This holds because the key spells the path exactly as the
watcher spells it today.

## Renames

The watcher's index keeps each candidate's inode and size beside its modification date. The
listing asks for them in the same bulk call. On 2,231 files that took the listing from 11.4 ms to
13.6 ms, on the watcher's queue (measured 2026-10-17).

In one listing, a name that disappeared and a name that appeared with the same inode, size and
modification date are one file renamed. The scan reports it as `renamed(from:to:)` and reports
neither a removal nor an arrival. A pair counts only when the match is one to one.

- **Downstream**, `FolderWrites.renamed` re-keys in this order:
  1. The card keeps its id and takes the new screenshot. Its notices and the capture origin are
     re-keyed.
  2. `AnnotationRun` gets `.renamed(from:to:)`. A queued name is re-keyed. The open image keeps
     its opening id and takes the new key.
  3. The drawing is rewritten under the new key, and the old file is removed. The editor's open
     drawing takes the new key, and the card is handed its drawing under it. This step comes
     last because that hand-over finds the card by the new key.
- **A rename is not a capture.** It is not copied, not opened by Instant Draw, and does not wait
  for the file to settle.
- **A same-name replacement**, such as Dropbox replacing a file, changes the inode under a name
  that stays. That is not a rename, and today's behaviour stays.
- **A case-only rename** on a case-insensitive volume keeps its inode, so it is a rename too. That
  replaces the case-alias tolerance in `Inventory.confirmsAbsence`.

The request record stores the source's full key. Records written before keep their basename and
are read the old way.

## What this does not cover

- **A rename while Vignette is not running.** The launch sweep still removes a drawing whose file
  is gone. The drawing store keeps no inode to match it by.
- **A rename that two listings split**, the removal in one and the arrival in the next. It falls
  back to today's removal and arrival. A rename is one change to the directory, so it should
  land in one listing. Nothing measures how often it does not.
- **A move out of the folder and back**, including Finder's Delete and Put Back. The review's
  Step 2 has that, with a pixel fingerprint.

## Verification

- **Watcher.** Unit tests for the diff: a rename, a case-only rename, a same-name replacement,
  two files swapping names, and a rename beside an unrelated removal.
- **Drawings.** Unit tests for `rename`: the drawing opens under the new key, and the old file is
  gone.
- **Reducer.** A run sequence where the open image and a queued one are renamed.
- **End to end, in the VM.** The `rename_keeps_drawing` scenario pushes an image with marks,
  renames it with `os.rename`, then renames it again changing only the case. Each time it checks
  that the card under the new name still has its drawing.
- **Finder, once by hand.** On 2026-10-17 a scratch script renamed a pushed image through Finder
  in the VM. The log showed one `[watcher] renamed` line and one `[drawing] renamed` line, and
  the card kept its drawing. The suite does not cover Finder, because a fresh VM has not granted
  the terminal Automation access to Finder.
