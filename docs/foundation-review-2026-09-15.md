# Shotnote foundation review, 2026-09-15

Status: review complete. No code was changed. The plan waits for Pete's go-ahead, one step at a time.
Plan version 2, 2026-09-15: a second pass looked for what the first plan would force us to redo. Its gaps are listed after the findings as G1 to G16, and the plan was rebuilt around them. Step numbers changed; the appendix headings carry the new ones.
Plan version 3, 2026-09-15: an adversarial third pass attacked the plan's load-bearing decisions, order, and verifications against the code and the running app. Its corrections are listed after the gaps as R1 to R19, and the plan was rebuilt again. Step numbers changed; the appendix headings carry the new ones.

Scope: read-only review of AGENTS.md, README.md, project.yml, scripts/, Sources/, web/src/, and the six-commit history, then verification against the running app (same process throughout, PID 95957). Driven with `open -g shotnote://…` URLs, `~/Library/Logs/Shotnote.log`, `shotnote://state`, and screenshots cropped with sips. Four test screenshots were created in the watch folder; three were trashed through the app's own trash action, one was deleted with `rm`. `git status` stayed clean. One ad-hoc-signed build was made into the session scratchpad.

Machine facts that matter to the findings: macOS 15.7.3, Xcode 26.3, xcodegen 2.46.0, tldraw 5.4.2. Two displays: the built-in Retina display is `NSScreen.screens[0]`, the Studio Display sits above it. No python3 on this Mac has pyobjc. Accessibility is granted to `com.petepetrash.shotnote`.

## Findings, most severe first

### 1. A settings file that fails to parse is wiped on the next launch
- Finding: `Settings.read()` returns nil for both "missing" and "invalid", and `init` writes fresh system defaults on nil.
- Evidence: Settings.swift:107-116 and 153-163. Read only; not run because it would destroy the tuned file.
- Consequence: one trailing comma or a string where a number belongs, then a relaunch, loses every `ui` value and the hotkey. The log says "created", not "replaced".
- Fix: distinguish missing from invalid in `read()`. On invalid, keep defaults in memory, rename the bad file to `settings.json.invalid`, log loudly, toast once. Settings.swift only.

### 2. A negative `recentCount` crashes the app at launch, every launch
- Finding: `recentScreenshots` calls `prefix(limit)` with the raw setting, and launch calls it through `warmThumbnails`.
- Evidence: ScreenshotWatcher.swift:73, AppDelegate.swift:297-303. Ran a compiled `[1,2,3].prefix(-1)`: trap, exit 133.
- Consequence: `"recentCount": -1` in the file means a crash loop until someone hand-edits it. Nothing is logged. Other numbers are equally unchecked: `backdropWidth: 0` makes NaN gradient stops in BackdropPanel.swift:93-116.
- Fix: a `validated()` pass in Settings that clamps and logs each correction, plus `max(0, limit)` at the call. Settings.swift, ScreenshotWatcher.swift.

### 3. Two annotate requests in quick succession leave the annotator open on an empty canvas
- Finding: `hide(then:)` completes immediately when `current` is nil, but `current` is set nil at the start of a park that is still running. The earlier park's completion then resets the page after the new image was loaded.
- Evidence: AnnotationController.swift:75-85, ThumbnailController.swift:260-282. Ran: stack open, annotate test-1, inject a rectangle by `eval`, then two `open -g shotnote://annotate` 24 ms apart (log 11:52:27.277 and .301). State: `current=test-review-3 windowVisible=true`, page `images:0`. Screenshot crop showed a blank editor with only the tldraw badge. Script in the appendix.
- Consequence: the user or agent sees a dark empty annotator. Done exports nothing. App.tsx:41-47 also reads `currentKey` after an await, so a preview can be posted under the wrong key.
- Fix: serialize parks. Keep the in-flight park's completion in AnnotationController and chain a second `hide` onto it. In `park`, capture the key before awaiting. Behavior change in AnnotationController.swift and App.tsx.

### 4. A new screenshot silently closes an annotator opened from a fresh thumbnail
- Finding: `present(cards:stack:)` tears down any annotation session without going through `close()`.
- Evidence: ThumbnailController.swift:556. Ran: annotate test-1 with the stack closed, then `screencapture` a new file. State: `annotating=nil`, annotator `windowVisible=false`, thumbnail shows only the new file. No `[annotate] cancelled`, no `[focus]` line. Script in the appendix.
- Consequence: taking a second screenshot mid-drawing makes the editor vanish. The draft is parked but nothing says so. Focus is not returned to the previous app; that part is inferred from the missing `[focus]` line, not observed.
- Fix: when a shot arrives while annotating from a lone thumbnail, present the panel with the new card and keep `annotating`. At minimum, route through `close()` and log `[annotate] interrupted`. Behavior change in ThumbnailController.swift.

### 5. One failed export bricks Copy Annotated for the rest of the session
- Finding: the page's export catch logs but never posts `exported`, and Swift refuses new exports while `exportCompletion` is set.
- Evidence: App.tsx:89-94, AnnotationController.swift:148-152 and 243-246. Read only; not run because it would brick the running session.
- Consequence: after any export error, every Copy Annotated copies the originals and toasts success.
- Fix: post `exported` with empty items in the catch. Add a Swift timeout that clears the completion and logs an error. Both files.

### 6. The stack shows ghosts for deleted files, and annotating one opens an empty editor
- Finding: the watcher only reports additions. `sendImage` logs the read failure but `prepare`, the flight, and `show` continue.
- Evidence: ScreenshotWatcher.swift:30-33, AnnotationController.swift:126-129. Ran: `rm` test-4 while it was in the stack, then annotate it. Log `[annotate] could not read image`, then state `windowVisible=true`, page `images:0`. Crop was blank. Script in the appendix.
- Consequence: Finder deletions and Dropbox moves leave dead cards. Copy on a dead card toasts "Copied to clipboard" with a dangling file URL (Clipboard.swift:20-27, read only).
- Fix: have the watcher report removals and call `thumbnail.remove`. Check readability before starting the annotate transition and abort with a toast and an error line. ScreenshotWatcher, AppDelegate, ThumbnailController.

### 7. Nobody else can build the project
- Finding: project.yml hardcodes the Developer ID identity and the team.
- Evidence: project.yml:24-27. Ran: `xcodebuild … CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` against the generated project into the scratchpad. Built in 10 s, `Signature=adhoc`.
- Consequence: a clone fails at signing. A fork also shares the bundle id, the `shotnote` URL scheme, the status item autosave name, and the settings directory, so it collides with the original on the same Mac.
- Fix: project.yml defaults to ad-hoc with no team. build.sh reads an optional gitignored `scripts/signing.env` and passes the identity and team as xcodebuild arguments, so this machine keeps Developer ID. README explains why. Also: Info.plist is generated by xcodegen from project.yml. Verified by deleting it on a throwaway clone and regenerating; byte-identical. Either stop committing it or say not to edit it.

### 8. A dead web content process, or a missing web bundle, is not handled
- Finding: no `webViewWebContentProcessDidTerminate`, and `webView` is an implicitly unwrapped optional that stays nil when `preload` bails.
- Evidence: AnnotationController.swift:17, 36-41, 112, 264-274. Read only. Frequency of WebKit process termination is a guess.
- Consequence: after a crash, `pageReady` stays true, every call is a silent no-op, and all drafts are gone without a word. For a fork whose `pnpm build` failed, the first annotate crashes at `makeWindow`.
- Fix: implement the terminate delegate: reload, reset `pageReady`, log, toast. Guard `webView` with a real optional. AnnotationController.swift.

