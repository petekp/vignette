# Architecture review, 2026-10-17

This review covers main at `766659b`. It builds on
[the system design synthesis](system-design-synthesis-2026-10-02.md) and
[the system improvement plan](system-design-work-2026-10-02.md), whose contract repairs are
implemented.

## Conclusion

Vignette's decisions are well placed. Its identities are not. Keep these as they are:

- the pure reducers (ADR 0003)
- the single mark renderer (ADR 0010)
- the durable request store

The weaknesses are four things the app works with but never gives an identity of its own:

- **A screenshot.** It is a path string.
- **An annotator opening.** It is a counter inside AnnotationController.
- **Who holds the keys.** That is spread over five flags in three objects.
- **A test launch.** It is one environment check written out in four places.

Because none of the four has its own identity, each consumer has to work out whether it still has
the same thing. Each place that does so has needed its own fix, its own guard and its own AGENTS.md
paragraph.

The fix is to mint each identity where the thing begins and to carry it through the effects and
callbacks that follow. Then a reducer can drop whatever is no longer current. Three of these changes
are foundations:

1. **An opening id**, minted by AnnotationRun.
2. **A typed screenshot key**, with rename matching.
3. **One small value for key ownership.**

The test-launch definition and the write results are local fixes.

The review rejected these larger rewrites on evidence:

- a screenshot library or ID store
- image leases
- a screen-level reducer
- a socket channel for agents
- an agent traits registry
- a Foundation-only core target
- an own motion clock
- rewriting settings as sparse overrides
- a shared Export module
- a shared write-outcome type with a quit coordinator

## Method

Ten finders each started from one shared premise rather than from one module. One finder read
AGENTS.md's rules as invariants the code does not enforce. Another used git churn.

Their 31 premises were merged into 12 weaknesses. Each weakness then got two skeptics:

- **Evidence.** One checked every citation at HEAD.
- **Tradeoff.** The other argued from the ADRs that the current shape is deliberate.

A completeness critic added output assembly, durable writes, keyboard ownership and the
launch-isolation details. Each of those got the same two skeptics.

Every weakness came back "holds with corrections" or "weak". This note reports only the narrowed
versions, with citations that survived or were re-checked by hand. Nothing was built for the review.

## What to keep

- **The pure reducers.** AnnotationRun, AnnotatorTransition, AnnotatorZoom, EditorCore,
  CardNotices and SettingsSync run behind EventHold and have random-sequence tests. All nine reducer
  files import only Foundation or CoreGraphics.
- **One renderer and one MarkLayers class.** The editor, the cards and the flights share them, and
  they share text through IOSurface. This code has been quiet since `72695f0`.
- **The rendering exports.** Copy Drawing, Done, drag and Send all go through
  `RenderingQueue.render`. RenderingQueue and PendingRendering own the pixel read, orientation and
  the result's identity (ADR 0018).
- **Main-actor isolation.** It is already typed. Strict concurrency is complete, and 57 types are
  `@MainActor`.
- **The agent surfaces.** ADRs 0004, 0005, 0007 and 0015 chose them. Codex's surfaces are forced,
  because its engine is private and it has no focus API.
- **The window count and press routing by pixels.** ADR 0012 holds, and the toolbar has to sit
  above the flight layer.
- **Watching macOS's folder.** ADR 0001 holds.

These suspected weaknesses were refuted:

- **Settings.shared as the cause of isolation failures.** Tests redirect it.
- **AppDelegate's callback wiring as the ownership problem.** Those closures are one-line forwards.
- **AGENTS.md drifting from the code.** Spot checks of five hard rules held at HEAD.
- **The handover having no model.** AnnotationRun and AnnotatorTransition model the logical
  timeline. Only the physical handover lacks a model.

## The weaknesses

### 1. A file path is a screenshot's identity

`Screenshot` is only a URL (`Sources/Settings.swift:6-8`), and a Card's `shot` is a `let`
(`Sources/ThumbnailController.swift:4-8`). The app keeps its facts about one picture in stores keyed
in different ways:

