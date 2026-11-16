# The add command and the agent title

`add` is the exception to the `file=` rule in `docs/rules/driving-the-app.md`, and it takes two
paths that rule does not cover.
`add?file=` copies an image in from anywhere and the watcher then reports it like a capture,
minus the copy and annotate toggles (`&annotate` opens the editor; `FolderWrites.add`). `&agent=<name>` says which
agent is pushing it: the name is recorded on the copy as the `com.petepetrash.vignette.agent`
extended attribute (`Agent.swift`, `xattr -l` shows it) and the card gets a white "From <Name>" tab
with the vendor's logo when `Resources/agents/<name>.svg` has one (`Agent.logo(for:)`). A logo
that is a single black shape, like Codex's, is listed in `Agent.oneColourLogos` and drawn in the
colour of the text beside it.
The tab sits in the card's top-right corner, `CardView.buttonPad` in from its edges, and never
reaches past the card (`AgentBadge.swift`). When the whole capsule does not fit inside the card's
drawn width with that margin on both sides and between it and the selection circle in the top-left
corner, it folds to the logo alone in a circle, or to
`Agent.fallbackSymbol` for an agent with no logo (`AgentBadgeFit`). It says its words again once
the card has `AgentBadgeFit.hysteresis` (4 pt) more room than it needs, so a pinch held near the
edge does not fold and unfold it with each step of the stack's width. "From Claude" needs a card
136 pt wide: a 188 pt card in the stack at its narrowest beside the annotator is 94 pt and folds,
and so does a tall capture's narrow card at full width. The words are measured once per label and
size. The right edge stays put, the logo travels with the capsule's left edge, and the words fade
as the capsule closes over them. A fold that comes with the stack's own spring rides it, so the
capsule moves in step with the card and stays inside it all the way. A zoom sets the width with
animations off, and the fold then runs its own `ui.relayoutDuration` spring. A Cmd+Plus or a fast
pinch narrows the card faster than that spring closes, so `CardView` clips the tab to the card: for
a few frames its left end is cut at the card's edge. At rest the clip cuts nothing, shadow included,
since the tab keeps its margin from every edge. Its accessibility
label is the full words in either shape. Flights, the drag image and a stitch's converge never draw
the tab: it fades out as the card leaves its slot and fades in, in the shape that card's slot
calls for, as it lands. A lone thumbnail follows the same rule at its own width.
The same tab says a card was sent (`CardTab`, `Card.Sent`): "Sent to <title>" with the client's
logo on a person's screenshot, and "From <Name> · Replied" on an agent's card sent back to the
session it came from. Folded, it keeps a paper plane or a check beside the logo
(`AgentBadge.glyph`), only while the folded tab stays clear of the selection circle by the words'
margins (`AgentBadgeFit.keepsGlyph`); narrower, it is the logo alone. An agent's card sent to any other session keeps its "From <Name>" tab. The
send is the `com.petepetrash.vignette.sent` attribute, JSON `{client, id, title, at}`
(`Agent.record(sent:on:)`), which `docs/rules/send.md` says when it is written. A card reads it as
it reads the agent's name, once when the card is made, and the card's tab changes when a send of it
is recorded (`ThumbnailController.delivered`). Replied compares the send's client and id with
`ScreenshotRequests.origin(of:)`, not `Agent.origin(of:)`: a published reply's file has no session
attribute, and its origin is its request. The editor shows no tab.
`&session=<id>` names the agent session pushing it. With `agent=claude` it is a Claude Code
session, recorded beside the name as `com.petepetrash.vignette.session`. With `agent=codex` it is
a Codex thread, recorded as `com.petepetrash.vignette.thread`, the attribute live ink uses for
one. The card's bar is then Reply and goes back there. `Agent.record(agent:origin:)` is the one
writer of the name and those attributes. It removes a session an earlier push recorded that this
one does not name, so a push with `agent=` and no `session=` of a file already in the folder
leaves it with no Reply. It also removes the file's send, which was of the picture this push replaces.
`ScreenshotRequests.origin(of:)` is the one reader: a reply's request, else the file's
attributes (`Agent.origin(of:)`). The id is the pusher's claim. Sending to it
still checks that a live plugin inbox holds that Claude Code session
(`ClaudeCodeConnection.submit`), or that Codex's thread store has that thread (`codex queue
--thread`). Anything but a UUID, or a session from any other agent, is not recorded, and `[add]`
still answers `ok` with a warning.
`&marks=<json file>` pushes the agent's own annotations with the image: they join the
screenshot's drawing before the card appears (`Drawings.add`), and the command answers once that
drawing is written. That JSON file may also be anywhere; it is read on the main thread, so it is
capped at 256 KB, and an error line names the mark and the field without quoting what the file
said. A text too long to fit even across the whole picture is cut at the edge and named in a
`[marks] text too long for <name>` line, which is the only thing that says so, since `[add]`
still answers `ok`. `docs/commands.md` has the format and the rest.
`&title=<text>` and `&description=<text>` say what the pushed image shows. Both go through one
type, `AgentTitle`. It makes each part one line and cuts it at a word to its limit, 60 and 140
characters. A cut logs an `[add] warning` line, and `[add]` still answers `ok`.
A push that names its session, onto a file with no marks yet, records the fingerprint of the
drawing and of the picture file's size and date (`Agent.record(sentDrawing:on:)`). A published
reply does too. Reply reads it
to tell that the person changed nothing (`docs/rules/send.md`).
`Agent.record(title:on:)` writes the two parts as extended attributes beside the agent's name,
and `Agent.title(of:)` reads them back through the same `AgentTitle` check. Only the editor shows
them, above the frame (`AgentTitleView`, which only `AnnotationController` makes). The text
sits on the editor's blur with no background. Its left edge sits `ui.annotationCornerRadius` in
from the frame's, where the frame's top edge comes out of its rounded corner. It wraps at the
frame's right edge, or `ui.agentTitleMinWidth` wide when that is wider, never past the room's
right edge (`StackLayout.titleWrapWidth`). Its text keeps its size at any zoom. Its ink is white or
black, whichever has the higher contrast with the lightest or darkest part of the screen behind
it (`TitleInk.choose`). With Screen Recording that is read off the main thread at open and after
each zoom step. Without it, the ink follows the system appearance. `[annotate] title ink=… source=…`
logs which. No card, rendering, stitch or send draws it. An image with a title opens with room above the frame for it
(`StackLayout.annotationFrame`'s `above`). Its zoom room ends twice `ui.agentTitleGap` above the
title (`AgentTitleView.marginAbove`), so a zoom never pushes the title off screen or against the
menu bar. The title fades in over `ui.agentTitleFade` once the flight has
landed and its ink is known, whichever comes second (`TitleReveal`), and fades out on the
flight home (`TransitionLayer.Caption`). When the ink is still unknown 0.5 s after the landing
(`TitleReveal.inkWait`), the title shows in the appearance's ink, and the measured ink replaces
it when it answers. The wait is for data, not motion, so the motion scale does not shorten it.
`[annotate] title shown ink=… source=… waited=<ms>ms` logs how long each title waited after the
landing. `[state] annotator.title` is its frame, or null when there
is none or it has not shown yet, and `annotator.titleInk` its ink and where the ink came from. The reply helper takes the same two as `--title` and `--description`, and the published
reply records them as `add` does. `docs/agent-title-2026-10-28.md` has the measurements.
