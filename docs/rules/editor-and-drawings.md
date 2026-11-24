# The editor and drawings

- The drawing editor is Swift, in `Sources/`. `Drawing.swift` is a drawing and its marks, the file
  format, and the one validator for files, pastes and agents' marks. `EditorCore.swift` is the
  editor's reducer, with `EditorGeometry.swift` and `EditorHistory.swift`. `EditorView.swift` hosts
  it in AppKit. `EditorLayers.swift` draws the picture and the overlay, `EditorTextView.swift` the
  text being typed, and `MarkLayers.swift` the marks, for the editor, the cards (`MarksView.swift`)
  and the flights. `MarkRendering.swift` is the renderer and `MarkGeometry.swift` the geometry it
  shares; `AgentMarks.swift` turns an agent's marks into a
  drawing's, `RenderingQueue.swift` runs the renderings, and `Drawings.swift` keeps the drawings on
  disk. `docs/editor.md` says how the editor behaves.
- The editor is a pure reducer and a view that decides nothing. `EditorCore.reduce` takes one
  `Input` and returns the `Effect`s to run, in order; `EditorView` turns events into inputs, runs
  those effects, and draws the core's state in one `CATransaction`. What a press hits is
  `core.target(at:)`, tested against the overlay as drawn and then the marks, so a test drives the
  core with no window. Cmd+Z and Shift+Cmd+Z always reach the editor (`performKeyEquivalent`, and
  `FieldCommand.undo` from the message field), so one owner handles undo whether a text or the
  message is being typed or not. The message field's changes are steps in the core's history
  (`Input.messageChanged`), and its text view keeps no undo of its own (`allowsUndo` is off). Each
  step has a `StepName`, which the Edit menu's items take through `validateMenuItem` on the editor
  and `validateUserInterfaceItem` on the bar's panel; `MainMenu.swift` builds plain "Undo" and
  "Redo". The history is kept in the drawing's file under `history` (`EditorHistory.fileObject`),
  checked on read against a hash of the marks and the message it ends at, so a drawing changed by
  another writer opens with none (ADR 0028). Agents' marks added while it is closed are one step of
  it (`Drawings.add`). While typing, the core takes only
  the keys `takesKey` names and the text view gets the rest, and an input method's composition owns
  every key until it is confirmed. A character right after a box is drawn starts a note for it
  (`startsNote`): the core begins typing and answers `passKeysToText`, and the view replays the key
  event into the text view, so an input method or a dead key composes as usual. A tool key then is
  held (`holdKey`, `heldKeys` in the view) until the next key shows whether it began a word. The
  hold is `HeldToolLetter`, the same value the toolbar's message field holds a letter with, so the
  rule is written once. A Cmd key the core does not take goes on to the menu.
  `docs/editor.md` is the behaviour: keys, gestures, what a press hits, the clipboard, the file.
- A mark has one geometry, and the renderer owns it. `Mark.shape(pointScale:markStyle:)` gives a
  rectangle's, an ellipse's or an arrow's paths, which the renderer draws and `MarkLayers` puts in
  `CAShapeLayer`s, so a shape looks the same in the editor, on a card, in flight and in the PNG. A
  text is a note: a rounded tag in the mark's colour with its words on it, and on an agent's note a
  badge naming the agent (`docs/note-tags-2026-09-29.md`). `TextLayout` owns the tag's geometry,
  its padding, the 18 em cap and the balanced line breaks, and its `box` is the tag, which is what a
  press hits and what is kept inside the image. The tag, the badge and the letters are drawn only by
  the renderer (`MarkRendering.swift`, `NoteTag.draw`), with every letter filled in one pass. An
  agent's text is set in SF Mono and a person's in SF Pro Rounded, and an agent's badge names it:
  every place that lays a text out takes the style from its mark (`TextStyle.forMark`), and the
  editor's `layout(_:of:)` takes the mark, so none can forget. The text being typed wraps without
  balancing, and when typing ends its view springs to the balanced lines
  (`TypingField.settle`) before the drawn note replaces it. `EditorTextView`, the text being typed,
  draws the tag with `NoteTag.draw` under its words, wraps at the layout's `wrapWidth`, and sets
  every line's baseline from `TextLayout` through its layout manager's delegate, so typing and the
  drawn text meet within half a point. The badge's logo comes from `AgentLogos`, which rasterizes
  `Resources/agents/<name>.svg` once so any thread can draw it.