- The drawing is named by a hash of the path (`Sources/DrawingStore.swift:30-32`).
- The run, the transition and the notices key on the path string.
- The request record keeps only the basename (`Sources/ScreenshotRequests.swift:255`).
- The capture origin is looked up by basename.
- Agent and session provenance are xattrs on the person's file.

This costs the following:

- **A rename deletes the drawing.** The watcher sees a removal plus an arrival. The removal reaches
  `Drawings.remove` through `FolderWrites.left` (`Sources/FolderWrites.swift:180-217`,
  `Sources/Drawings.swift:103-110`).
- **Every entry point has to re-spell paths.** Without `Commands.inWatchFolder`, `/tmp/x.png` and
  `/private/tmp/x.png` would make two drawings (`Sources/Commands.swift:115-148`).
- **Case aliases are tolerated rather than resolved.**
- **A failed-reply notice rebuilds the source path.** It joins the current folder to the stored
  basename (`Sources/AppDelegate.swift:1103-1108`).
- **Agents need a standing U+202F warning** about how macOS spells capture names.
- **A change here is wide.** Sources has 87 uses of `url.path`.

An app-issued ScreenshotID library does not fit, for four reasons:

- macOS has no durable file identity. `st_dev` changes across reboots, and file resource
  identifiers do not persist across restarts.
- The folder may be in Dropbox, which replaces files when it syncs.
- An ID xattr would change the screenshot, which ADR 0011 forbids.
- Agent pushes reuse basenames.

What fits has four parts:

- **A typed `ScreenshotKey`** holding the folder's canonical spelling. It absorbs `inWatchFolder`
  and `realPath`.
- **Rename matching inside one listing.** The same inode, mtime and size at a new name becomes
  `renamed(from,to)`, which re-keys the drawing and the card.
- **The full source URL** in the request record.
- **Re-keying the open editor's drawing** on a rename, instead of dropping it.

### 2. Name differences carry irreversible meaning

The watcher reports only that a name appeared or disappeared.

- A new name is treated as a capture, unless a name pattern or a pending table keyed by name exempts
  it.
- A missing name is treated as a deletion.

Vignette's own outputs land in the folder and are recognised again from the listing.

The cost is a set of clocks whose job is to prove that an absence is real: `observedAt`,
`changedAt`, `revisions`, `writtenAt`, `deferredRemovals`, `missingSince` and `publishedAt`. Behind
`add` there is also a handshake keyed by name.

Two constraints limit the fix:

- Captures cannot be claimed before they land, because macOS writes them (ADR 0001).
- Keeping drawings after a deletion is unsafe until weakness 1 is fixed, because a push with a
  reused basename would inherit old marks.

macOS records each capture's rect and kind in the file's metadata. It sets them before the file
takes its final name, so they are there when the watcher sees it. It also stops writing them for
weeks at a time ([the capture-origin spike](capture-origin-spike-2026-10-03.md) has the
measurements). `CaptureOrigin` reads it first, with the poll as the fallback. A missing value cannot
mark a file as not a capture, so arrival classification stays on today's rules.

### 3. An opening has no identity that the reducer mints

An annotator opening is a different thing in each layer:

- a path in the reducers
- a card UUID in the flight layer
- `openGeneration`, exposed as `session`, in AnnotationController

Every asynchronous continuation works out whether it is still current with its own token. Sources
has 17 `generation += 1` sites in 7 files.

The same bug class happened twice. Send's render answer (`1f8929d`) and the two discovery
continuations were each guarded by path equality, and each was fixed with a guard written at that
site. No test reaches those guards, because `Tests/` never constructs the three controllers.

`.shown` carries no key either. In `flyingOut(k)` after `annotate(k2)`, the reducer would take a
late `shown` for k as k2's (`Sources/AnnotatorTransition.swift:67-80`). Today the only sender
prevents that from outside the reducer:

- `covered` checks `run.phase == .flyingOut(key)` (`ThumbnailController.swift:883`).
- TransitionLayer checks the flight's generation (`TransitionLayer.swift:233`).

So the rule lives where no sequence test can reach it.

The fix is for AnnotationRun to mint an opening id when it emits `prepare`. Every effect and
callback carries it: `shown`, `parked`, `loaded`, `takesPresses`, `landed`, `rendered` and
`copyFailed`. One reducer rule drops stale ids. That id becomes the value behind `session`, and
`openGeneration` goes away.

An actor and AsyncStream rewrite does not fit. A hop that has to land on an exact frame must stay an
explicit main-queue dispatch, because nothing proves that a `Task { @MainActor }` lands in the same
commit.

### 4. The lift into the editor is a three-way AND across two classes

The lift waits on three values:

- `ThumbnailController.loadedKeys`
- `ThumbnailController.takingEvents`
- `TransitionLayer.arrivedFlights`

(`Sources/ThumbnailController.swift:512-516`, `TransitionLayer.swift:92-93`.)
`perform(.prepare)` resets them by hand (`ThumbnailController.swift:848-849`), and AnnotatorZoom.Phase
keeps a second latch for flying and landed.

Every handover defect so far was a window-server timing fact found by a 60 Hz recording, and a
reducer would not have caught any of them. The probe, the refresh counting and the spring prediction
stay as inputs whatever the design.

So the fix is not a new Presentation reducer. `loaded`, `takesPresses` and `arrived` become run
inputs keyed by the opening id, with a `liftFlight` effect. TransitionLayer still animates and
reports `arrived`, and it no longer decides the lift.

### 5. Key ownership is five flags in three objects

The flags are:

- `AnnotationController.editorUntouched` (`AnnotationController.swift:57`)
- the toolbar Model's `keyed`, `tookKeysOnOpen`, `focus` and `toolLetter`
  (`AnnotatorToolbar.swift:57-61`)
- the editor's `heldKeys` and `core.holdsKey` (`EditorView.swift:102, 252`)

The held-tool-letter rule is written twice, once as `EditorCore.startsNote`
(`EditorCore.swift:1399-1413`) and once as `HeldToolLetter` (`AnnotatorToolbar.swift:524-556`). The
rule that a press on the image gives the editor the keys is a 3-line patch from `f0a41ee`
(`AnnotationController.swift:90-92`). Before that patch, Return sent text that a tool key had typed
into the message.

`ef23e7f`, `f0a41ee` and `520b113` all follow from one decision: the message field takes the keys on
open. AppKit picks the key window, so any model can only mirror it, and the two windows are forced.

The fix has two parts:

- One small tested value for who takes the keys at open and what a press on the image, the field or
  a control does.
- One held-letter rule, shared by the core and the bar.

`makeKey`, `sendEvent` and `canBecomeKey` stay as AppKit adapters.

### 6. The test-launch check is written four times, and two effects are ungated

The check "VIGNETTE_SETTINGS is set" is written out in four places:

- `Settings.swift:434`
- `Settings.swift:915`
- `AgentTools.swift:42`
- `AgentPlugin.swift:142`

`AppLocation.swift:154` only forwards the variable.

Two effects that reach the person's Mac are not gated:

- **The Updater** starts with automatic checks on in every launch (`AppDelegate.swift:85`).
  `docs/e2e-suite-plan-2026-09-29.md:50-51` lists this.
- **The login item's unregister** runs in a test launch (`LoginItem.swift:43-48`). It can only
  remove the real registration from a hand-launched copy that shares the real bundle id and has
  `launchAtLogin` off in its scratch file.

Inverting the default so that a non-release launch reaches nothing does not work. `run.sh`, a
login-item launch and a Sparkle relaunch all carry no environment, and they are the real app. The
environment parameters exist so that tests can inject them.

The fix is one shared definition of a test launch, read by those call sites, plus gates on the
Updater and on the login-item unregister.

