# Shortcut and capture

- The recent-stack shortcut is either a Carbon hotkey (`HotKey.swift`, no permission needed)
  or a modifier double tap (`ModifierTap.swift`, `"double-rshift"`), which needs the app trusted
  for Accessibility because it watches key events with NSEvent monitors. Both fire the stack on
  the press and `hold` when the key stays down 0.4 s, so a held tap opens the stack and then
  lifts the newest card out of it. `RegisterEventHotKey` answers success for a combination macOS
  or another app already uses (measured with ⌘⇧3, ⌃Space and Raycast's ⌥Space), so only the keys
  firing prove a combination works, which is what setup's try shows. The recorder refuses ⌘ with
  one key, ⌘⇧3/4/5 and macOS's ⌃ shortcuts (`HotKeySpec.refusal`) and says why under the box.
  When the press closed an open stack, the hold brings it back
  (a presentation during the slide-out reuses the cards, which turn around) and lifts the card
  that was focused, or the newest. `annotateOnCapture` sends a new capture straight to
  `annotate` instead of `show`.
- Apple's Cmd+Shift+3/4/5 still capture. The app only watches the folder. Do not register
  those hotkeys.
- With `annotateOnCapture` on, a capture flies into the editor from the rect it was taken from
  (`CaptureOrigin.swift`). macOS records the rect and kind in the file's metadata
  (`kMDItemScreenCaptureGlobalRect`, `kMDItemScreenCaptureType`), set before the file takes its
  final name, and Vignette takes it from there first (`CaptureRect.recorded`). It is used only when
  the file was created in the last 10 s and the rect fits its pixels, since a copy by Finder,
  `copyItem` or `ditto` keeps the metadata and its creation date (`cp` gives a new date). On one Mac macOS stopped writing it for weeks
  (`docs/capture-origin-spike-2026-10-03.md`), so the poll below stays as the fallback. The capture
  overlay keeps its drag from every other app's event monitors. The button's state still reads, so ⌘ and ⇧ held
  together, seen by a `flagsChanged` monitor, start a 30 Hz poll of `NSEvent.pressedMouseButtons`
  and the pointer for 15 s. None of this needs a permission. `CaptureRect.locate` is the pure part.
  It tries a drag released within 3 s whose size is near the file's, then the topmost window under
  the pointer, bare or with either of Apple's two window shadows, then the display. A selection is
  the release corner and the file's size, since the poll sees the press up to a tick late. The
  capture includes the point under the release. A capture that matches none of them flies from its
  card. The presentation is pinned to the screen holding the rect's centre, and the flight starts in
  `Look.screen`, which has no corners, shadow, ring or matte, so its first frame matches the pixels
  beneath. `ThumbnailController.annotate(_:from:)` waits for the screen-size decode before the run
  starts: a new capture has no picture cached, and a flight with none is invisible in that look, so
  it travelled unseen and appeared part way along. `[origin]` lines say what was found, and `[annotate] from capture` says the flight used
  it. `docs/capture-origin-spike-2026-10-03.md` has the measurements, and the `capture_origin`
  scenario drives it with `screencapture -i`. Once the rect is found, `CaptureOrigin` also reads
  which apps' windows the capture showed (`CaptureRect.owners`) and keeps them for Send, which
  takes them once for that file within 30 s (`windows(of:)`, `docs/rules/send-start.md`).
  Every new image the person took, whether or not `annotateOnCapture` is on, asks `CaptureOrigin`
  once where it was taken, and logs the two clues a project label could be read from:
  `[capture] clues <file> apps=<app>:<share>%,… herdr=<pane>/<session or none> focus=<pane|tab|none> project=<repository or folder, or none>`.
  `apps` is the three largest by share (`none` when no window was under the capture, `unlocated`
  when Vignette did not see where it was taken), as bundle ids with no window title. The Herdr part is read off the main thread
  with the same focus and pick as Send's target (`HerdrFocus.clue`, `DestinationChoice`): the focused pane,
  the Claude Code session in it or, for a pane that runs none, the one in its tab, and that session's repository, or its folder
  when it has none. A Codex pane, a tab with two agents or no Herdr logs `none`. A focus that cannot be read logs
  `herdr=unread:<reason with its spaces as hyphens>`, with no session listing. A test launch reads no Herdr unless
  `VIGNETTE_HERDR_APP` and `VIGNETTE_HC` name one, so it logs `herdr=unread:no-herdr-app-or-hc`. The line comes after
  the `[origin]` line, once Herdr answers. An agent's file, a Stitch, a drawing's output and a recording log none.
- The status item has an autosave name and a seeded preferred position. AppKit keeps the position
  in the app's standard defaults under that name, so a test launch whose data moved uses
  `<bundle id>.test-launch` (`Identity.statusItemAutosaveName`) and never moves the person's own icon. Without it, a crowded
  menu bar on a notch Mac puts the new icon under the notch and it never appears. Opening Vignette
  again, from Finder or Spotlight, opens Settings (`applicationShouldHandleReopen`), or brings setup
  forward while it is up; with the icon hidden it is the way back. A `vignette://` URL is not a
  reopen (checked 2026-09-25), so a script's commands never open the window. The menu names its
  two screenshot switches as the Screenshots tab does, under an "After a Screenshot" section
  header, and its Live Ink switch as the Live Ink tab does.
- Files named `*-annotated.png` are outputs and are ignored by the watcher. `Stitch *.png`
  outputs are not ignored on purpose: they arrive like a capture, which is what carries a stitch into
  the annotator when `annotateOnCapture` is on. The watcher takes png, jpg, jpeg, and heic images
  and mov recordings (`ScreenshotWatcher.candidateExtensions`), reports removals to the stack
  (`[watcher] removed`), waits for a new file to decode before reporting it (a recording, until
  AVFoundation can read its video track), and gives up on one that never does after
  ten seconds (`[watcher] error never-stable`); the next folder event or stack open picks it up.
  Wake from sleep rescans the folder. The watcher keeps an index of the folder (name and
  modification date, from one bulk listing) so opening the stack and finding the newest screenshot
  never list the folder on the main thread. A screenshot is identified by its `ScreenshotKey`: its
  path as the watch folder spells it. The watcher, a stitch and an agent's push make keys with
  `ScreenshotKey(folder:name:)`, and the watcher reports keys, never URLs. A path from outside
  gets its key from the resolving initializer.
  `ScreenshotKey(asGiven:)` reads back a key that was stored, and names a file outside the folder
  for a debug-mode command. Every store that keeps something about
  a screenshot takes a key, and the drawing's file name is the SHA-256 of the key's path
  (`docs/screenshot-key-2026-10-17.md`, `docs/adr/0019-a-screenshot-is-its-watch-folder-key.md`).
  The same listing asks for each file's inode and size. A name that left the index and a name that
  entered it, with one inode, size and modification date between them, are one file renamed
  (`ScreenshotWatcher.renames`, `onRenamed`): its card, drawing, selection, queued place, notices
  and open editor move to the new key (`FolderWrites.renamed`, `ThumbnailController.rename`,
  `Drawings.rename`), and so do the request and reply records that name it
  (`ScreenshotRequests.renamed`). Nothing reports it as a removal or a capture. A file renamed to a
  name every listing hides, an agent reply's with no record, leaves as a removal. The watcher
  holds the renames a scan pairs until a delivery that covers that scan takes them
  (`ScreenshotWatcher.HeldRenames`). A pairing that is not one to
  one, a name with an undelivered arrival, or a folder that went missing falls back to a removal
  and an arrival. A rename seen only by a listing older than the app's last write waits for a
  newer listing, as a removal does. Every stack open asks for a rescan, which is how the
  index catches a file changed in place. The first listing runs on the watcher's queue and launch
  waits for it half a second: macOS holds the first read of a folder it protects (the Desktop,
  Documents, Downloads) until the user answers its prompt, and done on the main thread that read
  held the whole launch for as long as the prompt was up (measured: 4 minutes 20 seconds, no setup
  window and no menu bar icon). Until a listing has worked the reads answer from the empty index.
  While the folder cannot be watched (a volume not mounted yet, or macOS refused the app the
  folder) the reads list it directly and the watch is retried every 2 seconds, logging a change of
  reason rather than every attempt. A scan whose open fails with `EINTR`, `ENOENT`, `EPERM` or
  `EACCES` does not list the folder, and the error says why: unavailable, missing or refused. A
  listing then would meet the same refusal or wait on the same daemon: when macOS's sandbox daemon
  stopped answering, each open and each listing waited about 5.4 s and failed with EINTR. After any
  other error, such as a volume that can't be watched for events, the scan still lists the folder. The
  watcher keeps when the folder first failed to read (`ScreenshotWatcher.unreadable(after:)`).
  When every try for `ui.unreadableFolderSeconds` (5 s) has failed, the menu bar menu lists the
  failure first, greyed, since there is nothing to click. A missing folder reads Can't Find Your
  Screenshots Folder, and any other failure Can't Read Your Screenshots Folder Yet. A refusal shows
  Allow Access to Your Screenshots… at once. The wait keeps a slow read or a volume still mounting
  from showing a warning. The menu bar icon's dot turns yellow for either, and the yellow wins over
  an update's dot (`showStatusDot`). The watcher tells the app when a failure starts, ends or
  changes its reason (`onReadState`), and a timer wakes the dot when the grace ends
  (`folderReadChanged`). The intro's popover says the same. A press of the shortcut that finds
  nothing for this reason opens that popover under the icon, without the flight, in the menu item's
  words (`foundNothing`). It goes after 5 s, at a click on the icon, or at the next press, which
  opens no popover itself. The
  `[recent]` answer is `error unreadable-folder` with the reason. `[watcher] start` logs the
  watcher's creation, and `[watcher] watching` logs an open that worked. A folder that was there but unreadable is indexed silently by
  the first listing that works, so a grant does not report every file in it as a new capture; a
  missing folder is indexed as empty, and when it appears, as a volume mounts, the files dated
  before it was found missing are indexed silently and only newer ones are reported. `isDenied` (macOS refused
  the app the folder, at its open or at its listing) and `isReadable` (a listing worked) are what
  setup and the Screenshots tab read. A first launch whose folder is inside the Desktop, Documents
  or Downloads (`ScreenshotWatcher.protectedArea`) makes no watcher until setup's Allow…, its
  Continue or its closing (`watcherWaitsForSetup`), so macOS's prompt comes up under a row that says
  why. Setup reopened on live ink's permissions after Screen Recording's Quit & Reopen
  (`SetupWindowController.reopensOnLiveInk`) comes after the welcome page, which has already asked,
  so that launch starts the watcher at once, and a capture taken on that page gets its card. `recentShots` answers empty with no watcher, so nothing reads the folder before then.
  project.yml gives macOS's folder prompt its explanation
  (`NSDesktopFolderUsageDescription` and the Documents and Downloads keys).
  `docs/install-2026-09-24.md` has the measurements. Copying puts the image's own bytes on the
  pasteboard under its own type, `public.jpeg` for a JPEG, and promises the TIFF, and the PNG when
  the image is not one. Both are made only when a paste target asks.
- The main thread never reads a file that iCloud Drive has taken off the Mac. With Optimize Mac
  Storage on, an old file in an iCloud Desktop or Documents folder is a placeholder
  (`SF_DATALESS`), and any read of it, ImageIO's header or AVFoundation's asset, downloads all of
  it and waits: a 333 MB recording held the stack's opening for 14 s. The listing, `lstat`, resource
  values and extended attributes do not download. `Thumbnailer.lookUp` is what the main thread
  asks: `.notDownloaded` for a placeholder, and the card takes the kept shape or the screen's, with
  iCloud's thumbnail from Quick Look, which does not download (`Thumbnailer.cardImage`). A
  placeholder screenshot is downloaded in the background (`Thumbnailer.download`), because the
  editor reads the file on the main thread when it opens; a recording is not downloaded, and its
  badge shows no length. `docs/icloud-files-2026-09-25.md` has the measurements and what still
  reads on the main thread.
- A screen recording is a `Screenshot` whose `kind` is `.recording`, read from the `.mov`
  extension alone (`Screenshot.recordingExtensions`). Its card shows the first frame, decoded on
  the thumbnail queue (`Thumbnailer.posterFrame`, about 90 ms), and a badge with its length. Each
  action names the kinds it takes (`ShotAction.kinds`, images only unless it says otherwise), and
  `unavailableReason(for:)` is the one test: the strip greys a row that cannot take every selected
  card, its key beeps, and its URL answers `unsupported-type`. An action never runs on the part of
  a selection it can take. Draw and Open share Return and one strip row (`Config.stripRows` groups
  actions by key); the row shows whichever applies, and Draw when neither does. A click on a
  recording opens it in the app macOS opens movies with. A recording never reaches the annotator,
  so `annotateOnCapture`, the hold, and Draw on Newest Screenshot pass over it. Copy puts a recording
  on the pasteboard as its file URL and path, never its frames. Stitch takes its first frame, which
  is what its card shows (`Thumbnailer.posterFrame`, off the main thread).
  `docs/replacing-apple-capture-2026-09-22.md` has the measurements.
