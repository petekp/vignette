# Fable 5.1 system design assessment

Independent consultation at max effort. Source: `468b48397dff0cc776c36b6a01199cc886f4167b`. Date: October 2, 2026.

The consultation body is reproduced unchanged. [The synthesis](system-design-synthesis-2026-10-02.md) verifies and qualifies its recommendations.

## Overall judgment and system map

Vignette's hard decisions already sit in pure reducers with random-sequence tests, and the agent loop separates acceptance from publication with durable records. The weak seams are in the wiring. The push flow, the send flow, destination settling and the watcher's lifecycle live in the composition root as mutable state with no tests at their own interface. Nothing I found needs a new layer, dependency or process. Each recommendation moves state to an owner that already exists, or into a small value type of the kind the project already uses.

| System | Decides | Seam today | Tests at the seam |
|---|---|---|---|
| Capture and images | `ScreenshotWatcher` index, `Thumbnailer` cache | two closures from AppDelegate, a budget knob, no port | watcher folder tests, cache eviction tests |
| Stack, flights, annotator | `AnnotationRun` with `AnnotatorTransition` inside, `AnnotatorZoom`, `FlightPress` | ThumbnailController runs effects, 12 closures to AnnotationController | random-sequence tests on all four values, e2e for the handover |
| Editor, drawings, output | `EditorCore`, `Drawings` over `DrawingStore`, one renderer, `RenderingQueue` | `OpenDrawing` protocol with a real and a fake adapter | sequence tests, pixel captures, store tests |
| Settings, startup, platform | `Settings` bootstrap, `SetupWindowController`, `LoginItem`, `AppLocation` | a process singleton read in 16 files | bootstrap and migration tests, e2e first launch |
| Agents | `ScreenshotRequests`, `AgentConnection` with two real adapters, `ReplyProtocol`, `AgentPlugin` | protocol, callbacks struct, injected runners | request, protocol, plugin and connection tests, two e2e send-and-reply paths |

## Prioritized opportunities

**1. The push and send flows are state machines inside the composition root.** Severity medium, confidence high.

- Evidence: `Sources/AppDelegate.swift:55-69` declares `PendingAdd` and the sent-shot map, lines 1077-1142 run the add flow, lines 1250-1306 the send flow. No file under `Tests/` references either name. The e2e scenarios `agent_push`, `annotate_open` and `send_and_reply` cover only the happy paths.
- Caller burden: the watcher's report must look up a pending push by file name, a joining mark must flip a flag, and the presentation waits on whichever of two triggers comes last. A delivery answer finds its card through a same-launch map, while a failed reply rebuilds a URL from the current watch folder plus a bare file name. Those two answer differently after a folder change or a relaunch, as lines 1167-1184 show.
- Proposed owner: a `Pushes` value with inputs for pushed, file appeared, marks joined and copy failed, answering present or annotate. `ScreenshotRequests` keeps the sent screenshot's URL for the launch and hands the same `Screenshot` to both callbacks, so the map leaves AppDelegate. The record's `source` stays a name, as its comment intends.
- Smaller alternative: keep the code where it is, turn the present decision into a static function with tests, and make the delivered callback resolve the card the way the failed-reply callback does.
- Tradeoff: one more small value type, and the request store learns one in-memory fact about the launch.
- Verification: table tests for a report arriving before marks join, a file already in the folder, and a copy that fails. The e2e push scenarios stay as they are.

**2. Settling the send target has four owners and one untested rule.** Severity medium, confidence medium-high.

