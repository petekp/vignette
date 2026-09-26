# Screenshots iCloud has taken off the Mac (2026-09-25)

Opening the stack froze Vignette for 18.8 s during Pete's setup test. The cause was screenshots
that iCloud Drive had taken off the Mac. Vignette read them on the main thread, and each read
downloaded the whole file first.

Now such a file is never read on the main thread. Its card appears at once with iCloud's
thumbnail. A screenshot is downloaded in the background, for the editor. A recording is not
downloaded.

## What happened

Pete's `~/Desktop` is in iCloud Drive ("Desktop & Documents Folders"). With Optimize Mac Storage
on, macOS takes the bytes of old files off the Mac and leaves a placeholder. The file still lists
with its name, size and date. The kernel marks it `SF_DATALESS` in `st_flags`, and it takes no
blocks on disk.

Opening the file for reading makes macOS download all of it, and the read waits. ImageIO's header
read and AVFoundation's asset load both do this, however little they read. The log of
`fileproviderd` shows each one as `fetch-content(...) why:materialization`.

The stack reads each card's header on the main thread (`Thumbnailer.pointSize`), to size the card.
The freeze in the setup test, read from the system log:

| Time | What the main thread waited for |
|---|---|
| 30.13 | the double tap |
| 30.20 to 31.51 | a 709 KB screenshot downloading |
| 31.58 to 32.05 | a 92 KB recording |
| 32.05 to 46.35 | a 333 MB recording |
| 46.35 to 48.86 | a 93 MB recording |
| 48.93 | `[stack] shown ... shown=18799ms` |

The second tap of a double tap made during the freeze was queued behind it, so it closed the stack
18 ms after the stack appeared.

Launch did the same thing through the thumbnail warm-up (`warmThumbnails`), which reads the same
headers on the main thread. Setup hid that path: the warm-up ran while macOS's folder prompt was
up, so the folder listed as empty, nothing was warmed, and the first stack open read every header
cold.

## What reads without downloading

Checked on two files evicted with `brctl evict`, a 93 MB recording and a 709 KB screenshot. After
each check the files were still placeholders, and `fileproviderd` logged no `fetch-content`.

| Read | Time per file | Downloads |
|---|---|---|
| Listing the folder with dates | about 1 ms | no |
| `lstat` for `st_flags` | under 1 ms | no |
| `URLResourceValues`, including `ubiquitousItemDownloadingStatus` | 1 to 10 ms | no |
| Extended attributes (`Agent.of`) | under 1 ms | no |
| `QLThumbnailGenerator`, `.thumbnail` | 0.3 to 0.9 s | no |
| ImageIO header, AVFoundation asset | the whole download | yes |

Quick Look answered with a real thumbnail in the file's shape: 191 by 416 for the phone
screenshot, 416 by 376 for the recording. Spotlight has no records for these files, so `mdls`
gives nothing.

## The fix

- `Thumbnailer.isDataless` reads the flag with `lstat`.
- `Thumbnailer.lookUp` is what the main thread asks. It reads the header of a file that is here,
  and answers `.notDownloaded` for a placeholder, with the header kept from an earlier read if
  there is one.
- A card for a placeholder takes the kept shape, or the screen's shape until iCloud's thumbnail
  arrives. Its picture comes from Quick Look on the thumbnail queue (`Thumbnailer.cardImage`). The
  thumbnail's shape is kept as the file's header, marked not exact, until the file's own is read.
- A screenshot that is a placeholder is downloaded in the background (`Thumbnailer.download`), by
  the warm-up and by the stack. The editor reads the file on the main thread when it opens
  (`PixelSize(imageAt:)`), so the file has to be here by then. When the download lands, the card
  takes the file's exact size.
- A recording is not downloaded. It never reaches the editor, and a click opens it in the app
  macOS opens movies with, which downloads it. Its badge shows no length, since the length is in
  the file.
- Hovering a recording no longer decodes it at screen size. Only an image flies into the editor,
  and for a placeholder that decode would have downloaded the whole file.

## Measured

The demo copy watching `~/Desktop`, with the two files evicted before each run.
`.scratch/icloud-test/run.sh` does each step.

| | Before | After |
|---|---|---|
| Launch, `[app] launched` to `[app] ready` | 1616 ms, both files downloaded | 57 ms, only the screenshot downloaded, in the background |
| Launch with nothing evicted | 105 ms | |
| Stack opened right after launch | not measured: the warm-up had already downloaded both | 39 ms, `decoding=1`, the recording still a placeholder |
| Stack opened later | 60 ms | 55 ms |

## What is left

- Opening a screenshot in the editor before its background download finishes waits for the rest
  of the download on the main thread. The stack starts that download when it shows the card, so
  this needs a click within about a second of the stack opening.
- Draw on Newest Screenshot, a `vignette://annotate?file=`, and Copy each read the file on the
  main thread. For a placeholder, each waits for its download. The newest screenshot is rarely a
  placeholder.
- A screenshot that arrives from another Mac as a placeholder is read by the watcher on its own
  queue, which downloads it before the card appears. That is off the main thread, as before.
