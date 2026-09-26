# Overnight run, 2026-09-25 to 2026-09-26

Everything below is built, tested and uncommitted in the main checkout. Your build runs from
`build/` again, on your own settings. It was `/Applications/Vignette.app` before.

`./scripts/build.sh --test` passes: 405 unit tests. Each feature was also driven live on the demo
copy, which has its own bundle id, settings and screenshot folder. For the live Send tests, the demo
copy's source was patched so Send logs the line instead of submitting it. Nothing reached a real
session.

## Ready to try

1. **Screenshots in iCloud no longer freeze the stack.** Your 18.8 s freeze came from reading
   screenshots that iCloud had taken off the Mac, on the main thread. Their cards now show iCloud's
   thumbnail at once. A screenshot downloads in the background; a recording does not. Launch went
   from 1616 ms to 57 ms with two such files. `docs/icloud-files-2026-09-25.md`.
2. **Setup's success state has more character.** Each press of the shortcut presses the key picture
   and puts a check on it. The line says "There they are. Now try holding the second tap.", then
   "That's the whole trick." once you hold.
3. **Settings opens with nothing focused.** "How many to show" was selected on open.
4. **Text you type stays in view when zoomed in.** The view follows the caret, as a text view scrolls
   to it. This was the "text runs off the edge" TODO: past the frame, the words were cut off by the
   window, not the image.
5. **Text shrinks to fit a small screenshot.** As you type, a text gets smaller just enough to end at
   the image's right edge, down to half its size (12 pt). Then it wraps. Deleting grows it back.
6. **Type right after drawing a box.** The first character you type starts a note beside the box.
   It goes to the right if there is room, else below, else above, growing upward. V, R, A and T
   still pick tools: the next key decides. A press keeps the tool, and a character makes the letter
   the start of the note. So "the" and "add" work, and A then a drag still draws an arrow.
7. **The Arrow tool draws freehand.** The arrow follows your pointer, smoothed, and the head goes
   where you let go. A stroke that stays near a straight line draws a straight arrow, which keeps its
   bend dot. Shift draws a straight one at 15° steps. Dragging a freehand arrow's end turns and
   scales the whole curve about the other end.
8. **A message goes with Send and Reply.** A field sits beside Send, and beside Reply. It grows down
   past the bar as you type, up to six lines, and shrinks back when you click the image. The
   message ends the line the agent gets. The skill now tells agents to read it as your request.

## Decisions for you

Each is built one way, and the other way is small.

- **Return in the message field beside Send does not send.** It bounces Send's ⌘↩ instead, and
  ⌘Return sends. I kept your rule that Return never sends to a session Vignette picked. Beside
  Reply, Return sends, as it does in the editor. The chat-style alternative, where Return always
  sends, is one line in `AnnotatorToolbar.swift`.
- **A note takes its colour from the colour pass, like any text.** So a red box on a light area can
  get a yellow note on a dark one. The alternative is a note that matches its box.
- **Only boxes get a note.** An arrow could take one at its tail the same way.
- **The freehand thresholds.** A stroke within 6 screen pt of a straight line, or 4% of its length,
  becomes straight. The curve stays within 1.5 screen pt of the smoothed stroke.
- **Agents' marks in their own typeface is not built.** The TODO leaves open what marks an agent's
  box or arrow. For texts I'd suggest SF Mono: it reads as the agent's at a glance, and it is
  Apple's own. It is wider than SF Pro Rounded, so an agent's note takes more room.
- **An older build rewrote the skill in this checkout.** Launching `/Applications/Vignette.app`
  replaced the repo's newer `SKILL.md` and `scripts/reply`, through the `~/.claude/skills` link. I
  put them back. The TODO recommends a version number in `SKILL.md`, so a launch rewrites only an
  older copy.
- **The thumbnail slider's label.** Earlier I offered to show its exact stored value, such as
  "7.5 seconds". You haven't said yet.

## Not checked

- **Esc in the message field.** The rules forbid a synthetic Esc, so only a click on the image was
  tested for handing the keys back.
- **The message field on a Reply card.** No card named a session during the tests. It shares the
  code with the Send side, which was tested.
- **An Agents switch, and setup's skill install.** Both write to your real `~/.claude` or `~/.codex`.
- **The Dropbox folder prompt in setup.**

## Worth knowing

- **Another agent drove the Simulator on this Mac overnight** (a window titled "Paddock v1 audit
  2026-09-26"). Before I started checking which app was in front, three ⌘= presses meant for the
  demo may have reached the Simulator.
- **Nothing is committed.** Scratch helpers are in `.scratch`: `demo-sync.sh` builds the demo copy
  with Send patched off, `demo-open.sh` opens an image in it, and `probe/curve` drags along a curve.

## Where each change is

| Change | Code | Docs |
|---|---|---|
| iCloud screenshots | `Thumbnailer.swift`, `ThumbnailController.swift` | `docs/icloud-files-2026-09-25.md`, AGENTS.md |
| Setup success state | `SetupWindow.swift`, `AppDelegate.swift` | `docs/settings-polish-2026-09-25.md` |
| Settings focus | `SettingsWindow.swift` | |
| Caret in view when zoomed | `EditorTextView.swift`, `EditorView.swift`, `AnnotationController.swift` | `docs/editor.md` |
| Text shrinks to fit | `EditorGeometry.fittedSize`, `EditorCore.typed` | `docs/editor.md`, How a text grows |
| A note for a box | `EditorCore.startsNote`, `EditorGeometry.notePlace`, `EditorView` | `docs/editor.md`, A note for a box |
| Freehand arrow | `Drawing.swift` (`via`), `MarkGeometry.swift` (`ArrowBody.Curve`), `MarkRendering.swift`, `EditorGeometry.freehandArrow`, `EditorCore` | `docs/editor.md`, Arrow |
| Message with Send | `AnnotatorToolbar.swift`, `AnnotationController.swift`, `AppDelegate.swift`, `ScreenshotRequests.requestLine` | `docs/request-line-2026-09-25.md`, `docs/send-and-reply-2026-09-24.md`, skill |

The file format change is one optional field: `via` on an arrow. A build from before it reads a
freehand arrow as the straight arrow between its ends, so the file's `version` stays 1.
