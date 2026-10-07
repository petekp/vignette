# Test audit, 2026-10-06

The unit tests are mostly sound. Nineteen changes remove what costs upkeep and protects nothing:
tests that a stronger test already covers, assertions that cannot fail, and production code that
only tests call. Two changes add checks where nothing guarded a contract: a drawing's file name
across versions, and the refusal of a reply changed after it was prepared. Two more make tests
check a rule instead of a hand-made list or a tuned number: every setting against Reduce Motion,
and the editor's geometry. On `main` the changes remove 114 lines of tests and 10 lines of
production code, net. Change 19, on `live-ink`, removes
about 15 more lines of production code. Nothing here changes what the app does.

## Where the work lands

- **On a new branch, `test-audit`, off `main`**, in `~/Code/worktrees/vignette/test-audit`.
  Changes 1 to 18 and 20 to 23 touch code that `main` already has. `main` has not moved since
  `live-ink` branched from it at `535e42b`.
- **Not on `live-ink`.** That branch has live ink work in progress, much of it uncommitted. Mixed
  into it, these changes would make that work harder to review, and they would wait for live ink to
  land.
- **The cost is one merge conflict and one follow-on edit.** `live-ink` adds a test directly above
  change 1 in `ScreenshotRequestsTests.swift`, so merging it after this branch needs one small
  resolution. Change 22's motion test also needs `live-ink`'s new settings sorted, which the merge
  does.
- **Change 19 goes on `live-ink`.** The code it removes exists only there.

## Commit 1: delete tests a stronger test covers

| # | Deleted | Covered by |
|---|---|---|
| 1 | `ScreenshotRequestsTests.testAValidReplyIsAcceptedAndAcknowledged` | `testAReplyTheCommandPreparesIsAcceptedAndItsRetryMakesNoSecondCard`, with the real reply helper |
| 2 | `ScreenshotRequestsTests.testTheSameReplyDispatchedAgainIsAcknowledgedAndMakesNoSecondCard` | The same helper test, whose retry takes the same branch. Its one extra check, a single reply record, moves there. |
| 3 | `AnnotatorTransitionTests.testCloseReturnsTheCard` | The last three lines of `testNewShotDuringALoneAnnotationJoinsInsteadOfClosing`, word for word |
| 4 | `EditorCoreTests.testParkingDuringADragKeepsTheMarkAsDrawn` | `EditorViewTests.testParkAnswersAtOnceWithTheDrawingAndIgnoresInputAfterwards`, through the real view |
| 5 | `EditorCoreTests.testCmdVOfAnImageAddsNothingAndBeeps` | `EditorViewTests.testCmdVOfAFileOrAnImageAddsNothingAndBeeps`, from a real pasteboard |
| 6 | `DrawingTests.testAMarksColourSaysWhoDrewIt` | The colour checks in `EditorCoreTests`, `AgentMarksTests` and `DrawingStoreTests`, and the rendered red in `MarkRenderingTests` |
| 7 | `SettingsTests.testMigrateStampsCurrentVersion` | `testFileWithoutVersionIsMigratedAndRewritten` and `testMissingKeysAreFilledInOnDisk`, which read the file on disk |
| 8 | `SettingsTests.testMigrateLeavesNewerFilesAlone` | `testNewerVersionIsReadOnly`, which checks the file is left byte for byte |
| 9 | `ZoomTests.testTheWholeImageStaysVisibleInASideThatIsStillGrowing` | `testTheVisiblePartNeverLeavesTheImage`, `testEachSideGrowsFirstAndIsMagnifiedOnlyAfterIt`, and `AnnotatorZoomTests.testAPanMovesOnlyAMagnifiedPictureAndLeavesTheFrame` |
| 10 | `ZoomTests.testAPanComesHomeToTheWholeImage` | `AnnotatorZoomTests.testADoubleTapZoomsInTwiceAndThenBackToTheFit`, at the real boundary |
| 11 | `MarkGeometryTests.testChineseAndAnEmojiLayOutWithASize` | `MarkRenderingTests.testATextWithChineseCharactersAndAnEmojiDrawsInkForBoth`, which checks the drawn ink. The deleted test still passed with every Chinese character and emoji typeset as a space. |
| 12 | `ThumbnailerTests.testAnyCaptureFormatIsSentAsRealPNGBytes` | `ScreenshotRequestsTests.testAPictureTheCommandSendsIsAPNGTheAppAccepts`, through the function's one remaining caller, the reply helper. Send stopped using the function on 2026-10-03. |

