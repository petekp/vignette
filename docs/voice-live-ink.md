# How live ink speaks

Live ink's messages, written to the rules in [voice.md](voice.md). Change a message here and in the
code together.

The menu bar menu names the switch as the General tab does.

| Where | Words |
| --- | --- |
| The menu's switch, with a badge | Live Ink, badge "Hold *pair*" |
| The menu, while live ink is on, greyed out with no marks | Clear Live Ink |
| The General tab, under the switch while Accessibility is missing and the double tap is not asking for it (`liveInkAccessibilityReason`) | Needs Accessibility permission. Lets Vignette notice *pair* held down in any app. |
| The menu's first item while Accessibility is missing | Allow Accessibility for Live Ink…, or for the Shortcut and Live Ink… when the double tap needs it too |
| The menu bar intro's popover, while Accessibility is missing | Live ink needs Accessibility. Click the icon to allow it. (The shortcut and live ink need Accessibility, when both do.) |
| The General tab, under the switch while Screen Recording is missing (`liveInkScreenRecordingReason`) | Needs Screen Recording permission. Lets Vignette see the window under your ink when you ask about it. macOS may ask you to reopen Vignette after you allow it. |
| The menu's first item while Screen Recording is missing | Allow Screen Recording for Live Ink… |
| The menu bar intro's popover, while Screen Recording is missing | Live ink needs Screen Recording. Click the icon to allow it. |
| The note's placeholder, with Claude or Codex as its target (`NoteContent.askPlaceholder`) | Ask about this |
| The same, until the first ask to that agent (`NoteContent.firstAskPlaceholder`) | Ask about this. *agent* sees the window's picture, title and URL. |
| The note's placeholder, with a session as its target (`NoteContent.sendPlaceholder`) | Send to session |
| The note's placeholder with Claude as its target, Claude's row in the target menu under its name, and setup's live ink page in place of its line about asking Claude, when Claude Code is not found (`LiveResponder.Availability.problem`) | Vignette couldn't find Claude Code. You can send your ink to a session. |
| The same, when Claude Code is signed out | Claude Code isn't signed in. You can sign in by running claude in Terminal. |
| The note's placeholder with Codex as its target, and Codex's row in the target menu, greyed out, under its name, when Codex is not found | Vignette couldn't find Codex. You can send your ink to a session. |
| The same, when Vignette's Codex home is not signed in (`CodexDriver.signedOut`) | Codex isn't signed in for live ink. You can sign in in Settings. |
| The same, when Codex's process could not start | Vignette couldn't start Codex. |
| The same, when the isolation check found tools | This version of Codex starts with tools, so live ink can't use it. |
| The same, when Codex rejected a switch that turns its tools off (`CodexDriver.reason(forError:)`) | This version of Codex can't turn its tools off, so live ink can't use it. |
| Added after any of the reasons above, when the other agent can answer (`Target.problem(of:among:)`) | *other* can answer instead. For example: This version of Codex starts with tools, so live ink can't use it. Claude can answer instead. |
| The note's placeholder, with speech on and its permission missing (`LiveInk.speechNotice`) | Speaking needs the microphone and speech recognition. You can allow them in System Settings. |
| The note's placeholder, when speech could not start | The reason it gives: This Mac can't turn speech into words on its own yet. / Speech recognition isn't available right now. / Vignette couldn't find a microphone. / Vignette couldn't start the microphone. / Vignette couldn't start listening. |
| Beside the pointer, as the pointer field comes up without Screen Recording (`LiveInk.screenRecordingNotice`) | Live ink needs Screen Recording to see the window under your ink. You can allow it in System Settings. |
| The note's Return hint, ↩, and its tooltip | Return asks |
| The last of a reply's buttons (`LiveAnswerActions.replyTitle`) | Reply |
| The field Reply opens, empty | Reply to *agent* |
| The button beside that field (`LiveAnswerActions.cancelTitle`) | Cancel |
| The General tab, under the speech switch while a permission is missing (`liveInkSpeechReason`) | Needs microphone and speech recognition permission. Lets Vignette hear what you say while you draw. The words are made on this Mac. |
| macOS's microphone prompt (`NSMicrophoneUsageDescription`) | Vignette hears what you say while you draw, and turns it into words on this Mac. |
| macOS's speech recognition prompt (`NSSpeechRecognitionUsageDescription`) | Vignette turns what you say while you draw into words, on this Mac. |
| The note's target, and its tooltip | *agent* ⌄, "*agent* answers on the screen.", or why it can't answer / *title* ⌄, whose tooltip is the row's title, its second line and its repository |
| The target's menu | Claude, on the screen; Codex, on the screen, unless Vignette found no Codex; then the sessions under a heading for each repository, "Other folders" last |
| The search field, the first row of both target menus | Search sessions |
| The row when what was typed matches no session | No session matches |
| Below the five rows, in both target menus, once more than five sessions are active: one submenu per project, after a separator | The project's header text, with the number of its sessions as a badge |
| A session's row in the target menus | The herdr tab's label without a leading "*repository*:", else the session's name. Under it: the worktree, the branch when it is not the default, and the session's goal from the inbox mod, or its name when that adds to the title. A folder with no repository shows its path from home. A row with no herdr tab and no goal shows the session's name, then its worktree, subfolder, branch and how long ago it was used |
| The badge on a row | Needs you (the inbox mod has an open question for you), else Working (a turn is running) |
| Two rows in one group with the same title | The title and, in parentheses, the first of the herdr tab, the worktree and the branch that tells them apart, else #1 and #2 by when they started |
| The destination control in the bar | The row's title; its tooltip is the title, the second line and the repository |
| The destination control when no session runs and some can be started (`ToolbarView.chooseSession`) | Choose a session; its tooltip: No session is running. You can continue a past one or start a new one. |
| A project's rows when it has no running session (`SessionMenu.continueLast`, `newSession`) | Continue last session, under it the worktree, branch, the session's name and how long ago it was used / New session, under it the worktree and branch |
| The destination control, and the note's target, once a row of a project with no running session is picked (`SessionMenu.lastSession(in:)`, `newSession(in:)`) | Last session in *project* / New session in *project*; the tooltip keeps the menu row's words |