- Evidence: `Sources/AppDelegate.swift:1207-1243` orders the Codex app's shown thread before the listing and computes whether a kept list may settle. `Sources/ScreenshotRequests.swift:219-282` tracks kept, fresh and complete. `Sources/AgentConnection.swift:94-116` marks focus, and `Sources/AnnotatorToolbar.swift:108-146` carries a target across a swap. `ToolbarOfferTests` and `AgentConnectionTests` cover the two ends, nothing covers the middle.
- Caller burden: to open one image correctly the caller must read a log off the main thread, then list, then mark, then weaken the complete flag, then call the model. Four booleans travel through three modules.
- A concrete gap: the listing's late-answer guard compares the image path, at lines 1220 and 1235, while the send path compares the open's generation at lines 1251 and 1272. An image closed and reopened can take a list fetched for its earlier open.
- Proposed owner: the request store's `destinations` call takes a came-from hint and answers with a settles flag computed in one place, keyed by the open's generation. The controller then forwards without deciding.
- Smaller alternative: extract the three-line waits rule into a static function and test the kept-list cases, and switch the guard to the generation.
- Tradeoff: the request store gains a dependency on the Codex app helper, or a new small value carries the rule.
- Verification: tests for a kept list lacking the shown thread, a fresh list settling, and an answer for a reopened image being dropped. This matters before the planned session tabs multiply targets.

**3. The flight lift gate is the last handover decision still written imperatively.** Severity low-medium, confidence medium.

- Evidence: `Sources/ThumbnailController.swift:173-181` holds three gate fields, lines 476-495 test them, line 827 resets them in prepare, and line 860 retests on arrival. `TransitionLayer` keeps its own pending-lift set at lines 365-368.
- Caller burden: three call sites must each recheck the run's key, and a late decode for an abandoned image is kept out only by that recheck.
- Proposed owner: a `FlightLanding` value in the style of `FlightPress`, with inputs for prepare, loaded, takes events, arrived and ended, answering lift. The controller holds it and runs the one effect.
- Smaller alternative: leave it. The e2e `wait_editor` step already asserts the observable order.
- Tradeoff: marginal leverage for a new file. Do it only when the handover is next touched.
- Verification: table tests including a loaded answer for a key already abandoned.

**4. A folder change rebuilds the watcher on the main thread and leaves old state behind.** Severity low-medium, confidence high.

- Evidence: `Sources/ScreenshotWatcher.swift:36-49` waits up to half a second during construction. `Sources/AppDelegate.swift:208-221` reconstructs on every folder change, and lines 1346-1374 clear neither pending pushes nor the stack. Following Apple's location at `Sources/Settings.swift:759-768` means a pick in the system capture menu triggers this path.
- Caller burden: a caller must know construction may block and that pushes keyed by name outlive the folder they named.
- Proposed interface: the first-listing wait becomes a parameter the launch alone sets, and a folder change runs one routine that dismisses the stack and drops pending pushes.
- Smaller alternative: pass the wait flag only, since the wait is the user-visible hitch.
- Tradeoff: none for the wait. Dismissing the stack on a folder change is a behavior choice to confirm.
- Verification: a watcher test that construction returns at once when asked not to wait.

**5. Settings are read as a global from sixteen files.** Severity low, confidence high.

| File | Reads of the shared settings |
|---|---|
| `AnnotatorToolbar.swift` | 14 |
| `AnnotationController.swift` | 12 |
| `StackView.swift` | 9 |
| all others combined | 34 |

- Evidence: `StackLayout.current` is the documented single reader for layout, but motion and timing are read ad hoc, including inside `TransitionLayer.fly` and SwiftUI view bodies.
- Caller burden: a test of any of these modules depends on the scheme's settings path, and a tweak's reach is found by search.
- Proposed interface: no injection framework. Where a module already receives a style through `applyTweaks`, finish the job so it reads nothing itself, and let views take tweaks from their model.
- Tradeoff: churn without a user-visible gain, so do it as files are touched.

**6. Tooling, separately scoped: the trailer still patches source, and pixel tests hinge on an undocumented symbol.** Severity low, confidence high.

- Evidence: `media/trailer/trailer.py:123-139` rewrites arrays in `AgentConnection.swift` and the skill's scheme with regular expressions and exits if the shape drifts. The e2e plan records that `AgentTools.forSessions` and `AgentPlugin.stage` now make those patches unnecessary.
- Evidence: `Tests/WindowCapture.swift:14` loads `CGWindowListCreateImage` through dlsym, and six tests across `EditorViewTests` and `CardMarksTests` depend on it. The app already captures its own windows with ScreenCaptureKit in `Sources/MenuBarIntro.swift:651-691`.
- Proposed: drop the trailer patches. Give the tests the ScreenCaptureKit path, or make them skip with a named reason when the symbol is gone rather than fail.
- Verification: the stage copy still lists no real session, and the pixel tests still pass on the current OS.

