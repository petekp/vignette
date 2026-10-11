# TODO impact ranking

Pinned comments are the strongest product bet. Marks sized to small screenshots and one consistent
Copy action are the clearest immediate improvements. Live-screen drawing has the highest ceiling,
but its added value needs a small experiment first.

This assessment covers all 17 entries in `docs/TODOS.md`, including the discussed ideas and known
costs. Impact means useful change for people using Vignette: how much an idea helps, how often it
helps, and whom it reaches. The order accounts for the evidence behind that benefit. Effort is
listed separately. These are product judgments from the current working tree and dated notes,
not measured adoption forecasts. Adjacent entries within a tier are close calls.

## Ranking

Confidence describes the evidence for the benefit. Effort describes the remaining work, including
product decisions and verification; it is not a schedule estimate.

| Rank | Idea | Potential impact | Confidence | Effort | Assessment |
| --- | --- | --- | --- | --- | --- |
| 1 | Annotator redesign: pinned comments and replies | High | Medium | Large | Several precise feedback items can become one readable exchange. Rank the comments here; session tabs and the tool rail contribute much less on their own. |
| 2 | Drawing marks as text, then crops per mark | High for agent users | Medium | Medium | Gives agents exact note text and marked regions without reconstructing them from the annotated image. Reuses the drawing data Vignette already owns. |
| 3 | Drawing on the live screen, both directions | Very high ceiling | Low | Large | Could let a mark identify an app, window, control or phrase. That could remove substantial explanation, but the demos establish feasibility more than usefulness. |
| 4 | Marks sized to the screenshot | High | High | Medium | Improves the central act of pointing at a small detail without covering it. Some text adaptation already exists; consistent shape and note sizing is the remaining benefit. |
| 5 | Vignette without agent features | Medium–high | Low–medium | Medium | Gives people with agents installed a simpler screenshot-only experience. Wider adoption is plausible, but no evidence reviewed establishes agent controls as an adoption barrier. |
| 6 | Fold Copy Drawing into Copy | Medium–high | High | Small–medium | Makes an ordinary copy match the annotated card people see. Removes a repeatable surprise and aligns Copy with dragging. |
| 7 | Stitch layout | Medium | Medium | Medium | Preserves more useful detail in mixed-size sets. Equal-size sets gain little, and packing alone cannot rescue many full-screen images. |
| 8 | Sound effects | Medium | Low–medium | Small–medium | A reply-arrival sound could help someone working in another app. Confirmation sounds are useful selectively; sounds on every action could become distracting. |
| 9 | Agent pushes piling up: naming or another folder | Low–medium | Low–medium | Small for naming; larger for another folder | Clear names help identify what changed. A second watched folder needs evidence that naming cannot solve actual clutter. |
| 10 | Glint around a new thumbnail | Low–medium | Medium | Small–medium | Adds repeated visual character and can draw attention to a fresh arrival. Its benefit depends on restraint and fit with the existing motion. |
| 11 | Lay out only visible cards while the stack narrows | Low–medium | Medium | Medium | Fluid motion matters to Vignette, but the latest documented Release measurement found only zero or one slow commit per transition. Re-measure before investing. |
| 12 | Preserve Apple's original values after a crash and settings deletion | Low overall | High | Small | A concrete trust and recovery fix with narrow exposure. Useful maintenance, even though it does not change most people's daily use. |
| 13 | Correct oriented images and their marks in stitches | Low overall | High | Small–medium | Prevents incorrect output for imported images with an orientation flag. Serious when encountered, but ordinary screenshots do not exercise it. |
| 14 | Trailer camera drop | Low | Low–medium | Small if reproduced | Removes a visible defect from a public demonstration. Worth a short inspection because the existing take can be recut. |
| 15 | 3D logo with physically based materials | Low | Low | Large for the proposed scope | Could improve a first impression. Multiple rendering paths and appearance matching are substantial work for a moment people encounter infrequently. |
| 16 | Move card extended-attribute reads off the main thread | Negligible on measured local files | High locally; low for remote files | Small–medium | The recorded APFS cost is tiny. Remote placeholders are a reason to measure, not current evidence of a stall. |
| 17 | Xcode JSON project format | None under the current workflow | High | Medium–large if replacing XcodeGen | The generated project is ignored. Readable diffs and editable configuration already come from the committed YAML source. |

## Why the leaders rank here

**Comments improve the exchange Vignette already supports.** A person could name several issues,
and an agent could answer each one. The remaining value is individual comments and replies, since
Copy, the message field, Send's shortcut, the target menu and Reply already exist. The redesign
also consumes image space, so the comments must justify that cost. Compare one real review with
several issues in the current editor and the existing mockup. Look for missed issues,
clarification turns and time to understand the feedback. Comments remain paused in the TODOs.

