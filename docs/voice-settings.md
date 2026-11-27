# How the Settings switches speak

These are the Settings switches' messages, written to the rules in [voice.md](voice.md).

A switch's line says what changes when it is on, or what happens without it when that is the reason
to turn it on.

| Switch | Title | Line under it |
| --- | --- | --- |
| Claude Code may open sent drawings (`ClaudeReadRule`), in the Agents tab | Let Claude Code open drawings without asking | Otherwise Claude Code stops to ask you in its terminal each time you send one. This adds a permission to Claude Code's settings for these drawings only. |
| Under setup's agents while Claude Code is on (`ClaudeReadRule.setupNote`) | | Claude Code will open the drawings you send without asking you first. You can change this in Settings. |
| Naming the apps a screenshot shows (`sendCaptureApps`), in the Agents tab | Tell agents which app a screenshot shows | Send names the apps in screenshots you take from now on, such as Safari or Xcode. Vignette keeps the names with each screenshot, never a window's title. |
| Live ink (`liveInk`), in the Live Ink tab | Live ink | Hold *pair* to draw anywhere on your screen. You can also share your drawings with an agent session. (`LiveInkSettings.switchLine`) |
| Speaking while drawing (`liveInkSpeech`), under Live ink | Speak while you draw | What you say goes into the note beside your ink. Your voice stays on this Mac. |
| When the ask goes (`liveInkSendWhenQuiet`), an experiment | Ask when you let go | |

*pair* is the live ink chord as glyphs, ⌃⌥ unless another is chosen (`LiveInkChord.glyphs`).

| Where | Words |
| --- | --- |
| The pop-up that picks the pair (`liveInkChord`), under the Live ink switch | Hold to draw; its choices ⌃⌥, ⌃⇧, ⌥⇧, ⌃⌘, ⌥⌘ |
| Under it, when the stack's key combination holds the pair picked (`LiveInkChord.refusal(against:)`) | *shortcut*, the stack's shortcut, starts with these keys. You can pick another pair. |
| Under the stack's Keys box, when the combination pressed holds live ink's pair (`LiveInkChord.refusal(ofStackShortcut:)`) | Live ink uses *pair*. You can pick another combination. |
| Under the stack's Keys box, for ⌘ with one key (`HotKeySpec.refusal`) | *keys* is a command in every app. You can add ⌥ or ⌃. |
| The same, for ⌘⇧3, ⌘⇧4 or ⌘⇧5 | *keys* takes screenshots. You can pick another combination. |
| The same, for ⌃ with Space or an arrow | macOS uses *keys*. You can pick another combination. |
| Live ink's one-time offer, at the top of the Live Ink tab | Try Live Ink. Holding *pair* lets you draw over any app and ask Claude about what you drew. Buttons: Not Now, Turn On |
| The same, where Codex is installed and Claude Code can't answer (`ResponderStatus.namedAgent`) | Try Live Ink. Holding *pair* lets you draw over any app and ask Codex about what you drew. Buttons: Not Now, Turn On |

What leaves the Mac (`SetupInkCopy.costNote`) is a line on setup's live ink permissions page and in
the note's prompt until the first ask. It names the agents that can answer.

| Agents that can answer | Words |
| --- | --- |
| Claude Code, or neither | When you ask, Claude sees a picture of each window you drew on, with its title and URL, through your own Claude Code. An ask costs about one to four cents. |
| Codex alone, or Codex before its sign-in where Claude Code can't answer | When you ask, Codex sees a picture of each window you drew on, with its title and URL, through your ChatGPT account. An ask counts toward your plan's usage limit. |
| Both | When you ask, Claude or Codex sees a picture of each window you drew on, with its title and URL. An ask to Claude costs about one to four cents. One to Codex counts toward your ChatGPT plan's usage limit. |

Setup's live ink pages name Codex where Codex is installed and Claude Code can't answer
(`ResponderStatus.namedAgent`), and Claude elsewhere. The guide's label is Start here beside
Accessibility's Allow…, and Then this beside Screen Recording's Allow… and Sign In to Codex….

| Where | Words |
| --- | --- |
| The live ink page, under the line about drawing (`SetupInkCopy.askLine`) | Then ask Claude about it, or send it to a Claude Code or Codex session. On that Mac: Then ask Codex about it, … |
| Screen Recording's reason on the permissions page (`SetupInkCopy.screenRecordingReason`) | So Claude can see the window you drew on. On that Mac: So Codex can see the window you drew on. |
| Accessibility's reason on the permissions page | So you can draw while holding *pair*. |
| Under the permissions page while Screen Recording is missing (`SetupInkCopy.reopenNote`) | Once you allow Screen Recording, macOS asks to quit and reopen Vignette. Setup opens again on this page. |
| Screen Recording's reason once it is allowed, until macOS's window picker question is answered (`SetupInkCopy.pickerQuestionReason`) | macOS has one more question about the screen. |
| Under the permissions page in that state (`SetupInkCopy.pickerQuestionNote`) | macOS asks this question the first time Vignette looks at the screen. Allow lets Claude see the window you drew on. On that Mac: … lets Codex see … |
