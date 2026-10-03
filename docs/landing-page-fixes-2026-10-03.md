# Landing page interaction fixes

The work covers the eight findings from the review of the current landing page.
Changes stay in the demo scripts under `site/demo/`.

1. Restore the hint when an editor closes. Stop automatic drawing when its editor closes or the visitor takes over.
2. Route Cmd+Return to Send. Keep plain Return as Copy on the visitor's drawing and Reply on Claude's drawing.
3. Let focused buttons and links handle Enter and Space. Let Tab leave a note.
4. Run one automatic drawing per editor. Disable its hint while it runs.
5. Update tool buttons in place, so switching tools keeps the message and keyboard focus.
6. Cancel pending card arrivals when the stack closes, including during a quick close and reopen.
7. Start clipboard writes during the visitor's gesture. Show the result after the browser settles the write.
8. Display message text literally in the demo terminal.

Review the script changes after each coherent set of fixes and after browser verification.
Use disposable checks for the reproduced failures, delayed clipboard results, interrupted drawing,
and both complete demos. Check desktop and phone layouts with motion on and Reduce Motion enabled.
Keep verification scripts and logs outside the repository.

Status: implemented and verified in Chromium.

JavaScript syntax checks and `git diff --check` passed. Both demos completed at desktop size
with ordinary motion and at phone width in dark mode with Reduce Motion enabled.

Browser checks covered closing and reopening the editor, repeated drawing clicks, Undo and tool
changes during automatic drawing, canceled Reply, native button activation, Tab leaving a note,
message retention, Cmd+Return, and literal message text. Rapid stack dismissal left every card hidden.

Clipboard checks used an isolated browser with controlled write outcomes. Successful writes
validated the generated PNG. Denied and delayed writes produced failure feedback. Out-of-order
results left the newest hint and card notice intact, including a manual Copy while the initial
capture write was pending. These checks did not write to the system clipboard.

Implementation and integration reviews checked cancellation, keyboard ownership, clipboard
activation, and result ordering. The final independent review found no remaining actionable issue.
Safari and iOS touch behavior were not verified.