## What to preserve, how the seams interact, and what is still open

**Modules worth keeping as they are**

- `EditorCore` with `EditorGeometry` and `EditorHistory`. A large reducer behind one `reduce` call, tested by scripted and random sequences that check undo depth and placement invariants.
- `AnnotationRun`, `AnnotatorTransition` and `EventHold`. The same-turn answer problem is solved once and tested with seeded sequences.
- `AnnotatorZoom` over `Zoom`. One number drives frame and camera, and the tests prove the invariant across every level.
- `ScreenshotRequests` with `ReplyProtocol`. Acceptance before acknowledgement, publication as the only visibility point, paths derived rather than trusted, and tests that cover links, digests and clears.
- `AgentConnection`. Two real adapters, injected runners, and a submission outcome type that distinguishes queued from uncertain.
- `Drawings` over `DrawingStore` and the `OpenDrawing` seam, where a fake editor is a real second adapter.
- `MarkRendering` as the one renderer, and `MarkLayers` as its on-screen twin, verified by window captures.
- `Thumbnailer`, `StackLayout`, `Commands`, `Settings.bootstrap`, `AgentPlugin.stage` with `PluginHost`, and `CardNotices`. Each is a small interface over real behavior with tests at that interface.

**How the seams interact**

- One main-thread choreography runs from the watcher's report through the controller, the annotator, the drawings and the requests. The three reducers decide, and everything else runs effects in order, as ADR 0003 intends.
- One screenshot carries five identities: a card UUID, a URL, a path string, a bare file name and a request id. The controller translates among them, and `Commands.inWatchFolder` exists because path spelling once split one file into two drawings. Opportunity 1 removes the name-keyed and id-keyed maps from the wiring.
- Timing is guarded by seven hand-rolled generation counters and 29 delayed dispatches, 13 of them in the stack controller. That idiom works, and the reducers keep it out of the decisions. It is the reason the handover is verified by e2e rather than by unit tests.
- Six process-wide singletons exist: settings, the rendering queue, the thumbnail cache, focus return, agent logos and the recent-bitmap table. The tests tolerate them because each is pure or has a budget knob.
- A listing with a side effect: `ClaudeCodeConnection.liveInboxes` at `Sources/AgentConnection.swift:336-345` deletes inboxes whose process is gone. A reused pid keeps a stale inbox listed for the alive window only, which is acceptable, but the delete belongs with the plugin's own cleanup rather than a query.

**Dependency order for planning**

- Opportunity 6 is independent and can go first.
- Opportunity 2 should land before the annotator redesign's session tabs, which would multiply targets through today's four owners.
- Opportunity 1 should land before the planned agent-features-off switch, which otherwise has to reach into AppDelegate at three listing call sites, the toolbar and setup.
- Opportunity 4 stands alone. Opportunity 3 waits for the next handover change. Opportunity 5 is opportunistic.

**Unresolved decisions the plan depends on**

- Where mark scale lives for small captures. Computing it at draw time keeps the drawing format untouched, which ADR 0011 favors since old drawings need no migration.
- Whether a request record should carry a path. The comment says no on purpose, and opportunity 1 respects that by keeping the URL in memory for the launch.
- Whether a folder change should dismiss an open stack.
- The agent-features-off switch's home, and whether `add` keeps working with it on.
- The stitch layout proposal and the orientation flag that `Stitch` ignores, both already recorded in `docs/TODOS.md`.

**Missing evidence and limits**

- I ran nothing. Test and e2e results are the documents' reports from 2026-09-29 and 2026-09-30, not my own.
- Every performance figure above the code is the project's own measurement. I could not check the watcher's full decode per new file, the first destination listing's wait on the login shell of up to eight seconds, or the trailer's current behavior.
- I did not read the last 300 lines of `EditorCoreTests`, the Metal shader, or the resources folder. The Codex app's log format that `AgentApp.shownThread` reads is acknowledged in the source as a line rather than an interface, and I have no way to confirm it still holds.