Evidence: [remaining design](annotator-redesign-2026-09-24.md), especially its Comments and Issues
found in review sections; `Sources/AnnotatorToolbar.swift:635` shows the current agent controls.

**Marks as text is the strongest smaller agent improvement.** Send currently takes a rendered PNG
and writes the image, reply ticket and request record. Its message points the agent at that image.
The sender's exact mark text and geometry are not exported beside it. A small text export could
preserve the words and identify target regions; crops could then improve difficult small details.
Compare the current image against the same image with a manually prepared mark list and crops on
a few real tasks. Record interpretation errors and follow-up questions before building a new UI.

Evidence: `Sources/ScreenshotRequests.swift:315` and `:421`;
`Sources/Drawing.swift:23`; [the TODO](TODOS.md).

**Live-screen drawing is the biggest uncertain bet.** It could add the identity of the control
beneath a mark, which a screenshot alone does not supply. The demonstrated window ring and
recognized-text arrow do not prove that the full workflow saves effort. The exploration's sample
of 55 hand-made crops supports convenient cropping; it does not establish demand for control
identity. Compare crop-only input with crop plus manually gathered app, window and control data.
Proceed if that extra information repeatedly prevents ambiguity or a wrong target.

Evidence: [live-screen exploration](live-screen-2026-09-18.md), especially What was demonstrated
and The open question. Comments, structured marks and live anchors overlap: their impact should
not be added as three independent gains.

**Small-capture sizing fixes a current core behavior.** New drawings use the screen's backing
scale, and stroke width depends on that scale rather than the capture's dimensions. Typed notes
already shrink to fit, and agent text already scales with image width. The improvement is a
consistent sizing rule across shapes, notes, cards and exported images. Compare the same marks on
a button crop, a window and a full-screen capture, at the editor's fitted size and in the PNG.

Evidence: `Sources/AnnotationController.swift:152`, `Sources/MarkRendering.swift:369`,
`Sources/AgentMarks.swift:59`; [text sizing](editor.md#how-a-text-grows).

**Copy consolidation has a clear behavior gap.** Ordinary Copy uses the original files, while
Copy Drawing renders stored marks. Dragging already exports the drawing people see. This makes
Copy consolidation a strong first change even though comments have greater product upside.
Verification would need to cover annotated images, images without marks, recordings, mixed
selections and rendering failures.

Evidence: `Sources/AppDelegate.swift:366`, `:492` and `:567`;
`Sources/Config.swift:19` and `:27`.

## Suggested next investments

1. **Consolidate Copy, then tune marks on small captures.** Both improve the existing screenshot
   experience with a clear behavior to assess. Mark sizing needs a visual comparison before a
   scaling rule is chosen.
2. **Try structured mark text and crops on real agent tasks.** This can test the need underlying
   comments with little new interaction design. Keep text and crop benefits separate in the
   comparison so either can succeed on its own.
3. **Evaluate comments before resuming the full redesign.** Test whether individually answerable
   feedback improves a review enough to justify the extra controls and smaller image viewport.
4. **Probe live-screen context before building the complete flow.** Establish whether app and
   control identity adds value beyond the crop. The existing overlays provide a feasibility base.

The no-agent option moves up if people with agents installed regularly want screenshot-only use.
Setup already skips its agent page when no agents are detected, and the editor omits Send controls
without a destination. Its remaining audience is narrower than the full screenshot-user audience.
Evidence: `Sources/SetupWindow.swift:253` and `Sources/AnnotatorToolbar.swift:642`.

Stitch needs a real reading comparison before a warning threshold is chosen. The layout note's
gains are calculated, and it says no model read those stitches. Current Anthropic documentation
still distinguishes standard and high-resolution image budgets, so reader assumptions matter.
The Claude Code client's resizing behavior was not verified in this assessment. Compare current
stitches, wrapped layouts and separate images on the same named controls.
Sources: [layout calculations and limits](stitch-layout-2026-09-27.md),
[Anthropic vision guidance](https://platform.claude.com/docs/en/build-with-claude/vision).

The lower-ranked correctness fixes can be worthwhile small jobs. Their rank reflects exposure,
not whether the failure is acceptable. For performance, use the latest documented Release
measurement rather than the older Debug symptom:
[stack narrowing measurements](prerelease-fixes-2026-09-26.md#6-the-stack-stuttering-while-it-narrows).
The attribute-read concern comes from `Sources/Agent.swift:51`; the project-generation conclusion
comes from `scripts/build.sh:13` and `.gitignore:2`.