### 9. The stack and annotator always appear on the built-in display
- Finding: every placement uses `NSScreen.main`, which is the primary display whenever Shotnote has no key window.
- Evidence: ThumbnailController.swift:93. Ran: the frontmost window sat on the Studio Display (position y = -1415 in System Events coordinates). The backdrop frame in every state dump is `(1222, 0, 290, 982)`, the built-in display.
- Consequence: anyone working on an external display gets the thumbnail, stack, and annotator on the laptop screen.
- Fix: pick the screen under the mouse when presenting and keep it for that presentation. One property in ThumbnailController plus `presentEmpty`. Behavior change.

### 10. Paths with a literal `%` are corrupted by a double decode, and the comment justifying it is wrong
- Finding: query items are decoded once by URLComponents and again by `removingPercentEncoding`.
- Evidence: AppDelegate.swift:165-170. Ran: `open -g "shotnote://annotate?file=/tmp/nonexistent%25100.png"`. The `[url]` line shows `%25100` unchanged, so `open` did not re-encode. The `[annotate]` line shows `nonexistent0.png` with byte 0x10 in the name.
- Consequence: a file named `100%.png` cannot be targeted. Agents that encode correctly get silent misses.
- Fix: delete the second decode and the comment. AppDelegate.swift.

### 11. `shotnote://state` is not machine-readable, is incomplete, and has no end marker
- Finding: the dump is seven lines in Swift array and NSRect formats. The page line arrives later from an async callback. Drafts, previews, `NSApp.isActive`, Accessibility trust, and the server port are absent. Nothing logs park, draft, or drafts messages.
- Evidence: AppDelegate.swift:197-204, ThumbnailController.swift:105-107, AnnotationController.swift:250-260. Ran: the 11:52 session parked a real draft and the log shows no draft line at all.
- Consequence: an agent cannot parse the state reliably, cannot know when the dump is complete, and cannot observe drafts.
- Fix: one `[state] {json}` line assembled after the page replies, with an optional `?tag=` echoed back. Log `[draft] parked <key>` and `[drafts] <n>`. Three files.

### 12. There is no help, no result line, and several silent failures
- Finding: commands do not report outcomes uniformly.
- Evidence: empty copy returns silently (AppDelegate.swift:81); stitch under two files returns silently (:100); empty stack is silent (ThumbnailController.swift:127); the watcher's `open()` failure is silent (ScreenshotWatcher.swift:22) after `[watcher] watching` was already logged (AppDelegate.swift:292). Read only.
- Consequence: an agent cannot distinguish "ran and did nothing" from "not delivered".
- Fix: `shotnote://help` generated from `Config.actions` plus the fixed command table. Every command ends with one `[<cmd>] ok …` or `[<cmd>] error …` line. Log the watcher failure.

### 13. Plain `open` activates Shotnote; `open -g` does not; the docs never say
- Evidence: Ran `open shotnote://recent` then `dismiss`: `[focus] stack dismissed: returned to Ghostty`. Same with `open -g`: no focus line, frontmost app unchanged.
- Consequence: agent-driven runs differ from hotkey runs in key focus and focus return, so agent verification is not representative.
- Fix: AGENTS.md and README use `open -g` everywhere. Docs only.

### 14. `scripts/input.py` cannot run on this Mac, and Python is the wrong language for it
- Finding: the only Python in the project needs pyobjc, which no Mac ships and which must track the Python minor version.
- Evidence: `import Quartz` fails in /usr/bin/python3 and /opt/homebrew/bin/python3 (3.14.7). AGENTS.md:28 assumes it works. Measured alternatives: `uv run --with pyobjc-framework-Quartz` works but takes 52 s on first run and needs uv installed; a 45-line Swift equivalent compiles with `swiftc` in 1.1 s to a 75 KB binary and runs in 0.4 s, and `swift scripts/input.swift` runs it uncompiled in the same 0.4 s.
- Consequence: the hotkey, sweep, and drag-out are untestable by an agent on a fresh clone, and a fork's agent has to hold a third language for 44 lines. Agents also translate key names to key codes by hand (right Shift is 60) because the script cannot read the app's hotkey strings.
- Fix: port the script to Swift as `scripts/input.swift`, compiled by build.sh together with `Sources/HotKey.swift` into `build/input`, so `input hotkey double-rshift` and `input hotkey cmd+shift+6` parse the same strings as settings.json through `HotKey.parse`. Keep the existing subcommands (key, move, click, drag, scroll, tap) so AGENTS.md stays valid, and add `pasteboard` to replace the JXA one-liner. Xcode is already required, so this adds no dependency. Unverified caveat: synthetic events only post from a process trusted for Accessibility, which today is inherited from the terminal (Ghostty is trusted); a Swift binary launched from the terminal behaves the same as the Python script did. Until the port lands, `uv run --with pyobjc-framework-Quartz python3 scripts/input.py …` is the working fallback.

### 15. "Which image is in the annotator" has three owners synced by callbacks
- Finding: `ThumbnailController.annotating`, `AnnotationController.current`, and the page's `currentKey`, plus `model.outCards` and `visible` versus `panel.isVisible`.
- Evidence: findings 3 and 4 are both disagreements between these owners. Callbacks wired at AppDelegate.swift:37-45.
- Consequence: every new interruption sequence needs reasoning across three files.
- Fix: one session value owned by a small `AnnotatorTransition` that both controllers read. Model transitions as a reducer over events: annotate, swap, parked, shown, cancel, done, newShot, dismiss, remove. Structure only, moderate size.

### 16. What to split and what to keep together
- ThumbnailController: move out transition choreography (annotate, swap, returnCard, dismiss with annotator, lines 254-320) and the image caches (`previews`, `flightImages`, lines 74-79 and 360-381). Keep selection, keyboard, and scrolling together; they share the model and layout and are 200 lines that read well.
- AppDelegate: move URL parsing and the state dump into a `Commands` type that `help`, `state`, and tests can share. Keep the Actions implementation there; it is small.
- AnnotationController: fine as is once parks are serialized.
- Also pass `UITweaks` into `StackLayout` functions instead of reading `Settings.shared` (StackLayout.swift:6), which makes the layout math testable.

### 17. The bridge has no version and inbound calls are string literals in seven places
- Evidence: Bridge.swift:3, AnnotationController.swift:33-35, 79, 82, 137, 151, 155. Unrecognized messages log the whole body (AnnotationController.swift:216-219), which for a bad `done` is megabytes of base64.
- Consequence: a stale `web/dist` against new Swift is a silent no-op. Renaming a page method breaks at runtime only.
- Fix: `ready` carries a protocol version that Swift checks and logs. A `PageAPI` enum renders the seven calls. Log unrecognized messages by type and keys only.

### 18. Drafts living only in page memory: judgment
- Acceptable for a prototype, wrong for the pitch. They die with the process and with the web content process (finding 8). They are unobservable from Swift and from an agent. Copy Annotated must mutate the live canvas to render them (App.tsx:272-285); whether `loadSnapshot` pollutes undo history is a guess. Each draft holds the base64 image string.
- Fix, smallest: expose draft keys in state and log parks now. Later: persist snapshots as JSON under `~/.config/shotnote/drafts/` with the image referenced by path, served by the loopback server instead of inlined.

### 19. Memory grows without bound in three caches
- Evidence: Thumbnailer.swift:10 never evicts. Done stores the full-resolution PNG as the card preview (AnnotationController.swift:232, ThumbnailController.swift:190) while park previews are capped at 1600 px (App.tsx:34). Flight images keep four screen-size decodes (ThumbnailController.swift:373-379). Not measured; sizes are estimates.
- Consequence: a long session with many screenshots grows to hundreds of MB.
- Fix: LRU cap on Thumbnailer, downscale the Done preview like park, drop flight images on dismiss.

### 20. A trashed file's draft can come back after `forget`
- Evidence: `remove` starts an async park, then `forgetDrafts` runs (AppDelegate.swift:118-119). The park's `saveDraft` runs after `forget` (App.tsx:41-50, 85-88). Read only.
- Consequence: a phantom key in drafts and a retained snapshot. A later file with the same name would restore a stale draft.
- Fix: forget after the hide completion, or make `park` skip forgotten keys.

