# Screenshot comments: Undo, state machines and build steps

Part of [the screenshot comments plan](../screenshot-comments-2026-11-24.md).

## Undo and redo

Each pin step is one editor step in the history the message field shares (`docs/editor-undo.md`).
The undo timeline keeps that history between an opening and its close (ADR 0029). The timeline
itself does not change.

`HistoryStep` today has a marks kind and a message kind. Moving or deleting pins and marks together
has to be one step, so the marks kind becomes a drawing kind that holds both. Its marks are named by
index, as now, and its pins by `id`, each stored as it was before and after.

| Step | Name |
|---|---|
| Making a pin with its first comment | Comment |
| Posting another comment on a pin | Comment |
| Editing a comment's words, one composer session | Typing |
| Moving pins, alone or with marks | Move |
| Resizing an area pin | Resize |
| Deleting pins, alone or with marks | Delete |
| Pasting pins | Paste |

- Undo of a deleted pin brings back its number. Undo of a new pin takes it away, and redo brings it
  back with the same number.
- An older build that met a pin step would drop the whole history, so a file with one is version 2.

## State machines that change

Each change updates its file in `docs/state-machines/` in the same commit, as the index asks.

| Machine | File | What changes |
|---|---|---|
| EditorCore | editor-core | `Tool.comment`. A gesture phase for a pin's area. Typing becomes a note or a comment, one at a time. Selection holds marks and pins. The drawing step kind. `nextPin`. Cmd+Return from the composer. |
| HeldKey and HeldToolLetter | editor-core | C is a tool letter, so a C typed right after a box is held like V, R, A and T |
| EditorView session | editor-view-and-drawings | The composer's lifecycle beside `TypingField`, its popover, and its late answers after park |
| MarkLayers | editor-view-and-drawings | Teardrop and cluster layers, each teardrop's orientation, and their springs into and out of clusters |
| Drawings and DrawingStore | editor-view-and-drawings | `Drawing.isEmpty`, `keys` meaning "has a drawing", version 2 writes, `basis` |
| Rendering and the clipboard promise | editor-view-and-drawings | The list's layout, a larger output, and the clipboard's text |
| AnnotatorZoom, `fitBeforeHide` and `hideWindows` | zoom-and-panels | Scrolling to a pin from a list, a popover open while zooming, and the popover leaving before the windows hide |
| AnnotationController session | annotation-run-effects | Park and a screenshot swap while the composer is open |
| AnnotatorToolbar.Model | toolbar | The Comment tool, the pins list button, and who has the keys while the composer is open |
| Stitch converge, UndoTimeline | stack | For Choice 6: the stitch's drawing written before its card, unstitch and restitch carrying it, Trash undo bringing pins back |
| CardNotices | corner | For Choice 6: the stitch's Copied notice waiting on its rendering |
| Screenshot requests | requests-and-replies | `pins.json` and the line's pins, and in step 4 a reply's comments |

## Build steps

Each step merges on its own and leaves the app working. Each updates `docs/editor.md`, the rules
files it touches, and `docs/voice.md` for any new words.

1. Pins in the drawing. `Pin` and `Comment` beside `Mark`. `Drawing.isEmpty` and every
   `marks.isEmpty` site moved to it. The file keys, version 2 writes, the validator, `basis`,
   `nextPin`, and the drawing step kind. The renderer draws pins as teardrops on cards, flights and
   PNGs, with the orientation rule. Nothing makes a pin yet. The glossary gets the four words and
   the new meaning of Drawing. Unit tests check each of these. A pinned file round-trips. A file
   holding pins, a `nextPin` or a pin step is written as version 2. A pin outside the image is moved
   in. A bad pin is dropped. A teardrop at the picture's top or right edge flips inside it. A
   drawing holding only pins follows a rename, comes back with Trash undo, goes into a stitch's
   piece, and changes `Agent.fingerprint`.

   Step 1 settled these points the plan left open:
   - A comment is the type `Pin.Comment`, since it means nothing apart from its pin.
   - A pin's colour is the writer of its first comment: indigo when an agent made the pin, red
     otherwise.
   - The teardrop is 24 drawing pt, `PinTeardrop.side`, and its number is SF Pro Rounded for a
     person's pin and SF Mono for an agent's, as their notes are. The size becomes a `UITweaks`
     setting in step 3, beside the outline's width and the cluster distance, since step 3 is
     where it can first be seen and tuned.
   - The edge rule counts the white edge, so a flipped teardrop's edge stays inside the picture.
   - Until step 3, the editor draws a pin through `MarkLayers` at mark scale, as a card does.
     Step 3 gives it one size on screen at every zoom.
   - A history step leaves out `changes` when it changed only pins, and `pins` when it changed
     only marks. A file with no pins and `nextPin` 1 keeps the `basis` it had before pins, so
     stored histories stay valid.
   - Copied marks on the clipboard stay version 1, since they never hold pins.
   - Reading a file with no marks and no pins gives no drawing, even when it keeps a `nextPin`
     beside a message. A write keeps the file's higher `nextPin`. Step 3 must open the editor
     with the stored `nextPin`, so a new pin's number is not one a deleted pin had.
2. Outputs. Copy, Copy Drawing and a drag as the picture with its list, with the clipboard's text.
   Send's image and line, and `pins.json`. Stitch's live pins, and the teardrop's flip away from a
   piece's number. Reply's change check. The skill's words. Verified by rendering tests from fixture
   drawings for each output, and a test of the line. Then one send each to a Claude Code session and
   a Codex thread in the VM, measuring the longest line each takes whole.
3. The Comment tool and dense areas. The tool and its gestures. The composer in its popover.
   Posting, editing and deleting comments. Moving and resizing pins, undo, and the keys in [Pins in
   the editor](editor.md), Shift+Return placement included. Teardrops at one size on screen, their
   hit area, and the flight hand-over. Clusters in the editor and on cards, the cluster popover, and
   the toolbar's list of pins. The pin elements, the Pins rotor and Add Pin for VoiceOver. Clusters
   ship with the tool because a crowded area is the case Pete asked about. Verified by editor-core
   tests of the composer's keys, of a press on a teardrop beside a mark, and of the cluster rule at
   several zooms, including pins on one point. Then Pete checks by eye on his build. He checks ten
   pins on a dense screenshot with their comments, Copy and Send. Someone who did not write a copy
   pastes it into a chat and an issue, and matches every comment to its place. He repeats that after
   deleting an earlier pin, and with long comments on a small screenshot. He checks a copy of a
   drawing with one arrow, a terminal paste, reopening, Stitch, and a reply of marks only, in Claude
   Code and in Codex. He checks VoiceOver by hand.
4. Agents answer on pins (Choice 5). Its ADR is written first. Then the reply helper takes
   `--comments`, `ReplyProtocol.version` goes up, a request stores `base.png`, the reply card holds
   the person's pins with the answers, and the skill says how. Verified by protocol tests and one
   live round in the VM with each agent client.

Steps 1 and 2 show nothing new on their own. Step 3 is the first a person sees.
