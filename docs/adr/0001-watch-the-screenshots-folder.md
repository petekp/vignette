# Vignette watches macOS's screenshots folder and replaces Apple's thumbnail

Vignette never captures. macOS's own shortcuts capture, and Vignette watches the folder macOS saves
to, following macOS when that folder changes, so a Mac keeps one save location and one set of
capture shortcuts. Apple's floating thumbnail holds the file back for about 5.6 s, so a paste right
after a capture pasted what was on the clipboard before. First launch therefore turns the thumbnail
off without asking, and quitting Vignette turns it back on.

## Considered options

- A setting to keep Apple's thumbnail. Rejected because it presented a broken install as a
  preference. Installing Vignette is the choice of what happens after a capture.
- A folder chosen in Vignette's setup. Replaced on 2026-09-26 by following macOS's save location.

Sources: `docs/replacing-apple-capture-2026-09-22.md`, commits e3d24a0 and 0d73cf5.