Separate bundle ids for non-release builds are a separate decision. They change `project.yml`, they
cost one Accessibility grant per id, and they would not have prevented most past incidents.

### 7. Smaller gaps with local fixes

- **Stitch ignores orientation.** `Stitch.decode` and `Stitch.pixelSize` read the raw header
  (`Stitch.swift:125-140`). It is parked in `TODOS.md`. Only an image pushed through `add` can carry
  the flag.
- **A failed stitch or drag shows nothing on a card.** The failure appears only in the log
  (`AppDelegate.swift:404-413, 581`).
- **The editor's drawing handover drops the write result** (`AppDelegate.swift:111`). The store logs
  the failure (`DrawingStore.swift:143`), and the pending-drawing plan covers the outcome.
- **SettingsSync counts a write as saved before it is attempted** (`SettingsSync.swift:89-100`). The
  fix is a write-result event into the reducer.
- **The log is the only answer channel.** e2e runs and agents match `[cmd] ok|error`, and only
  `state` echoes a tag (`Commands.swift:171-177`). Every answer should echo `tag=`. A socket does not
  fit, because Codex's sandbox refuses writes to `~/Library` (`docs/reply-command-2026-09-26.md:118-119`).
- **Per-Mac state lives in `settings.json`**, the file meant to sync through dotfiles. That covers
  `setup`, `agentSkill` and `appleOriginal`. ADR 0014's differences-only file stays.

### 8. AGENTS.md is 18.6k words

It is about 28k tokens loaded into every session. By rough count it is:

- 7.3k words of design record
- 6.4k words of invariants
- 3.1k words of dev-environment hazards
- 1.6k words of macOS facts

The rules hold at HEAD, so this is a cost in context, not in correctness. Each foundation deletes
the rule paragraphs it replaces, so trim last:

- the three-moment lift
- the session compares
- re-spelling by folder
- the field's Return and Esc rules

## The October open items

- **Image retention follows foundation 1.** The opening id pins its screen decode, and the flight
  home uses the editor's own decode. That replaces the `flightImages` fallback
  (`ThumbnailController.swift:149, 186`). Request coalescing goes in `Thumbnailer.load`.
- **Rename preservation is foundation 2.**
- **Pending drawings keep their own plan.** The opening id gives the departure step an owner, and
  the rename case needs foundation 2.
- **Settings persistence becomes two changes:** the SettingsSync write-result event, and moving the
  per-Mac state out of `settings.json`.
- **The mark presentation interface stays separate.** It comes after pending drawings, as its plan
  says.
- **Claude inbox timing stands alone.** The session id goes in each `.line` and is compared when the
  monitor reads the inbox. A fixture test runs the real `inbox.sh`. The observation probe still
  gates it.

## Order

### Step 0

- Write the test-launch definition once, and gate the Updater and the login-item unregister.

### Step 1: the foundations, in order

1. **The opening id, minted by AnnotationRun, plus the lift inputs** (weaknesses 3 and 4). Verify
   with:
   - random sequences that include stale ids
   - the `annotate_open` and `annotate_queue` scenarios
   - a 60 Hz before-and-after recording of open and close
2. **`ScreenshotKey` and rename matching inside one listing** (weakness 1). Verify with:
   - watcher diff cases for a rename, a case-only rename and a same-name replacement
   - a native rename check
3. **The key-ownership value** (weakness 5). Verify with:
   - the `f0a41ee` sequence as a unit test: the field takes the keys, a press lands on the image,
     a tool key follows, then Return, and nothing is sent
   - the `send_message` and `send_target` scenarios with `--input`

### Step 2: what becomes small

- **Image request coalescing**, pinned by the opening id. Measure with `[state] memory`, and record
  the lone thumbnail's flight home at 60 Hz.
- **Keeping a drawing through Finder's Delete and Put Back.** This needs foundation 2 plus a pixel
  fingerprint.
- **The local gaps** in weakness 7.
- **The AGENTS.md trim.**

Run e2e in the Tart VM.
