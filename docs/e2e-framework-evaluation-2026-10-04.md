# Should the end-to-end suite move to tester-army/e2e? (2026-10-04)

No. [tester-army/e2e](https://github.com/tester-army/e2e) cannot drive a Mac app, and making it
do so would mean writing our own engine. Most of what our scenarios check is not visible on screen,
so even a working engine would leave that work in place. The suite stays in `scripts/e2e`.

## What tester-army/e2e is

A TypeScript test runner for web and mobile apps, at version 0.x. A test can describe a goal in
plain words, such as "upgrade the workspace to the Pro plan", and a model drives the app to reach
it. The runner records the actions an agent took and replays them without a model on later runs,
until the app changes. Tests can also use locators and assertions, like Playwright's, with no model.

It ships two engines, the part that observes and drives an app:

- **Web**, on Playwright.
- **Mobile**, on [agent-device](https://github.com/callstack/agent-device). Its platform type is
  `'ios' | 'android'` (`packages/mobile/src/options.ts`), so it drives simulators and phones only.

agent-device itself can drive macOS apps, through a local helper. The e2e docs describe how to
write an engine for "a desktop app", and nothing in the repository or its issues plans one.

## What our suite does

`scripts/e2e` is about 1,500 lines of Python: 23 scenarios, all passing on 2026-10-03. Each
scenario builds a test copy with its own bundle id, launches it on a scratch home, settings file and
screenshots folder, drives it, and checks the results. `docs/e2e-suite-plan-2026-09-29.md` has the
design.

Most of the checks look at things no screen shows:

- The `[state]` report and the log's `ok` and `error` lines.
- The files the app writes: renderings, drawings, the settings file after a repair.
- The pasteboard's types and bytes. `draw_and_done` checks that the PNG on the pasteboard is
  byte-for-byte the rendering on disk.
- The pixels of a rendering, to check that marks are drawn in the right colour.
- Apple's screenshot defaults, first launch and upgrade on a fresh home folder.
- Send and Reply, through a fake Claude Code inbox and a fake `codex`.

Eleven scenarios post keys and clicks. Each one is gated on the test copy's own `[state]`: the
step reads `annotator.key` or `stack.key` and sends nothing unless the test copy has the keys.

## Why it does not fit

- **There is no engine for the Mac.** We would write one on agent-device's macOS backend and keep
  it working through e2e's 0.x changes, which its README says can break between minor releases.
- **The screen is the smallest part of what we check.** Every check in the list above would become
  a TypeScript fixture doing what the Python does now. The rewrite would change the language, not
  what the suite can see.
- **The editor is one image to the accessibility tree.** `EditorView` reports itself as an image
  named after the screenshot, and its marks are layers with no elements of their own, as are the
  flights. An agent would find a mark in a screenshot, so drawing steps would rely on pixel
  coordinates, which the runner replays only at the recorded window size. The stack's cards are
  SwiftUI views and may expose more; the probe below would show how much.
- **An agent on the real desktop can type into the wrong app.** agent-device's macOS backend drives
  the Mac the tests run on, not a simulator. On 2026-09-29, keys from a test went into Slack. Our
  gate on `annotator.key` is what stops that, and a model choosing its own actions has no such
  gate.
- **It adds a toolchain.** The repository has no Node.js today. e2e brings pnpm, a model provider
  for agent steps, and telemetry that is on unless turned off.

What e2e offers that we lack, plain-language steps and a replay cache, matters most for apps whose
screens change often and are built from standard controls. Vignette is neither.

## Where it could help

- **The landing page.** `site/` is a web page, and e2e's web engine fits it as it is. Nothing
  tests the page today beyond manual checks in a browser. Locator tests need no model.
- **Exploratory passes.** e2e's [bug bash](https://e2e.tester.army/docs/bug-bash) lets an agent
  explore an app and report what looks wrong. Once someone writes a Mac engine, that could cover the
  Settings and setup windows, which use standard controls. It would add to the suite, not replace
  it.

## A cheap probe, if the question comes back

Run `agent-device snapshot --platform macos` against a test copy with the stack and the annotator
open, and read the accessibility tree it returns. If the cards, the selection strip and the toolbar
appear with names, a Mac engine for the windows would be worth a spike. If they do not, an engine
could only see the screen as pixels.
