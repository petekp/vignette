# Live ink: turning it on, its pair, and what it needs

How a person turns live ink on, which modifiers hold it, and what it says when something it needs
is missing. `docs/live-ink.md` has the rest of live ink's rules. The decisions behind these are in
`docs/live-ink-release-plan-2026-10-24.md`, "Decisions for Pete" 4 to 7.

| Part | Where |
| --- | --- |
| The pair and its refusals | `LiveInkChord.swift`, `LiveInk.takeChord` |
| The offer | `LiveInkOffer.swift`: `AppDelegate.offerLiveInk`, `LiveInkOfferSection` |
| Whether Claude Code can answer | `LiveResponderAvailability.swift`, `LiveInk.checkResponder` |
| A notice beside the pointer | `LiveNotice.swift`, `LiveInkOverlay.showNotice` |

## Turning it on

- Live ink is turned on in setup's live ink page, the General tab's switch, or the menu (`liveInk`).
- An install that finished setup without seeing that page gets a one-time offer at the top of the
  General tab, on a launch that makes no other offer: the Settings window shows one tab, and the
  agent plugin's offer goes first. The offer is recorded as made (`liveInkOffered`) when it opens,
  as the plugin's is, and whenever live ink turns on, by any switch. An install with live ink on
  never sees it, and a showing offer leaves when the switch goes on. A settings file written before the offer existed that already holds `liveInk`
  counts as offered (`Settings.migrate`), since the switch in it was set by the person or by setup.
- What leaves the Mac is said in three places (`SetupInkCopy.costNote`): under the switch, on
  setup's permissions page, and in the note's prompt until the first ask to Claude
  (`liveInkAskedClaude`). Until then it comes before why speech cannot listen
  (`NoteContent.prompt`). The prompt goes once the person types or speaks, so with speech on the
  note can fill before it is read.

## The pair

- The chord is a pair of modifiers, `liveInkChord`, one of `LiveInkChord`'s five: ⌃⌥ by default,
  ⌃⇧, ⌥⇧, ⌃⌘ and ⌥⌘. It is picked under the switch, as "Hold to draw". VoiceOver holds ⌃⌥ too,
  which is why the pair can change, and why there is no pause for VoiceOver.
- The picker sits under the switch rather than in the stack's shortcut control, as Pete decided on
  2026-10-29. The pair belongs to the switch, and that control offers double taps and key
  combinations, which do not fit a held pair.
- A pair is refused when the stack's key combination holds it, since pressing that combination
  begins the chord, and live ink would take the pointer and let go of the focus as the stack comes
  up. The stack's recorder refuses such a combination from the other side, whether live ink is on or
  off. A collision already in the file, from an older build or an edit by hand, is named under the
  picker for as long as it lasts. A double tap never collides: `ModifierTap` counts a modifier only when it is pressed alone, and
  another modifier's press resets its count.
- A new pair replaces the chord and keeps the marks (`LiveInk.takeChord`). The menu's badge and the
  General tab's words name the pair, and so do the keys in setup's live ink demo.

## When Claude starts

- `claude -p` starts as the first stroke moves, and only when the note that ink goes to is aimed at
  Claude (`LiveInk.prepareResponderForStroke`). A press of the chord, a tap that erases a mark, and
  a note to a session start no process, so nobody is billed for holding the keys. A Claude Code that
  failed is started again only by an ask, not by the next stroke.
- `LiveInk.answeringResponder` is the one place live ink picks its responder. A Codex responder
  joins there.

## What it says when something is missing

- **Claude Code.** `claude auth status --json`, which sends no message, says whether Claude Code is
  installed and signed in. It is asked when live ink turns on, when a note opens while Claude could
  not answer, and on setup's live ink page (`[live-ink] responder ready|notInstalled|signedOut`,
  `[state] liveInk.claude`). An answer that cannot be read counts as ready, and the ask then reports
  what the process says. Without Claude Code, live ink still draws and notes still go to sessions. A
  note with no session picked opens on the first running session, and a note already open moves
  there when a late check says Claude cannot answer, unless the person picked its target. Its prompt
  says why when Claude is its target, and Claude's row in the target menu says why and cannot be
  picked.
- **Screen Recording.** A note's picture needs it. Without it, a notice beside the pointer says so
  as the pointer field comes up, before any ink is drawn. It wraps at 260 pt and fades after 4 s,
  or as the chord is let go. It waits for the field, so a chord on its way to a window manager's
  shortcut says nothing. It is part of the pointer, not a toast, as Pete decided on 2026-10-29.
- **Speech.** When speech cannot listen, for a missing permission, no on-device model, or a
  microphone that will not start, the note's prompt says why (`LiveInk.speechProblem`). It goes once
  speech can listen or is turned off.
- Every notice comes and goes with motion: the notice beside the pointer, a refused pair's reason,
  the offer, setup's line about Claude Code, and the note's prompt, which cross-fades. The note
  grows and shrinks on the popover's animation. `docs/voice.md` has the words.