### 21. The shipped UI defaults are not the tuned UI, and "nothing visual is hard-coded" is false
- Evidence: Settings.swift:36-87 versus ~/.config/shotnote/settings.json on this Mac: cardMaxHeight 150 vs 86, cardMinSide 56 vs 114, annotationMinWidth 480 vs 770, backdropBands 6 vs 3, backdropBlurRadius 40 vs 13, slideInDuration 0.4 vs 0.75, backdropTint 0.3 vs 0. Hard-coded numbers remain at StackView.swift:23-25, 133, 180, 193, 205-215, 227, 263-264, 283, 295, 301; AnnotatorToolbar.swift:22, 61-77, 85-97; TransitionLayer.swift:102; Stitch.swift:5-6, 39, 44.
- Consequence: a fork gets an untuned UI and a doc that misleads it about where to look.
- Fix: promote the tuned numbers to defaults before publishing. Keep `ui` in settings.json but label it as design numbers with the reset button. Move the remaining constants into one `Theme` enum or into UITweaks, and correct AGENTS.md:9.

### 22. Adding a third geo tool breaks the toolbar highlight
- Evidence: App.tsx:220-224 maps any non-ellipse geo tool to rectangle.
- Fix: look up the tool by its `geo` value. One line.

### 23. Code quality, smaller items
- `applyTweaks` and `warm` decode synchronously on the main thread on every slider tick (ThumbnailController.swift:138-144, 205-213; AppDelegate.swift:52). `Thumbnailer.pointSize` reads the whole file through NSImage while its comment says header only (Thumbnailer.swift:14-18).
- Names: "thumbnail" means the controller, the fresh card, Apple's thumbnail, and the decoder. Ending an annotation is dismiss, cancel, close, hide, or annotationEnded depending on the file. `Actions.annotate` takes one shot while every other action takes a list (Config.swift:15-16, 55).
- Log lines have no date (Log.swift:7) and two lines have no tag (AnnotationController.swift:41, 143).
- Magic delays: 0.5 s in ThumbnailController.swift:163, 0.03/0.06/0.15 s around flights and key focus.

### 24. No tests. The first ones and how they run
- An xcodegen `ShotnoteTests` unit-test target, run with `xcodebuild test -scheme Shotnote -destination 'platform=macOS'`, added to build.sh behind a flag.
- Cover in order: `HotKey.parse`; `StackLayout` after finding 16; `Settings.read` and validation, including "invalid file is not rewritten" and "negative counts clamp"; `ScreenshotWatcher.isCandidate` and `recentScreenshots` on a temp folder; `WebMessage(body:)` for every type and malformed input; `Clipboard.pathsText`; then the transition reducer over the sequences in findings 3 and 4.
- Web: vitest for `activeTool` and the message union. Leave `render()` to manual verification.

### 25. Docs drift
- README.md:28 describes a two-call bridge that no longer exists. :36 says the app is unsigned; false since 1a5e375. :41 says "last five"; the default is 30. :96 shows `recentCount: 5`. README omits `dismiss`, `cancel`, `eval`, `-g`, the Accessibility requirement for double-tap, and that the icon can hide under the notch.
- AGENTS.md:71 names `ExpandPanel`, deleted in 306c7ad. AGENTS.md:46 says the badge reads "Made with tldraw"; the bundled tldraw 5.4.2 renders "Get a license for production". Whether that tier permits redistribution in an open-source app is a guess worth checking in tldraw's license before publishing.
- A fork author also needs: rename the bundle id and URL scheme, the signing override, that `web/dist` must exist before `xcodegen`, and that `run.sh` loses drafts.

## Gaps, second pass

Found by asking what the first plan would force us to redo. Same shape as the findings, shorter. Each names the plan step that absorbs it. Step numbers follow plan version 3.

### G1. Draft ownership is undecided, and three later steps depend on it
- Finding: finding 18 defers where drafts live, while the state, reducer, and bridge steps were all shaped around page-owned drafts.
- Evidence: App.tsx:28-33 module globals; AnnotationController.swift:148-161 export round trip. Findings 5, 8, and 20 all stem from this.
- Consequence: the bridge would be revised twice.
- Fix: Swift owns drafts as snapshot JSON files and the page is stateless. Step 15. Supersedes the fix in finding 20.

### G2. Images cross the bridge as base64 inside JS source
- Evidence: AnnotationController.swift:126-139. LocalServer.swift:33-41 reads one 64 KB chunk and assumes it holds the whole request.
- Consequence: three copies of every screenshot in memory and a slow load path. Changing it later is a second bridge revision.
- Fix: serve files from the loopback server with a per-launch token and a watch-folder allowlist; parse requests to the header terminator. Step 14.

### G3. Any local process, or a web page after one consent prompt, can trash any file
- Evidence: AppDelegate.swift:109-120 and 165-170 accept any `file=` path; `eval` at :180 runs arbitrary JS. Read only.
- Consequence: `shotnote://trash?file=~/Documents/x` works from a browser that remembers the consent.
- Fix: restrict `file=` to the watch folder; put `eval`, `show-editor`, and `tweaks` behind a `debug` setting. Step 5.

### G4. Identity is spread over five constants, and two instances can run at once
- Evidence: project.yml:3, 15-17, 24; AppDelegate.swift:242-245; Settings.swift:94-95; Log.swift:5. No launch guard.
- Consequence: a fork renames five things or collides with the original. A second instance registers a second hotkey and both write settings.
- Fix: derive everything from the bundle id and add a single-instance guard. Step 7.

### G5. Durations and delays are scattered, so agent runs depend on timing
- Evidence: ThumbnailController.swift:163 (0.5 s) and the 0.03, 0.06, and 0.15 s waits around flights and key focus; UITweaks durations; the hard-coded animations in finding 21.
- Consequence: every script needs sleeps, and Reduce Motion is ignored.
- Fix: one `Motion` scale that every duration and delay passes through. Step 13.

### G6. The watcher gives up silently on a file that keeps changing, and never rescans
- Evidence: ScreenshotWatcher.swift:44-51: twenty polls at 0.1 s, then return without reporting. Read only.
- Consequence: a large file synced in from another machine never appears. After sleep, or when the folder setting changes, nothing reconciles the stack with the disk.
- Fix: FSEvents with added and removed paths, rescan on wake and on folder change, and an error line for a file that never stabilized. Step 9.

### G7. Display and sleep changes are not observed
- Evidence: no observer for `NSApplication.didChangeScreenParametersNotification` or `NSWorkspace.didWakeNotification`. Read only; not run.
- Consequence: unplugging a display with the stack open leaves it off-screen (guess).
- Fix: one handler that relayouts and rescans. Step 10.

### G8. Nothing enforces the main-thread assumptions
- Evidence: finding 23; the Thumbnailer lock, the watcher queue, and no `@MainActor` anywhere.
- Fix: strict concurrency warnings in the existing Swift 5 mode, `@MainActor` on the controllers. Step 11.

### G9. Settings have no version or migration
- Evidence: Settings.swift:11-20 has no version; unknown keys are dropped on the next write (Settings.swift:174-182).
- Consequence: the first renamed key after publishing silently resets users.
- Fix: a `version` field and a `migrate` function with tests. Step 4.

### G10. There is no startup contract
- Evidence: `[web] ready` is the last launch line. Commands before it are partly queued (AnnotationController.swift:138) and partly dropped (:33-35). A first launch shows nothing but a menu bar icon.
- Fix: an `[app] ready` line, early commands answered with an error, a first-launch toast, a git build id. Step 6.

### G11. The reducer would have unit tests but no sequence tests
- Fix: randomized event sequences with invariants. Step 12.