## Commit 2: trim what cannot fail

| # | Test | Change |
|---|---|---|
| 13 | `AgentConnectionTests.testACodexDestinationIsPinnedByTheRuntimeAndAClaudeOneByAPreflightCheck` | Delete. It repeats a two-case `switch`, and nothing branches on the answer. |
| 14 | `CommandsTests.testErrorCodesAreKebabCaseAndUnique` | Drop the uniqueness line, since Swift refuses duplicate raw values at compile time. Keep the kebab-case check, which guards the log's `error <code>` format, and rename the test to it. |
| 15 | `IdentityTests.testSignatureIsStableAndDistinguishesBundleIds` | Drop the line that compares a value with itself, and rename the test to what is left. |
| 16 | `ScreenshotRequestsTests.testASentDrawingIsStoredWithItsTicketBeforeAnythingIsSubmitted` | Delete. Nothing is submitted in it, so the order its name promises is never tested. Its one unique check, a non-empty secret, moves to `testTheRequestLineNamesTheImageBesideItsTicketAndNotTheSecret`. |

## Commit 3: remove production code that only tests call

- **17. `ClaudeCodeConnection.herdrBinary(exists:)`.** Production calls it only with the default,
  and its body is one `first(where:)`. Drop the `exists:` parameter, make `herdrPaths` private, and
  delete `AgentConnectionTests.testTheHerdrBinaryIsTheFirstOneThatExists`.
- **18. `ScreenshotWatcher.recent(in:limit:)` and `listing(of:)`.** No production code calls
  either. Delete both, and the default on `Inventory.candidates(retaining:)` that only
  `listing(of:)` used. `testRecentAreNewestFirstAndLimited` uses a watcher's own `recent(limit:)`,
  which sorts through the same `recent(from:)`, with every file in place before the watcher starts.
  It takes the candidate count from `testRecentCountsEveryCandidate`, which goes. The comment with
  the bulk listing's measurement moves to `read`.

## Commit 4: pin the drawing's file name

**20.** `DrawingStoreTests.testIdIsStableAndFilenameSafe` compared the id with itself and checked
that it is 32 hex characters. It asserts the known id for one fixed path instead.

- **What it protects:** every stored drawing's file name. A drawing is stored as `<id>.json`, and
  the id is a hash of the screenshot's path.
- **The failure it catches:** a different hash, or a change to what is hashed. After such an
  update, every saved drawing would stop showing on its screenshot.
- **Why nothing caught it:** the test computed the id twice in one run, so both sides changed
  together. Its length and hex checks pass for any 128-bit hash.

## Commit 5: refuse a reply changed after it was prepared

**21.** `ScreenshotRequestsTests.testABundleChangedAfterItsAttemptWasWrittenIsRefused` changes a
reply's bundle after its attempt names the digest, and expects `digest-mismatch`, no card and no
reply record.

- **What it protects:** a card shows exactly the bytes the reply helper checked.
- **The failure it catches:** `ScreenshotRequests.receiveReply` dropping or skipping its digest
  check. With the check removed, the changed reply was accepted and became a card.
- **Why nothing catches it now:** only the digest function itself was tested.

## Commit 6: check every setting against Reduce Motion

**22.** `MotionTests.testScaledTweaksTouchOnlyMotion` listed by hand the settings that motion
scales, and the list missed `shiftUpDuration` and `noteSettleDuration`. It now checks every setting
in `UITweaks.bounds`. At motion 0, a motion setting is 0 and every other setting is unchanged.