*agent* is the note's target, Claude or Codex, and *other* is the agent that is not.

## Codex's sign-in

Codex answers live ink on a Codex home of Vignette's own, which signs in once through Codex's
browser login. The row is in the General tab under Live ink while Codex is installed, and on setup's
live ink permissions page while Codex is installed and Claude Code can't answer (`CodexSignInRow`).

| Where | Words |
| --- | --- |
| The row, while that home is not signed in (`CodexSignInRow.line`) | Codex can answer live ink after a sign-in of its own, apart from the Codex app's. Button: Sign In… in the General tab, Sign In to Codex… in setup |
| The row, while the browser's sign-in page is open (`CodexSignInRow.waiting`) | You can finish signing in in your browser. Button: Cancel |
| The row, once signed in (`CodexSignInRow.signedIn`) | Signed in to Codex. Button: Sign Out, in the General tab only |
| Under the line, when port 1455, where Codex's sign-in waits for the browser, is taken (`CodexLogin.portTaken`) | Another sign-in to Codex may be open. You can try again once it's done. |
| Under the line, when Codex could not start the sign-in (`CodexLogin.couldNotStart`) | Vignette couldn't start the sign-in to Codex. You can try again. |
| Under the line, when the browser's sign-in failed or was not done in 10 minutes (`CodexLogin.notSignedIn`) | The sign-in to Codex didn't finish. You can try again. |

## In the conversation's row, or on the ink

Vignette's own words about an ask. With the conversation up, they go in its row after the name, and
a reason whose subject is the answerer goes on from the name: **Claude** couldn't answer. You can ask
again.
Without one, they are a note beside the ink it was about, in the person's colour.

| When | Words |
| --- | --- |
| A session did not take the note | Not sent. Then the reason, as on a card. |
| No Screen Recording | Live ink needs Screen Recording permission to see the screen. |
| The capture failed | Vignette couldn't see the screen. / Vignette couldn't capture the window. |
| No `claude` found | Vignette couldn't find Claude Code. You can send your ink to a session. |
| Claude Code is signed out | Claude Code isn't signed in. You can sign in by running claude in Terminal. |
| The usage limit | Claude's usage limit is reached for now. |
| No answer in 45 s | Claude took too long to answer. You can ask again. |
| The answer did not parse | Vignette couldn't draw Claude's answer. You can ask again. |
| Anything else | Claude couldn't answer. You can ask again. |
| The CLI started with tools | Live ink stopped Claude, which started with tools. |

With Codex answering, the rows after the capture's are Codex's own.

| When | Words |
| --- | --- |
| No `codex` found | Vignette couldn't find Codex. You can send your ink to a session. |
| Codex could not start, for no reason below | Vignette couldn't start Codex. |
| Vignette's Codex home is not signed in | Codex isn't signed in for live ink. You can sign in in Settings. |
| Codex rejected a switch that turns its tools off | This version of Codex can't turn its tools off, so live ink can't use it. |
| The usage limit | Codex's usage limit is reached for now. |
| No answer in 45 s | Codex took too long to answer. You can ask again. |
| The answer did not parse | Vignette couldn't draw Codex's answer. You can ask again. |
| Anything else | Codex couldn't answer. You can ask again. |
| The isolation check found tools | Live ink stopped Codex, which started with tools. |

## What VoiceOver reads

| Element | Label |
| --- | --- |
| The note's field (its placeholder is read after it) | Note |
| The note's target | Goes to Claude / Goes to Codex / Goes to *title* |
| A reply's question | Your question |
| A reply's answer | Answer |

The note's ↩ hint and a reply's logo are hidden from VoiceOver, since the field and the name beside the
logo say the same.