- `MarkLayers` is the one on-screen drawer for a drawing's marks: the editor (`EditorPicture`), a card
  (`MarksView`) and a flight, so a mark looks the same in each and nothing steps when a flight hands
  over to the editor. A text is a bitmap the renderer draws off the main thread, on
  `MarkLayers.textQueue` for the editor and flights and `cardQueue` for cards, so a stack of long
  texts never delays the one being edited. The bitmap is an `IOSurface`, because Core Animation
  copies a `CGImage` on the main thread at the commit that shows it and doubles its memory
  (`docs/native-editor-2026-09-23.md` has the cost). A bitmap is shown only while its text still
  wants exactly that `Target` (mark, region, scale, style), so a bitmap never crosses styles, and
  none is shown after `park()`. A text keeps at most two bitmaps, a whole and a sharper detail, the
  one on its way included. Each owner's plan caps them: the editor's at the view's size in device
  pixels, a card's at the part of the image the card shows at its rest size. The comments in
  `MarkLayers.swift` and `MarksView.swift` say how bitmaps are shared between the editor and a
  flight, restyled, and flattened on a card.
- Drawings are owned by the app, and every write goes through `Drawings` (`Drawings.swift`, with
  `DrawingStore` for the files): one JSON file per screenshot under
  `~/Library/Application Support/<bundle id>/drawings/` (`Identity.applicationSupportURL`, which
  `Launch.dataHome` moves for a test copy), named by a hash of the screenshot's
  `ScreenshotKey` path (`key.path`). The editor hands its drawing over 0.3 s after each change,
  never while a button is held (`[drawing] saved`), and once more when it parks (`parked`). Until
  then the open drawing is ahead of its file, so whatever needs a screenshot's drawing as it is now
  (Copy Drawing, Stitch, a drag) asks `Drawings.current(of:)`, which answers the open drawing over
  the stored one. `Drawings` reaches the editor only through `OpenDrawing`, which `EditorView` is.
  Agents' marks arrive through `Drawings.add` (`built`, or `saved` when they join the open drawing:
  the editor's `join` answers the joined drawing and `add` writes it). A drawing with no marks removes its file, unless the file holds a message. The file also keeps
  what was last typed in the message field for the screenshot (`message`, `docs/drawing-file.md`),
  so the screenshot opens in the editor with it again: after Send, Reply, Copy, Esc, a failed send
  or a relaunch alike. The editor's hand-overs carry the field's words, and the field's own changes
  are written 0.3 s after the last one (`Drawings.keepMessage`, `[drawing] message saved` or
  `message removed`), beside the marks the file holds. `Drawings.keys` names the screenshots with
  marks and `Drawings.messages` those with a message; a rename, a removal and the sweep move or
  remove both. The field holding only those words counts as untouched until something is typed
  (`Model.messageAsOpened`, `docs/rules/annotator-toolbar.md`), since the session Vignette picked
  may not be the one they were typed for. When the field takes the keys on its own or for M or P,
  its caret goes after the words, where AppKit would select them all. A drawing with marks whose screenshot is gone is not
  written (`[drawing] dropped <name>: its screenshot is gone`). The editor hands its drawing over
  through `Drawings.handOver`. When that write fails after the editor let go of the drawing, the
  card says "Not saved" (`Drawings.onWriteFailed`, `ThumbnailController.showNotSaved`), and after
  Done it lands without Copied. While the editor holds the drawing, the next hand-over writes it
  again. An empty drawing that a newer build's file refuses is not reported, since no marks are
  lost. `add`, a reply's install and live ink write through `write`, which answers its caller and
  puts nothing on a card. `onChange` hands each card its
  drawing, so a write reaches the card at once. `load` takes a list and reads it in one job off the
  main thread, and a stack opening reads its cards' drawings in one such job per turn and changes
  `cards` once (`ThumbnailController.setDrawings`). A key written or removed while it was read is
  left out of the answer, since `onChange` already said what it is. A file that does not parse is
  set aside as `<id>.json.invalid` only by the launch scan (`DrawingStore.scan`), which runs before
  anything reads or writes a drawing. A read at any other time logs
  `[drawing] error invalid <name>: <reason>; opened without it` and leaves the file where it is.
  Reads run beside the main thread's writes, so a read that moved the file could move a good one a
  write had just put in its place. A newer build's file, another screenshot's, or one made on an
  image of another size is read as no drawing and left where it is. Cleanup waits for a successful
  `ScreenshotWatcher.Inventory` for that drawing's folder. It uses enumerated presence and the
  observation time; unavailable folders retain their inventory and drawings. A positive file lookup
  also preserves a file created since the observation or reached through a case alias. The removal
  callback applies the same check to cards, drawings, and reply records. Suppressed removals stay
  pending until a listing enumerates their presence or confirms their absence. Writes newer
  than the observation wait for another scan. Trash removes drawings only for files it successfully
  trashed. `FolderWrites` holds these removals back and tells the cards, drawings and requests.
  `docs/system-design-work-2026-10-02.md` records the verification. The launch also
  removes what earlier builds left (`Leftovers`): the web editor's drafts, which
  are not carried over, WebKit's data and the shadow log, `send-context.jsonl`. Each logs one
  `[app] removed <what> <path>` line.