- **What counts as motion:** a name with Duration, Fade, Slide, Delay or stagger in it, and
  `flightArc` and `flightDepth`, the flight's bow and swell.
- **What does not, despite its name:** `textDragDelay`, a press's wait before a drag, and
  `introFunnelFade`, a share of the funnel's travel.
- **What it protects:** Reduce Motion and `ui.motion` reach every animation.
- **The failure it catches:** a new duration left out of `UITweaks.scaledForMotion`, which would
  keep animating with Reduce Motion on, and a dwell time or a size scaled by mistake. With
  `shiftUpDuration` dropped from `scaledForMotion`, the test fails. The old list did not name it.
- **On `live-ink`:** `liveInkDrawOn` is motion, and `liveInkGlowDelay`, how long the chord is held
  before the glow shows, is not. The merge adds each to its set.

## Commit 7: take geometry numbers from the code

**23.** Two tests hard-coded numbers worked out from tuned defaults, so retuning a default broke
them with no bug.

- `MarkGeometryTests.testLinesAreTheLineHeightApart` reads the note's padding from its style.
- `EditorCoreTests.testTheHandlesOfAMarkInTheImagesCornerCanAllBeTakenInsideTheImage` states its
  rule in the editor's own geometry: the frame's sides at the image's edge are the outline offset
  inside it, and its other sides the outline offset outside the ink. Its hit areas are the
  corner and edge hit sizes on screen.
- **Checked both ways:** both pass with seven defaults retuned (the hit sizes, the outline, stroke
  and edge widths, and the note padding). Each fails when its rule breaks: the frame allowed past
  the image's edge, or the note's top padding read from the bottom.

## On `live-ink`: change 19

`LiveAnswerLayout.marks(for:)`, `pointer(_:at:scene:obstacles:)` and `arrow(to:room:obstacles:)`
are wrappers that only tests call.

- The six `marks(for:)` calls in `LiveInkTests` use `placed(for:).marks`.
- The circle and line test calls `pointers(…)`, which `placed(for:)` uses, and checks the kind it
  offers first.
- The arrow test goes through `placed(for:)`, with the obstacle as scene text, since `placed` picks
  among the arrows by its own costs.
- The assertion "from the right, which is clear" goes. With no obstacles every side costs the same,
  so it passes only because of the order the candidates are listed in.
- The comments in `placed(for:)` and `LiveInk.swift` that name `marks(for:)` change with it.

This lands with the live ink commit or right after it.

## Verification

- **The suite.** 475 tests passed on `main` before the change and 460 after: 16 deleted and one
  added.
- **Each deletion's cover was proved.** For changes 2, 4, 5, 9, 10, 11 and 12, the production line
  the deleted test guarded was broken on purpose, and the covering test failed each time. The lines
  were then put back.
- **The changed and added tests catch their failures.** The pinned id fails when the hash's input
  changes, the watcher test fails when equal dates stop falling to the name, and the new reply test
  fails when `receiveReply` skips its digest check. Changes 22 and 23 were checked as their
  sections say.
- **Builds** went to the worktree's `.derived-data`. Nothing a person sees changes, so the app was
  not launched.

## Left as they are

- **Five tests that overlap a stronger one but have a reason of their own:**
  `CommandsTests.testHelpNamesEveryCommandAndAction`,
  `EditorCoreTests.testRightAfterDrawingARectangleAClickOnEmptySpaceThenCmdCCopiesTheDrawing`,
  `EditorCoreTests.testCmdASelectsEveryMark`,
  `ScreenshotWatcherTests.testDiffReportsAddedAndRemovedSorted`, and
  `ZoomTests.testTheWindowAndTheCameraMultiplyToTheLevelInEachDirection`.
- **Tests that look like copies but guard a contract:** the random-sequence tests AGENTS.md names,
  the argument lists for `codex`, `claude` and `herdr`, the security refusals, the memory-bound
  checks, and the live ink answer format.