### G12. The export workaround has no test, and tldraw is the one moving part
- Evidence: App.tsx:239-262 exists because tldraw's own export was blank in WebKit; package.json pins 5.4.2.
- Fix: a render test in a real WKWebView and an upgrade checklist. Step 19.

### G13. The log has no grammar
- Evidence: Log.swift:7 has no date; error descriptions and eval results can contain newlines; no rotation; result lines do not carry produced paths.
- Fix: define it once. Step 17.

### G14. Three coordinate conventions
- Evidence: state dumps use bottom-left points (ThumbnailController.swift:105-107), input.py uses top-left points, sips crops use top-left pixels at 2x.
- Fix: top-left points for state and the input tool, stated in AGENTS.md. Steps 17 and 3.

### G15. The tldraw license question blocks publishing
- Evidence: finding 25; the bundle renders "Get a license for production".
- Fix: read the license, record the conclusion. Step 1.

### G16. No build id
- Evidence: Info.plist carries 1.0 and 1; the launch line says `launched 1.0`.
- Fix: a git-derived version passed by build.sh. Step 6.

## Third pass: adversarial review

Same process (PID 95957), no relaunch, no test screenshots. Ran the URL decode check, three `state` or `eval` reads, curl probes of the loopback server, a strict-concurrency typecheck of Sources in three variants, and fetched tldraw's license and pricing pages. Three earlier claims were refuted or narrowed (R2, R4, R5) and one guess was confirmed (R3). Each item names what it changed in the plan.

### R1. The license question is different from the one finding 25 and G15 ask
- Evidence: LicenseManager.mjs:87-94 classifies any `http:` origin as a development environment; LicenseProvider.mjs:21-41 hides the editor 5 s after mount when the state is `unlicensed-production`, which is the "non-http origin" rule in AGENTS.md. Live eval: `state: "unlicensed", isDevelopment: true`, watermark text "Get a license for production". tldraw's LICENSE.md (main branch, fetched today): a Development Environment is "internal hosting or deployment ... for development, testing, or staging purposes ... not accessible to end users, customers, or the public"; conditions include "Not to use the Software in Production Environments", "Not to disable, change, or interfere with the Software's License Key enforcement", and "To include a verbatim copy of this License in any distribution". tldraw.dev/pricing lists a free Hobby license for personal use and a 100-day trial; the SDK has a native-app license flag matched by regex against the page URL (LicenseManager.mjs:21, 245-247). The repo has no license file and the bundle carries no copy of tldraw's. There is no unlicensed watermark tier.
- Effect: step 1 rewritten; its verification is the license state the page reports, not a written conclusion. Excalidraw (MIT, 0.18.1 on npm today) is the named fallback.

### R2. Finding 9's "always the built-in display" is false
- Evidence: today's state dumps show the panel at x=1268 (built-in) 35 times and at x=2571 (Studio Display) once, at 13:07, when a screenshot was taken and Copy clicked there. The mechanism, the active display under separate Spaces, is a guess; Apple's page did not render.
- Effect: step 10 keeps `NSScreen.main`, pins it per presentation, and tests the guess before switching rules.

### R3. Finding 18's guess is confirmed: `loadSnapshot` records into undo history
- Evidence: Store.mjs:457-472 and 772-806 run the load as `atomic(fn, false)` with remote merging off; HistoryManager.mjs:33-34 records every entry with source "user". Live: `getCanUndo()` false, then true after one `export([])` round trip on the empty canvas.
- Effect: step 15 clears history after any snapshot load.

### R4. Finding 23's "reads the whole file through NSImage" is refuted
- Evidence: over the 1253 PNGs in the watch folder, `NSImage(contentsOf:).size` took 678 ms and ImageIO properties took 209 ms. Header only, three times slower; the launch warm of 30 files costs about 16 ms.
- Effect: the claim is dropped; step 16 switches to ImageIO as a small win.

### R5. G2's single-read claim is not a failure, and the server's real gaps are elsewhere
- Evidence: a request split across two writes and a 70 KB header both got 200, because only the request line is parsed and it arrives in the first segment. `curl -H 'Host: evil.com'` got 200, the DNS-rebinding shape; POST got 200; raw and percent-encoded `..` got 404; the listener binds 127.0.0.1. The MIME table (LocalServer.swift:54-65) lacks jpg. `render` draws the image onto a canvas (App.tsx:255-261), so the image must be same-origin with the page or `toDataURL` throws.
- Effect: step 14 adds Host and method checks and MIME types, records the same-origin constraint, and demotes header-terminator parsing to hygiene.

### R6. G8's cost was unmeasured
- Evidence: `swiftc -typecheck -swift-version 5 -strict-concurrency=complete` over Sources: 286 diagnostics bare and 3 in minimal mode; 133 with `@MainActor` on the four types the plan named; 15 with every AppKit-facing type annotated and LocalServer left nonisolated (annotating it gives 2 errors at LocalServer.swift:21 and 24).
- Effect: step 11 scopes the annotations to every UI type and keeps Thumbnailer's lock.

### R7. G4: line numbers, a race, and the settings path
- Evidence: the URL types are at project.yml:22-23 and the bundle id at 27, not 15-17. scripts/run.sh:6-7 sends SIGTERM and opens the new build at once; a guard that quits the newer instance can leave nothing running. README:57 and 86 document `~/.config/shotnote/settings.json`.
- Effect: step 7 keeps the settings path literal, makes the newer instance win, and run.sh waits for the old pid.

### R8. Finding 14's trust caveat is verified
- Evidence: a Swift script run from this shell printed `AXIsProcessTrusted: true` in 0.3 s; the parent chain was zsh, claude, zsh, herdr server. Synthetic events will post from a compiled tool launched the same way.
- Effect: step 3 states it; the tool compiles on demand instead of inside build.sh.

### R9. G14: "top-left points" needs a display
- Evidence: the Studio Display sits above the built-in at y 982 to 2422 in AppKit coordinates and at negative y in Core Graphics coordinates.
- Effect: steps 3 and 17 use global Core Graphics coordinates and state names the screen.

### R10. Finding 13: `open -g` still activates Shotnote when the annotator opens
- Evidence: AnnotationController.swift:69; today's log shows `[focus] annotator closed: returned to Notion` after `open -g shotnote://cancel`.
- Effect: step 21 says so.

### R11. G10: most commands never need the page
- Evidence: `[app] launched` at 10:36:07.698 and `[web] ready` at 08.383; AnnotationController.swift:138 queues the load, only lines 33-35 drop.
- Effect: step 6 refuses only page commands and keeps the queue.

### R12. G6: removals are one set difference away, and the stack already rescans
- Evidence: ScreenshotWatcher.swift:30-33 discards `known - current`; 44-51 leaves a never-stable file in `known`; AppDelegate.swift:283 rescans the disk on every stack open, so ghosts live only inside one open stack. The folder is a plain directory with 1398 entries, no symlink, no conflicted copies. That Dropbox stages writes in `.dropbox.cache` and renames into place is a guess.
- Effect: step 9 keeps DispatchSource; FSEvents is deferred.

### R13. Step 15's kill test had no target
- Evidence: WebKit's Networking process owns the sockets and every request closes its connection, so `lsof -i TCP` finds nothing; today's web process is pid 95960 (51 MB RSS), found only by its start time. `launchctl procinfo` needs root.
- Effect: state carries the pid; the kill test uses it; the memory check counts both processes.

### R14. G1: a tokened `src` inside a persisted snapshot dies with the launch
- Evidence: App.tsx:155-165 stores the src in the asset record; `getSnapshot` (App.tsx:55) includes assets; tldraw 5.4.2 offers an asset store hook on the component (tldraw index.d.mts:4341) and `Editor.resolveAssetUrl` (Editor.mjs:3813). `~/.config` is a dotfiles directory, not a place for preview PNGs.
- Effect: step 15 stores a path-based src, resolves it at load, and moves drafts to Application Support with an orphan sweep.

