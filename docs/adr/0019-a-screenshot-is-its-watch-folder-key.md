# A screenshot is its watch-folder key, and a rename moves it

Status: accepted, 2026-10-17.

A screenshot is identified by `ScreenshotKey`: its path as the watch folder spells it. The watcher
and one resolving initializer make keys, a stored key is read back as it was written, and every
store that keeps something about a screenshot takes one. A file renamed inside the folder, seen in one listing as the same inode, size and
modification date under a new name, keeps its drawing, its card and its place in the editor.

macOS offers no file identity that lasts: `st_dev` changes across reboots, and file resource
identifiers do not persist across restarts. Dropbox replaces files when it syncs. An id stored in an
extended attribute would change the person's file, which ADR 0011 forbids. So the identity is the
path, and the inode is used only to match a rename between two names in the same listing.

The drawing file stays named by a hash of the key's path, so existing drawings need no migration.
A rename while the app is not running, or a move out of the folder and back, still loses the
drawing. See `docs/screenshot-key-2026-10-17.md`.