- Done, Send, Copy Drawing and a drag of a card with a drawing render on `RenderingQueue.shared`, one
  at a time, off the main thread: one rendering of the largest capture holds two bitmaps of about
  85 MB. Done's rendering, and Cmd+C with nothing selected, go `.first`, ahead of any rendering that
  has not started, because Done's clipboard is a promise. `Clipboard.copyRendering` puts the path on as text at once and promises
  the PNG, the TIFF and the file URL; a paste that comes first waits for the rendering on the main
  thread for up to 5 s, then gets nothing and logs `[clipboard] error`. The card goes home at once.
  A dragged card with a drawing carries the same item, its PNG rendered from the hover or press
  (`DragItems`). In a selection, the hovered or pressed card is rendered first, and at most two more
  with it; the rest are rendered in turn as the drag begins. A drop target that asks for one of
  those first holds the main thread until it is rendered, and gets nothing for it after 5 s, as a
  paste does. Each is written as `<name>-<result-id>-annotated.png` as the drag begins; a card without
  one drops its file.
  A rendering that fails clears the clipboard, unless something else was copied since, and the card
  says "Not copied" and why in place of its Copied notice (`ThumbnailController.showNotCopied`,
  `Rendering.Failure.reason`). `[annotate] done files=["<absolute path>"] <n> bytes, copied` is
  logged when the file is written. `copy-annotated` and drag completion report the same JSON
  `files=` array. `RenderingQueue` allocates each result path and `PendingRendering` owns it;
  clipboard callers supply only the pending result. Completed files stay until the person deletes
  them. The source-name prefix respects filename and full-path limits, including the physical
  path behind directory symlinks, while keeping the full result id and `-annotated.png` suffix
  (`docs/adr/0018-rendered-files-are-immutable-results.md`). A drawing with no marks copies the
  original file and writes nothing. Send renders even an empty drawing through the queue, to preserve displayed orientation
  and DPI, and writes no file beside the source.
- A mark's colour says who drew it and is not stored: `Mark.color` names a person's colour or the
  agent colour (`MarkColor`, from `agent`), and `MarkStyle.color` gives the settings' red or indigo.
  Contrast comes from a 1.5 pt white edge (`MarkStyle.edgeWidth`) around every mark, notes included,
  which casts the tag's shadows. An agent's
  `color` in `marks=` is ignored and logged. An agent's note becomes the person's when typing ends
  with its words changed (`EditorCore.endTyping`), as one undo step; a move or a resize keeps it the
  agent's. `docs/mark-colour-2026-09-29.md` has the reasons and the candidates.
- A drawing's sizes are in points of its own `pointScale`, which is the screen's backing scale times
  the drawing's `markScale`. A new drawing in the annotator takes the screen it opens on; one an
  agent's marks create takes `NSScreen.main`, the best guess with no annotator open. Both are
  clamped to `Drawing.pointScales`. `MarkScaleRule` sets the mark scale from the image's area
  against that screen's, in screen points: 1 for a capture of the whole screen or anything larger,
  less for a smaller one, and never so small that a new note's text reaches a model that resizes the
  image (`Stitch.readerScale`) under `ui.smallestNoteText` px. Every drawer converts through
  `pointScale` alone, so the editor, the text being typed, cards, flights, renderings and stitches
  draw the same size, and so does an older build that shares the drawings folder. The file writes
  `markScale` only when it is under 1, and the format's version stays 1
  (`docs/adr/0025-marks-are-sized-to-the-screenshot.md`). A stored drawing keeps both, so a mark
  keeps its size in the image when the drawing is opened on another screen or after the rule
  changes. A change to `ui.markScalePower` or `ui.smallestNoteText` rescales the open drawing
  (`EditorCore.Input.rescaled`), which hands it over and is no undo step. An agent's note keeps
  `ui.agentTextSize` of the image's width, with the same floor (`AgentMarks`). Live ink's cards keep
  full-size marks (`UITweaks.liveInkMarkScaleRule`, `docs/live-ink.md`).
  `docs/mark-scale-2026-10-27.md` has the reasons and the measurements.