### R15. Two verifications were unsafe
- Evidence: the settings check needs a bad settings file at the real path; every relaunch destroys drafts until they persist.
- Effect: step 4 adds a settings path override; the plan header says when relaunch checks are safe.

### R16. G5: the delays are ordering hacks, not motion
- Evidence: ThumbnailController.swift:152 (key retry), 577 and 609 (SwiftUI commit), 163 (card exists), 308, 332, 338, 346, 348 (flight end), all inside the code the reducer step rewrites; finding 4's lone-thumbnail branch (309-315, 556) is rewritten by the same step.
- Effect: the lone-annotation step is merged into the reducer step; the motion step scales durations only and runs after it.

### R17. Finding 21: the false claim is in the doc, not the constants
- Effect: step 18 promotes the tuned defaults and corrects AGENTS.md:9; no Theme enum and no new knobs.

### R18. G12: the render test needs the loopback origin
- Evidence: LicenseProvider.mjs:24 hides an unlicensed production origin after five seconds, so a `file://` test that finishes in four passes by luck.
- Effect: step 19 starts LocalServer.

### R19. G2's "slow load path" is unmeasured
- Evidence: no `shown` timestamp exists, so nothing in the log can time the base64 path.
- Effect: step 5 adds `[annotate] loaded <ms>`; step 14 must not regress it.

## Plan, version 3

Each step is independently verifiable. [B] changes behavior, [S] is structure only, [D] is a decision recorded in writing. Tick a step when its verification passed. The order is dependency order: a step may be pulled forward only if it does not touch code a later structural step rewrites. Steps 2 and 3 exist so the others can be verified; steps 4 to 10 are independent of each other. Every relaunch destroys drafts until step 15 lands, so run relaunch checks (steps 4, 6, 7) when no draft matters. Settings checks use the override from step 4, never the real file. Once step 17 lands, scripts wait on tagged state lines instead of sleeping.

### Phase A: decide, test, secure

