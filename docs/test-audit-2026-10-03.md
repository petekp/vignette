# Test audit repairs: 2026-10-03

The typing handoff checks visible word ink. Done's end-to-end scenario checks its clipboard output.
Queue cancellation is exercised while files still wait. Large-image rendering retains its own
coverage under a precise name. Two redundant tests and an unused fixture parameter are removed.

## Changes and retained coverage

| Change | Contract and credible failure | Why this boundary matters |
| --- | --- | --- |
| `EditorViewTests.testWhenTypingEndsTheWordsStayVisibleInEachSampledCapture` | White word ink and the red note tag remain visible in sampled native captures while a bitmap replaces the text view. Missing glyphs fail even when the tag remains. | Settled renderer and zoom tests do not exercise this handoff. Word pixels are counted inside the line's padded bounds, excluding the tag's white edge and the grey screenshot. |
| `draw_and_done` in `scripts/e2e/scenarios.py` | Return publishes the exact rendered PNG bytes and that result's file URL. Missing data, stale bytes, or another result URL fail. | Unit tests call Clipboard directly. This scenario exercises the editor action's connection to it through the application. It uses the existing pasteboard probe. |
| `annotate_queue` in `scripts/e2e/scenarios.py` | Both original handovers retain their order, Copied notices, and dim continuity. A second run cancels with two files waiting, empties the queue, ends the run, and opens neither waiting file. | Reducer tests cover queue rules. This scenario also covers controller wiring. The URL command is described as cancellation; no synthetic Escape is sent. |
| `MarkRenderingTests.testA3102By6780ImageRendersAtItsFullSize` | A large image with rectangle, arrow, and text marks renders and decodes at its full dimensions. | The test's synchronous global-queue dispatch did not establish background execution. The test now names its large-image contract and renders directly. |

The two deletion decisions preserve stronger tests:

| Removed test | Stronger retained test | Removal scope and risk |
| --- | --- | --- |
| `SettingsTests.testDefaultsAreWithinTheirBounds` | `testValidatedLeavesGoodDataAlone` supplies the same default settings and checks the entire validated result plus no corrections. `SettingsData.ui` already starts as `UITweaks()`. | Only the duplicate test is removed. The default-validation owner still serves bootstrap and disk reload. The narrower check arrived in `434c5be` after the broader check in `837cba7`. Both detect default clamping, so removal adds no distinct risk. |
| `ReplyProtocolTests.testTheBundlesDigestIsRecomputedRatherThanTrusted` | `testABundleChangedAfterItWasPreparedNoLongerMatchesItsAttempt` prepares a genuine digest, changes the bundle bytes, and requires a mismatch. It catches both trusting the attempt and a constant digest implementation. | The duplicate and the sole-use `stage(digest:)` override are removed. Both tests arrived in `7761ea9`. `ScreenshotRequests.accept` continues to use `readBundle` and compare the computed digest. The mutation test preserves the integrity check. |

Configuration bounds, digest framing, symlink rejection, authorization, reply recovery, terminal
clearing, folder absence, reducer ordering, zoom geometry, and bitmap lifetime tests remain.
They protect separate failures. No test-only production interface was added or removed.

## Verification

- The full native unit suite passed: **469 tests, zero failures, zero skips**.
- A temporary native control set the word color to the tag color through `EditorView.applyTweaks`.
  The strengthened handoff test failed at its word-ink assertion with zero qualifying pixels.
  The red-tag assertion passed. The temporary edit was removed, and the restored test passed.
- Both native end-to-end scenarios passed: `draw_and_done` and `annotate_queue`.
  The first compared actual clipboard PNG bytes and its file URL with the action's rendering.
  The second cancelled with two waiting files and verified that neither opened.
- Disposable scenario controls accepted valid fixtures and rejected retained queues, opened
  waiting images, stale PNG bytes, wrong file URLs, and missing clipboard data.
- Independent adversarial review found no issues. `git diff --check` passed.

Unit tests used isolated derived data. End-to-end tests used their own bundle, scratch home,
settings, watch folder, and launch lock. The runner restored the pasteboard. Tagged state confirmed
that the normal app was restored to its usual bundle and settings file.

Verification output:

- `/private/tmp/vignette-test-audit-unit.log`
- `/private/tmp/vignette-test-audit-unit-summary.json`
- `/private/tmp/vignette-test-audit-glyph-negative-summary.json`
- `/private/tmp/vignette-test-audit-glyph-positive.log`
- `/private/tmp/vignette-test-audit-e2e.log`
- `/private/tmp/vignette-native-e2e-audit-repair-probe.log`

## Scope

Production changes: zero lines. Swift tests: 27 added, 29 removed. End-to-end test support:
38 added, 6 removed. This report records the final checks and the reasons to retain or remove them.
CI workflows, build and release scripts, and production behavior are unchanged.
