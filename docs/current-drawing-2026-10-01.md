# One answer to "this screenshot's drawing, now"

`Drawings.current(of:)` answers what a screenshot's drawing is now, for every caller. The editor's
open drawing wins over the stored file, because the editor hands its drawing over only 0.3 s after a
change. Before this change, each caller wrote that rule out itself.

An agent's push to the open drawing also changes. The editor answers the joined drawing, and
`Drawings.add` writes it. Before, the editor handed the drawing over through four callbacks, and
`add` learned whether the write worked by reading back a private `lastWrite` field.

## Why

The rule "the open editor's drawing beats the stored file" was in five places:

| Place | What it did |
| --- | --- |
| `AppDelegate.stitch` | `annotator.openDrawing(of:)`, else a read of the file |
| `AppDelegate.copyAnnotated` | the same, written again |
| `AppDelegate.dragItems` | `annotator.openDrawing(of:)`, else the card's drawing |
| `Drawings.add` | `editor.core.isOpen` and `editor.core.drawing.key`, read directly |
| `AnnotationController.openDrawing(of:)` | the check the first three called |

A new caller that forgot the rule would act on a drawing up to 0.3 s old. The push's write went
through `EditorView.onHandOver`, `AnnotationController.onDrawing`, the closure `AppDelegate` set,
and `Drawings.write`, which recorded `lastWrite` for `add` to read back. The only test of a push to
the open drawing rebuilt that wiring by hand.

## The interface

```swift
/// The drawing open in the editor. Its marks are ahead of the stored file until the editor's next hand-over.
@MainActor protocol OpenDrawing: AnyObject {
    func drawing(of key: String) -> Drawing?   // as the editor would hand it over now; nil when not open
    func join(_ marks: [Mark]) -> Drawing?     // one undo step; the drawing to store, or nil when none fit
}

final class Drawings {
    weak var open: OpenDrawing?
    func current(of url: URL, style: TextStyle) -> Drawing?             // the open drawing, else the file
    func current(of url: URL, stored: () -> Drawing?) -> Drawing?       // the open drawing, else the caller's copy
    func add(_ marks: [AgentMark], from: String?, to: URL, style:, newPointScale:) throws -> Int
}
```

`EditorView` is the app's adapter. The tests use a fake. `Drawings` no longer knows `EditorView`.

`current(of:style:)` reads the file only for a screenshot in `keys`, the set of screenshots with a
stored drawing. Before, Copy Drawing and Stitch read every screenshot's image header on the main
thread, and the header read downloads a file that iCloud has taken off the Mac.

`dragItems` passes the card's drawing as `stored`. A drag starts on the main thread, and the card
already holds the stored drawing, since every write reaches it through `onChange`.

## What stays

- `AnnotationController.storedDrawing` reads the file when the editor opens. Nothing is open then,
  so the stored drawing is the drawing now.
- The flights read the editor's `MarkLayers`, not only its drawing, because they reuse the editor's
  text bitmaps (`ThumbnailController.outFlightMarks`, `homeFlightMarks`).
- Done, Send and Cmd+C receive the drawing from the editor that produced them.

## Behaviour

The same, with one change. Copy Drawing and Stitch no longer read the image header of a screenshot
with no stored drawing.

## Tests

- `DrawingStoreTests`: a push to the open drawing writes what the join answers, once. A push whose
  write fails throws `writeFailed`. `current(of:)` answers the open drawing over the file, and the
  file once the editor is closed. These use a fake `OpenDrawing`, with no window.
- `EditorViewTests`: `join` answers the drawing with the agent's marks and does not call
  `onHandOver`, so the push is written once.
- `EditorCoreTests` already covers the join as one undo step.
- The e2e scenario `annotate_open` now also pushes a mark to the image while it is open. It checks
  that the open editor shows the mark, and that the mark is still there when the editor opens again.
  The unit tests cannot see the line that connects `Drawings` to the editor, and without it the
  editor's next write erases the push.

## Verification

1. `scripts/build.sh --test`: 411 tests pass, the three new ones included. `lsregister -u` was run on
   the built app.
2. Mutation checks, each restored afterwards:
   - `current` answering the stored drawing first fails `testTheDrawingNowIsTheOpenOneOverTheStoredOne`.
   - `join` also running its hand-over fails `testAJoinAnswersWithTheDrawingAndHandsNothingOver`.
   - Removing `drawings.open = annotator.editor` fails `annotate_open` at "the pushed mark in the
     open editor".
3. `scripts/e2e/e2e.py run`: every scenario without input passes, 47 checks. The log shows one
   `[drawing] saved` line for the push to the open drawing.
4. `scripts/e2e/e2e.py run --input` posts keys, so it runs with Pete's go-ahead.