- [x] 1. [D] tldraw license (G15; R1). Done 2026-09-15, the "Now" part; the key, its eval check, and any binary release wait for the public repo. The app's own license is MIT. Decided 2026-09-15: the free Hobby license. The editor runs today only because the SDK classifies `http://127.0.0.1` as a development environment, and the license reserves that for internal development. The application form wants a public presence, at least a GitHub link, so the key waits until the repo is public. Now: bundle tldraw's LICENSE.md in the app and the repo; add the app's own license file; App.tsx passes `import.meta.env.VITE_TLDRAW_LICENSE_KEY` as the `licenseKey` prop so the key drops in later without a code change; correct AGENTS.md:46 and the "http origin" rationale to say what the server is for. No binary release before the key lands; publishing the source is fine because the repo carries no tldraw code. When the key arrives: build with it and run the eval check. If the application is refused, switch the editor to Excalidraw (MIT) and reshape steps 14, 15, and 19 before any of them starts; until then they proceed on tldraw. Verify now: both license files are present in a fresh clone and in the built bundle, and a build with `VITE_TLDRAW_LICENSE_KEY=test` puts that string in `web/dist`. Verify later: `open -g 'shotnote://eval?return window.editor.licenseManager.state.get()'` logs `licensed` or `licensed-with-watermark`.
- [x] 2. [S] Test target (finding 24; R15). Done 2026-09-15. The bundle compiles `Sources/` minus `AppDelegate.swift` instead of using the app as a test host, so a test run never launches a second Shotnote against the real settings. An xcodegen `ShotnoteTests` unit-test target run by `xcodebuild test -scheme Shotnote -destination 'platform=macOS'`, wired into build.sh behind a flag, with one test: `HotKeySpec.parse`. Every later step adds its tests here: settings read, validation, and migration (4); command parsing, error codes, and `Clipboard.pathsText` (5); `ScreenshotWatcher` candidates, ordering, and the removal diff on a temp folder (9); `StackLayout` and the reducer sequences (12); `WebMessage` decoding for every type and malformed input (14). Verify: green, and build.sh runs it with the flag.
- [x] 3. [S] Input tool in Swift (finding 14; G14; R8, R9). Done 2026-09-15: `hotkey double-rshift`, `click` on a card frame, and `pasteboard` verified against the running app. The `hotkey cmd+shift+6` check needs the hotkey setting changed, so it runs with step 4's settings override. Move `parse` and the key tables into `HotKeySpec.swift`; `scripts/input.swift` compiles with it through `scripts/input.sh`, which rebuilds `build/input` when the binary is older than either source and is not part of build.sh. Subcommands key, move, click, drag, scroll, tap, `hotkey <spec>`, `pasteboard`. Coordinates are global top-left points as Core Graphics reports them, so the Studio Display above the built-in has negative y; state (step 17) prints the same. Delete the Python file. Synthetic events post because the tool inherits the terminal's Accessibility trust; verified from this shell. Verify: `scripts/input.sh hotkey double-rshift` opens the stack; `hotkey cmd+shift+6` does the same after switching the setting; `pasteboard` prints the item count after a copy; `click` on a card frame from state annotates it.
- [x] 4. [B] Settings hardening (findings 1, 2; G9; R15). Done 2026-09-15; the step 3 `hotkey cmd+shift+6` check passed under the override. Note: macOS 15's JSONSerialization accepts a trailing comma, so finding 1's example needs a real syntax error; an unterminated object was used. A reload that drops `appleOriginal` keeps the in-memory record, and a pre-version file is stamped once on reload. `SHOTNOTE_SETTINGS=<path>` in the environment overrides the file and is named on the launch line, so checks never touch the real file. Keep an invalid file and rename it to `settings.json.invalid`; clamp and log every bad value; add `version: 1` and a `migrate(from:)` function; flush pending writes on quit. Record the Apple screencapture values first run read under `appleOriginal`, and add `shotnote://restore-apple-defaults` plus a menu item, because the app changes Apple's defaults and nothing restores them today. Log a warning at launch when Apple's `type` is a format the watcher ignores. Verify: launched with the override pointing at a scratch copy that has `"recentCount": -1` and a syntax error, the real file's mtime is unchanged, the scratch file is intact beside its `.invalid` rename, one log line per correction; bump the version in a fixture and the migration runs; toggle the thumbnail setting, restore, and `defaults read com.apple.screencapture show-thumbnail` returns the original.
- [x] 5. [B] Command surface and policy (findings 10, 12; G3; R10, R19). Done 2026-09-15. Three codes were added to the vocabulary because commands needed them: `no-apple-original` (step 4's restore), `eval-failed`, `write-failed` (stitch save, trash). The `loaded` baseline: 549 to 567 ms over three runs for a 5120x2880 PNG of 1.8 MB, on a page->host `loaded` message posted two frames after the image shape exists. The Studio Display was not attached during this session, so the 5K file was a resampled capture. Parsing, policy, help, and `Clipboard.pathsText` are unit-tested; the watch-folder check resolves the longest existing prefix with `realpath`, because `resolvingSymlinksInPath` leaves a missing path alone. Single decode. `file=` restricted to the watch folder, compared after resolving symlinks on both sides, unless `debug` is on; `eval`, `show-editor`, and `tweaks` need `debug`. `shotnote://help` generated from `Config.actions` and the command table. Every command ends with one line, `[<cmd>] ok <detail>` or `[<cmd>] error <code> <detail>`, with produced paths in the ok line; codes are a fixed vocabulary (`unknown-command`, `missing-file`, `outside-watch-folder`, `not-enough-files`, `unreadable-image`, `page-not-ready`, `export-timeout`, `settings-invalid`, `debug-disabled`). Annotate refuses an unreadable file with `error unreadable-image` in the command layer, before any transition starts. `[annotate] loaded <ms>` when the page reports the image, so step 14 has a baseline. Log the watcher's open failure. Verify: the `%25` script resolves the path; `trash?file=/tmp/x.png` logs `error outside-watch-folder` and touches nothing; with `debug` on, `annotate?file=/tmp/x.png` proceeds; the deleted-file script logs `error unreadable-image` and no window opens; `help` lists every command and action.
- [x] 6. [B] Startup contract and build id (G10, G16; R11). Done 2026-09-15. Measured: `[app] ready` at +290 ms, a `copy` fired with the launch answered ok 210 ms before `[web] ready`, `eval` answered `page-not-ready` while loading. The page-ready rule is by page state: an unavailable page (no bundle, no server, failed load) refuses annotate too; a loading page refuses only copy-annotated and eval. build.sh stamps both its xcodebuild calls, because the test run rebuilds the app. `[app] ready pid=… build=… port=… watching=…` at the end of launch, and `[web] ready` stays its own line; only annotate, copy-annotated, and eval answer `error page-not-ready`, and annotate keeps its one-deep queue as today; a first-launch toast names the watched folder; build.sh passes a git-derived version into the bundle. Verify: launch and fire `copy` at once, it succeeds before `[web] ready`; fire `eval` at once, get the error line; the ready line shows the git hash.
- [x] 7. [B] One identity and a single-instance guard (finding 7's collision note; G4; R7). Done 2026-09-15. The log name derives from CFBundleName (so `~/Library/Logs/Shotnote.log` keeps its documented path) and the rest from the bundle id; `bundleIdPrefix` was removed because PRODUCT_BUNDLE_IDENTIFIER was already explicit, so the fork check renamed `name`, the target and scheme keys, the bundle id, and the URL scheme on a clone: it built as Shotnote2.app, logged to Shotnote2.log, seeded its status item under com.example.shotnote2, and ran beside the original. The status item's autosave name changed from `shotnote` to the bundle id, so its remembered position reset once. Log name, status item autosave name, Application Support directory, and the Carbon hotkey signature derive from the bundle id; `~/.config/shotnote/settings.json` stays literal because it is documented and lives in dotfiles; the URL scheme is read from Info.plist; project.yml is the one place to rename. A second launch of the same bundle id asks the older instance to terminate and continues; run.sh waits for the old pid to exit before opening the new build. Verify: change `bundleIdPrefix` on a clone, rebuild, and the log and autosave names follow while the settings path does not; launch twice, the older exits with a log line and the newer runs; run.sh three times in a row leaves exactly one instance.
- [x] 8. [S] Signing, runtime, and the generated Info.plist (finding 7; new). Done 2026-09-15. Verified: fresh clone without signing.env gives `Signature=adhoc`, `TeamIdentifier=not set`, no runtime flag (Xcode does not add it to ad-hoc signatures); with signing.env the designated requirement is byte-identical to the pre-step build, the runtime flag is set, and double-rshift still fires after the relaunch, so the Accessibility grant survived. The self-signed certificate claim was NOT verified: a certificate made with openssl in a temporary keychain imports but codesign refuses an untrusted identity, and trusting it changes the user's trust settings. The README says so; a person can verify it by creating the certificate in Keychain Access on a clone. Info.plist left git. project.yml defaults to ad-hoc with no team; build.sh reads a gitignored `scripts/signing.env` and passes identity and team as xcodebuild arguments; README tells fork authors that a self-signed code-signing certificate from Keychain Access keeps Accessibility trust across rebuilds without a paid identity (a guess by analogy with Developer ID; verify on a clone before writing it); `ENABLE_HARDENED_RUNTIME` on now so notarization is never a redesign; the sandbox stays off, recorded in AGENTS.md with the reasons (writes to Apple's screencapture domain, an arbitrary watch folder without bookmarks, global event monitors); Info.plist is removed from git or marked generated. Verify: a fresh clone builds ad-hoc; with `signing.env` present the signature is Developer ID; `codesign -dv` shows the runtime flag; hotkey, double tap, and annotator still work.
- [x] 9. [B] Watcher: removals, stability, rescan (finding 6; G6; R12). Done 2026-09-15. Stability is size unchanged across two polls plus a successful ImageIO decode, because `CGImageSourceGetStatus` reports complete for a truncated PNG (measured) while the decode returns nil; a `dd` in two halves 1.5 s apart was reported once complete. A removed file leaves the open stack; a heic shows a card. Wake rescans through `rescan(reason:)`; a folder change already makes a fresh watcher. Keep the DispatchSource watcher. Report removed names to `thumbnail.remove`; a file that never stabilizes leaves `known` with `[watcher] error never-stable <name>`, so the next directory event or stack open picks it up; rescan on wake and on folder change; accept the formats screencapture can write, at least png, jpg, and heic, through `isCandidate`. Verify: `rm` a file while the stack is open and its card disappears; a file copied in slowly with `dd` and a pause appears once complete, or logs the error and appears on the next event; a heic in the folder shows a card.
- [ ] 10. [B] Screen choice and display or wake changes (finding 9; G7; R2). Code landed 2026-09-15: the screen is pinned per presentation, state logs `screen="<name>" screenFrame=… pinned=…`, `didChangeScreenParameters` relayouts the panel and backdrop (the annotator window is left where it is until step 12 owns transitions), wake rescans (step 9). Automated check passed: panel (1268,70,246,876; the 2 pt overhang is the shadow inset), backdrop, and annotator frames lie within the logged built-in display. NOT ticked: the Studio Display click check and the sleep check need a person, and the Studio Display was not attached during this session. Keep `NSScreen.main` as the rule, since it followed the active display today; pin the screen for one presentation; log `screen=<name>` in state; relayout on `didChangeScreenParameters` and rescan on `didWake`. Verify: the panel, backdrop, and annotator frames lie within the logged screen; a person clicks on the Studio Display and then runs `open -g shotnote://recent`, and the panel's y is at or above 982 (if not, the active-display guess is wrong: switch the rule to the screen under the mouse); the sleep check also needs a person: after wake the stack opens and shows files added while asleep.

### Phase B: structure, in dependency order

- [x] 11. [S] Concurrency checking (G8; R6). Done 2026-09-15 by a subagent, diff reviewed: 189 diagnostics with the flag on and nothing annotated, 0 after; `nonisolated(unsafe)` only on Thumbnailer's cache; `MainActor.assumeIsolated` on the Carbon hotkey handler, main-run-loop Timers, and `queue: .main` observers; LocalServer lost its `self` captures instead of a Sendable conformance; 41 tests green, 14 of them marked `@MainActor`. Strict concurrency warnings on in the existing Swift 5 mode; `@MainActor` on every AppKit-facing type: AppDelegate, both controllers, Settings, the panels and windows, the toolbar, the transition layer, the debug and settings windows, FocusReturn, ModifierTap, HotKey, Tween. LocalServer, ScreenshotWatcher, and Log stay nonisolated; Thumbnailer keeps its lock as a documented `@unchecked Sendable` cache, because an actor would make its synchronous calls async and ripple through the controller. Measured today: 286 diagnostics bare, 133 with four types annotated, 15 with all UI types. Verify: zero concurrency warnings; no `nonisolated(unsafe)` outside Thumbnailer.
- [x] 12. [S] One session owner and the transition reducer (findings 3, 4, 15, 16; G11; R16). Done 2026-09-15. `AnnotatorTransition` has phases idle, flyingOut, annotating, parking(then:) rather than the eight named states: swapping, returning, and dismissing are `parking` with a `Next`, and thumbnail/stack live in `origin`; the invariants and both findings are tests (500 random seeds). The 0.03 s commits became next-run-loop hops, the 0.06 s flight lift waits for the page's `loaded`, the 0.15 s key retake and the 0.5 s slide-in wait are gone (a lone annotate flies from the offscreen slot). `Commands` was already extracted in step 5; dispatch stays in AppDelegate until step 17 reshapes state. Race script: `images:1`, annotator on the last request, parks serialized in the log; lone-annotation script: annotator open with the new card beside it; deleted-file script: refused. The race script's rectangle inject needs `debug` on and was skipped. Extract `Commands` from AppDelegate; pass `UITweaks` into `StackLayout`; extract `AnnotatorTransition`, a reducer over the events annotate, swap, parked, shown, cancel, done, newShot, dismiss, remove, and the states idle, thumbnail, stack, annotatingFromThumbnail, annotatingFromStack, swapping, returning, dismissing. The reducer serializes parks (finding 3), is the only writer of the session, makes a new screenshot during a lone annotation join the panel instead of closing the editor (finding 4, formerly its own step), and replaces the 0.03, 0.06, 0.15, and 0.5 s waits with completions. Tests: random event sequences with the invariants "a visible annotator has an image", "at most one park in flight", "annotating implies a placeholder slot", "dismiss ends with everything hidden"; findings 3 and 4 are two fixed seeds. Verify: the race script passes with `images:1`; the lone-annotation script leaves the annotator open with the new card visible; the deleted-file script behaves as after steps 5 and 9; tests green.
- [x] 13. [B] Motion (G5; R16). Done 2026-09-15. `ui.motion` scales the ten duration tweaks through `Settings.motionUI` (StackView's three hard-coded list animations follow the same scale); Reduce Motion is observed and forces 0, and the rule is unit-tested. With `motion: 0` on a scratch file: the whole column is in place 50 ms after `[stack] shown`, the panel is gone 120 ms after `[dismiss] ok`, and the race (with the rectangle injected this time), lone-annotation, and deleted-file scripts pass. The live Reduce Motion check needs a person to flip the system switch; not done. Every UITweaks duration honors Reduce Motion and a `ui.motion` multiplier from 0 to 1. No delay is scaled; step 12 removed them. Verify: with `ui.motion: 0` the stack appears and leaves without animation and the appendix scripts pass; with Reduce Motion on, the same.
- [x] 14. [S] Bridge version 2, transport (finding 17; G2; R5, R19). Done 2026-09-15. Verified: a page patched to `protocol:1` logs `[web] error protocol-mismatch page=1 app=2`, sets the toast, and `annotate` answers `error page-not-ready`; `curl` of a watch-folder file without the token 404, `Host: evil.com` and `Host: localhost` 400, POST 405; the 5K image is served same-origin and decodes at 5120x2880 in the page. `[annotate] loaded` for the 5K screenshot: 368 ms on the first load against the 549 to 567 ms base64 baseline, 90 ms once WebKit has the file cached. Two traps met on the way: the timing line is posted from a `requestAnimationFrame`, which WebKit pauses while the document is hidden, so it never arrives on a locked screen; and `NWListener` refuses to start without a connection handler, while the routes need the port, so the handler reads them through a locked box. Deviations: the token is also hidden from the `state` dump (it reports the page file name, not `location.href`); the request is read to the header terminator, so a request split across packets is served; `HEAD` gets 405 like every non-GET.
- [x] 15. [B] Drafts owned by Swift (findings 5, 8, 18, 20; G1; R3, R13, R14). Snapshots live in `~/Library/Application Support/<bundle id>/drafts/<hash>.json`, keyed by the canonical file path, with the preview PNG in Caches. The snapshot's asset `src` is the file path, resolved to the tokened URL at load time through tldraw's asset store, so a relaunch does not break it; `render` resolves it the same way. `load` carries an optional snapshot, `park` returns snapshot and preview, `render(imageURL, snapshot)` produces export PNGs and clears history afterwards (today's round trip leaves an undo entry, verified); export has a timeout and always answers; the page is stateless; a web content process termination reloads the page and re-sends the current image and snapshot; `forget` deletes files; a launch-time sweep deletes drafts whose image is gone; state (step 17) carries the web process pid (WKWebView exposes it only through private API; if that fails, an agent picks the WebContent process started right after the app). Verify: draw, quit, relaunch, reopen the card, annotations are back with the badge and the image visible; `kill -9` the web process named in state and the editor returns with the drawing; after Copy Annotated while annotating, `getCanUndo()` is unchanged; monkeypatch `render` to throw and Copy Annotated logs an error while the next one works. Done 2026-09-15. Verified: drew, quit, relaunched, the card carried the badge and the preview with the drawing, reopening restored both shapes with the arrow tool and `getCanUndo()` false; `kill -9` of the `webPid` from state reloaded the page and the editor returned with the drawing in 1.1 s; `getCanUndo()` was true before and after Copy Annotated while annotating, with the selection restored; `getSvgString` patched to throw gave `[copy-annotated] error export-failed boom from test` and the next export was ok; an export hung on purpose and then a `kill -9` answered `error export-failed` at once and the next export worked. Deviations: drafts are keyed by `shot.url.path`, the path the app uses everywhere, not a symlink-resolved one, so badges and previews match cards; the page builds the image URL from its own location, so the host passes only the path and a stored snapshot never contains a token; `park` and `export` answer through `callAsyncJavaScript` return values, so the `drafts`, `draft` preview, and `exported` messages and the `forget` call are gone; the page posts the snapshot 300 ms after each change, which is what makes an unsaved drawing survive the kill; loads and exports run with draft reporting suspended until the `loaded` frame, because tldraw delivers a snapshot load's changes on the next transaction; `export-failed` joins the error vocabulary; on an export error Copy Annotated copies nothing and toasts, rather than copying originals under an ok line; `webPid` comes from WKWebView's private `_webProcessIdentifier` through KVC guarded by `responds(to:)`, which works on macOS 15.7.3; the flight image still lifts on `loaded`.
- [x] 16. [B] Memory caps (finding 19; R4, R13). LRU limit on Thumbnailer; the Done preview downscaled like park previews; flight images dropped on dismiss; `pointSize` through ImageIO properties. Verify: RSS of the app and of its web process after opening 30 cards and five annotations, then repeating, stays within 10 percent on the second pass. Done 2026-09-15. Measured with the scratch settings (recentCount 30): after opening the 30-card stack and five annotations, app RSS 157 MB and web process 122 MB; after the same again, 153 MB and 132 MB, a 2.5 percent drop and an 8 percent rise, both within 10 percent. The thumbnail cache sat at 22 MB throughout. Deviations: the Thumbnailer cap is a byte budget (96 MB of decoded RGBA) rather than an entry count, evicting least recently used, with the newest entry kept even when it alone exceeds the budget; the Done rendering is downsampled to `Config.previewMaxPixel` (1600, the page's PREVIEW_MAX) off the main thread and then stored as the draft's preview on disk too, which step 15 had left to the next park; flight decodes drop whenever the stack hides, not only on dismiss; `pointSize` reads DPI from the header, which is what `NSImage.size` reports for a Retina capture, and the test pins the two equal; `[state] memory` logs resident size and cache bytes. During the second pass a geo shape appeared on one real screenshot with no input tool running, most likely a stray click while the annotator was up; its draft file was removed.
- [x] 17. [S] State and log as contracts (finding 11; G13, G14; R9, R13). One `[state] {json}` line assembled after the page replies or after a one-second timeout with `page: "unavailable"`, with a `?tag=` echo, global top-left points as in step 3, the screen name, drafts, previews, isActive, Accessibility trust, port, build, and the web process pid. Log grammar written in AGENTS.md: a date on the launch line, no embedded newlines, `key=value` pairs, size-capped rotation, every event one line. `[draft] parked <key>` and `[drafts] <n>` lines; `[stack] shown` carries the file count and scan time (1253 files today, 21 ms). Verify: `open -g "shotnote://state?tag=t1"` yields one line that `python3 -m json.tool` accepts and that contains the tag, the screen, and the draft keys; with the web process killed, the line still arrives within a second; a 6 MB log rotates. Done 2026-09-15. Verified: `shotnote://state?tag=t1` wrote one `[state] {json}` line that `python3 -m json.tool` accepts, with the tag, the screen (`Built-in Retina Display`, frame `[0, 0, 1512, 982]`), and the draft keys; with the stack up, 30 card frames in top-left points; `kill -9` of the web process followed at once by `state?tag=t3` answered in the same millisecond with `page: "unavailable"` and `pageState: "loading"`; the log padded to 7.6 MB rotated to `Shotnote.log.1` on the next write, leaving a 2 KB log; the launch line ends with `date=2026-09-15`; `[stack] shown cards=30 files=1255 scan=139ms shown=24ms decoding=0`. Deviations: rotation is at 5 MB, one previous file kept; the page section adds `shapes`, `canUndo`, and `hidden` (the locked-screen tell from step 14); the annotator `frame` is null while there is no window; `[draft] saved` is logged for every debounced snapshot and `[draft] parked` at park, with `[drafts] <n>` after each change to the set; the scan line reports the scan and the show separately; `webPid` comes through the private accessor from step 15 and the fallback agent method was not needed.
- [x] 18. [B] UI defaults (findings 21, 22; R17). Promote the tuned numbers to `UITweaks` defaults; `activeTool` looks up by `geo`; AGENTS.md:9 stops claiming nothing visual is hard-coded and names where the remaining constants live. No new knobs. Verify: a fresh settings file renders like the tuned one; a third geo tool highlights correctly. Done 2026-09-15. Verified: with a settings file that has no `ui` section and with the tuned one, the 30-card stack gave identical card frames, panel, and backdrop bands in `[state]`, and a pixel diff of the stack crop found zero differing pixels; with a temporary triangle geo tool, `setTool` of triangle, rectangle, and ellipse each showed as the toolbar's tool in `[state]` (the tool was removed again before the commit). 27 defaults changed; `motion` stays 1. Deviations: the annotator's `tool` and `color` were added to the `[state]` line so the highlight can be checked without a screenshot; a test pins that every default is inside its bound, since a default outside one would be clamped on load.
- [ ] 19. [S] Render test and tldraw upgrade checklist (G12; R18). An XCTest starts LocalServer, loads the built page into a WKWebView over the loopback origin, calls `render` with a fixture image and snapshot, and checks non-blank pixels where the annotation is. A checklist in AGENTS.md for bumping tldraw: license state, watermark text, snapshot migrations, the asset store hook, the blank-export workaround, protocol version. Verify: the test fails when `render` is replaced by tldraw's `toImage`.

### Phase C: ship

- [ ] 20. [B] Launch at login (new). `SMAppService` behind a setting, offered once by the first-launch toast. Verify: `sfltool dumpbtm` lists the app after enabling; turning the setting off removes it.
- [ ] 21. [S] Docs (finding 25; R10). Fix every line in finding 25; use `open -g` everywhere and say that opening the annotator activates Shotnote regardless; describe `scripts/input.sh`, the coordinate convention, the log grammar, the error codes, the `debug` setting, the settings override, the license key, `restore-apple-defaults`, and a fork checklist (rename in project.yml, `signing.env` or a self-signed certificate, `web/dist` before `xcodegen`, drafts on disk survive relaunch). Verify: each README command exercised once against the built app; the AGENTS.md dev loop followed end to end on a fresh clone.

Deferred, not steps: a control socket and a `shotnote` CLI that returns JSON instead of log polling (decide after step 17); FSEvents, if a folder replacement under Dropbox is ever observed; a Theme enum for the remaining constants.

## Appendix: verification scripts as run

All scripts assume the app is running, use `open -g` so the frontmost app keeps focus, and read the log slice written since a line-count marker. The sleeps are generous on purpose; once step 17 lands, wait on a tagged `[state]` line instead. `W` is the watch folder. Delete the test files afterwards; the app's own trash action does that and forgets their drafts.

Shared helpers:

```sh
W=$HOME/Dropbox/Screenshots; LOG=$HOME/Library/Logs/Shotnote.log
enc() { python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe="/"))' "$1"; }
fm() { osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'; }
```

### Rapid swap race (finding 3, step 12)

```sh
m=$(wc -l < "$LOG")
for i in 1 2 3; do screencapture -x "$W/Screenshot test-review-$i.png"; sleep 0.6; done
sleep 2.5
open -g shotnote://recent; sleep 1.2
open -g "shotnote://annotate?file=$(enc "$W/Screenshot test-review-1.png")"; sleep 1.6
JS='window.editor.createShape({type:"geo",x:200,y:200,props:{w:600,h:400,geo:"rectangle"}}); return window.editor.getCurrentPageShapeIds().size'
open -g "shotnote://eval?$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$JS")"; sleep 0.8
open -g "shotnote://annotate?file=$(enc "$W/Screenshot test-review-2.png")" & open -g "shotnote://annotate?file=$(enc "$W/Screenshot test-review-3.png")" & wait
sleep 2.2
open -g shotnote://state; sleep 0.8
sed -n "$((m+1)),\$p" "$LOG" | cut -c1-420
# Before the fix: annotator current=test-review-3 windowVisible=true and page state images:0.
open -g shotnote://cancel; sleep 1.3; open -g shotnote://dismiss; sleep 1.6
```

### New screenshot during a lone annotation (finding 4, step 12)

```sh
m=$(wc -l < "$LOG")
open -g "shotnote://annotate?file=$(enc "$W/Screenshot test-review-1.png")"; sleep 2.0
screencapture -x -R 200,200,600,400 "$W/Screenshot test-review-4.png"; sleep 1.6
open -g shotnote://state; sleep 0.7
sed -n "$((m+1)),\$p" "$LOG" | cut -c1-300
# Before the fix: annotating=nil, annotator windowVisible=false, no "[annotate] cancelled" line.
```

### File deleted behind the app (finding 6, steps 5 and 9)

```sh
m=$(wc -l < "$LOG")
open -g shotnote://recent; sleep 1.3
rm "$W/Screenshot test-review-4.png"; sleep 0.6
open -g "shotnote://annotate?file=$(enc "$W/Screenshot test-review-4.png")"; sleep 1.9
open -g shotnote://state; sleep 0.7
sed -n "$((m+1)),\$p" "$LOG" | cut -c1-300
# Before the fix: "[annotate] could not read image" then windowVisible=true and images:0.
open -g shotnote://cancel; sleep 1.3; open -g shotnote://dismiss; sleep 1.6
```

### Cleanup

```sh
open -g "shotnote://trash?file=$(enc "$W/Screenshot test-review-1.png")&file=$(enc "$W/Screenshot test-review-2.png")&file=$(enc "$W/Screenshot test-review-3.png")"
ls "$W" | grep -i 'test-review' || echo none
```

### URL decode check (finding 10, step 5)

```sh
m=$(wc -l < "$LOG")
open -g "shotnote://annotate?file=/tmp/nonexistent%20a%20b.png"; sleep 0.4
open -g "shotnote://annotate?file=/tmp/nonexistent%25100.png"; sleep 0.4
sed -n "$((m+1)),\$p" "$LOG"
# Before the fix the second [annotate] line reads "nonexistent0.png" with a hidden 0x10 byte.
```

### Activation check (finding 13)

```sh
open -g shotnote://recent; sleep 1; open -g shotnote://dismiss; sleep 1.3   # expect no [focus] line
open shotnote://recent; sleep 1; open shotnote://dismiss; sleep 1.3         # expect "[focus] stack dismissed: returned to …"
```

### Ad-hoc build (finding 7, step 8)

```sh
xcodebuild -project Shotnote.xcodeproj -scheme Shotnote -configuration Debug \
  -derivedDataPath /tmp/shotnote-adhoc build -quiet CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
codesign -dv /tmp/shotnote-adhoc/Build/Products/Debug/Shotnote.app 2>&1 | grep -E 'Signature|TeamIdentifier'
# Expect Signature=adhoc, TeamIdentifier=not set.
```
