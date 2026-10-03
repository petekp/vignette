# Landing page performance

The changes reduced the constrained phone's largest contentful paint by 22.5% in three paired
cold-load trials. The screenshots and trailer retain their original bytes.

The six screenshots used by the initial demos still decode eagerly. Later agent images prepare
as their section approaches, and Send starts preparing Claude's answer. The footer fan builds
within 1200 pixels of the viewport, and its app icon uses native lazy loading. These changes avoid
566,437 bytes of image payload during the initial load.

A browser window keeps its current image until the replacement decodes. Claude's card also waits
for its image before arrival. Fan resize callbacks use their supplied width, rounded to preserve
the existing crop geometry.

The baseline is a saved copy of commit `86bd44d`. The candidate contains the four site changes
described above. Lighthouse 13.0.3 ran in isolated Headless Chromium 154. The local static server supplied
gzip text, byte-range video responses, and no-store headers. Each profile used three alternating
before/after pairs. Tables show medians.

The phone profile used a 390 by 844 viewport, 4× CPU slowdown, and Lighthouse's DevTools network
throttling configured for 1600 Kbps download and 150 ms request latency. Desktop used a 1440 by
1000 viewport with provided, unthrottled conditions. Device pixel ratio was 1.

| Phone cold load | Before | After |
| --- | ---: | ---: |
| Lighthouse performance score | 87 | 93 |
| First contentful paint | 662 ms | 647 ms |
| Largest contentful paint | 3,978 ms | 3,081 ms |
| Total blocking time | 96 ms | 77 ms |
| Main-thread work | 1,104 ms | 988 ms |
| Transferred bytes | 4.02 MB | 3.46 MB |
| Demo JPEG transfer | 1.107 MB | 0.617 MB |
| Cumulative layout shift | 0 | 0 |

The trailer was the phone's largest contentful element. Its paint time ranged from 3.91 to
3.99 seconds before and 3.06 to 3.16 seconds after. Video buffering makes total transferred
bytes vary between runs; the avoided image payload is fixed.

Desktop performance scores remained 100, with zero blocking time and layout shift. Median
main-thread work fell from 196 to 176 ms. Initial DOM elements fell from 424 to 326.

Complete demo benchmarks used 4× CPU slowdown and an unthrottled local network. Each viewport
used three alternating before/after pairs. Main-thread task time includes the whole driven demo;
it is not the animation's duration or a frame-rate measurement.

| Complete demo task time | Before | After |
| --- | ---: | ---: |
| Screenshot demo, desktop | 894 ms | 739 ms |
| Screenshot demo, phone | 1,009 ms | 786 ms |
| Agent demo, desktop | 1,137 ms | 1,148 ms |
| Agent demo, phone | 1,613 ms | 1,486 ms |

No interaction task exceeded 50 ms in any run. Both demos completed without runtime errors.
The agent demo's script cost remained roughly unchanged. Its phone layout cost increased from
76 to 90 ms across the complete sequence, while total task time decreased.

Twelve alternating desktop resizes at 4× CPU slowdown reduced layout passes from 96 to 31.
Median layout time fell from 29.0 to 27.5 ms. The count reduction is clear; the time saving is small.
Forty crop comparisons at integer and fractional widths matched the original geometry.

Both resting demos and the footer produced identical PNG captures before and after at desktop
and phone widths in dark mode with Reduce Motion enabled. The share image capture also matched.
A slow-image check held the itinerary revision and Claude's answer: the visible itinerary stayed
in place, Claude's card arrived decoded, and Reply completed. The final source review found no
actionable issue. JavaScript syntax and `git diff --check` passed.

Temporary reproduction commands:

```sh
node /private/tmp/vignette-lighthouse.mjs pair mobile 3
node /private/tmp/vignette-lighthouse.mjs pair desktop 3
node /private/tmp/vignette-runtime-perf.mjs resize desktop 3
node /private/tmp/vignette-runtime-perf.mjs interaction desktop 3
node /private/tmp/vignette-runtime-perf.mjs interaction mobile 3
node /private/tmp/vignette-slow-image-check.mjs
node /private/tmp/vignette-visual-perf.mjs
```

The runners use the isolated browser's CDP port. Raw results, traces, and captures are under
`/private/tmp/vignette-perf-results/`; the server and baseline copy are also under `/private/tmp/`.
Restart that server and browser, and update the runner port before repeating the commands.

These are local lab results. They do not measure production CDN behavior, physical-phone
performance, Safari, or 120 Hz animation smoothness. Clipboard benchmarks validate rendered PNGs
with controlled browser writes and leave the system clipboard alone.
