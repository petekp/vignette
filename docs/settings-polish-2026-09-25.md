# Setup and Settings (2026-09-25)

Status: approved 2026-09-25 ("looks great. please proceed with implementing everything"). Built
the same day and not committed. "Verified" below says what has been checked and what still needs
the screen. Pete, 2026-09-25: "let's mock up alternative setup and settings views.
we want to balance following the Apple HIG with doing what's right for our particular product … our
target outcome is making it as elegantly simple and easy to understand as we can." This replaces the
earlier list of eleven fixes. Each of those fixes is now a row in the element review below. The agent
skill in setup is approved separately (`docs/setup-agent-skill-2026-09-25.md`) and appears in every
setup mockup.

An adversarial review the same day changed decisions 2, 5 and 6, and found four gaps the first
pass missed. "Found in review" below lists them. Decision 1 then moved to pages. Pete: "don't you
think setup A is way too much info at once??"

## Recommendation

- **Setup is pages, one step each (Setup B).** Welcome, with Desktop access when macOS will ask
  for it and Open at login. Then the shortcut, with Accessibility and Try it. Then the agents, only
  when Claude Code or Codex is installed.
- **Settings keeps its three tabs, regrouped (Settings A).** General covers how you reach Vignette
  and what the recent screenshots do. Screenshots covers what happens to a new capture. Agents is
  one switch per agent.
- **The shortcut is a pop-up menu.** It lists double taps in words ("Press Right Shift Twice") and
  ends with Key Combination…, which shows a recorder labelled Keys. macOS's own Dictation and Siri
  shortcut settings work this way.

## Decisions for Pete

| # | Question | Recommended | Other option |
|---|---|---|---|
| 1 | Setup layout | B: pages, one step each | A: one window |
| 2 | Shortcut control | A pop-up of double taps and Key Combination… | One recorder that takes both |
| 3 | Settings layout | A: three tabs, regrouped | B: one pane, no tabs |
| 4 | The Desktop prompt | Setup asks for it | Default to a folder macOS doesn't protect |
| 5 | macOS's own "Save to" choice | Follow it while running; then remove "Save macOS screenshots here" | Remove the switch now |
| 6 | How many screenshots the stack shows | Keep the field and stepper, relabelled | A menu of 10 to 100 |

1. **Pages.** The one window asks for two permissions, a shortcut and an agent choice at once:
   seven controls and five lines of explanation, with two Allow… buttons. A page asks one thing,
   and the shortcut page has room for a picture of the key. The cost is two more clicks. The page
   dots show how many steps there are.
2. **A pop-up.** Today the shortcut is two controls: a switch between "Double-tap Right Shift" and
   "Key combination", then a recorder with no label. The first proposal was one recorder that also
   takes a modifier tapped twice. It hides the double tap: someone who records a combination has to
   know that tapping a modifier twice is also an answer. macOS solves the same problem in its
   Dictation and Siri settings with a pop-up: "Press Right Command Key Twice" and similar, then
   Customize. The pop-up names each double tap in words and can offer every modifier
   `HotKeySpec.modifierCodes` parses. Once a combination is chosen, the pop-up reads "Key
   Combination", without the ellipsis, and the Keys row holds the recorder.
3. **Three tabs.** The one pane is 836 points tall. A 13-inch MacBook Air's screen is 900 points
   (M1) or 956 points (M2 and later) tall at its default setting, before the menu bar and the Dock.
   The tabs keep each view whole and are the macOS Settings pattern.
4. **Setup asks for Desktop.** Today macOS's "access files in your Desktop folder" prompt comes up at
   launch, over the setup window, before anyone asked. The watcher waits to open or list a protected
   folder (Desktop, Documents, Downloads) until setup's first row asks. The other option, a default
   folder macOS doesn't protect such as `~/Pictures/Screenshots`, needs no prompt but moves where
   screenshots are saved. The conditions this needs are under "Found in review".
5. **Follow macOS's choice first.** Vignette reads macOS's save location only at launch:
   `Settings.reconcileApple` writes Vignette's folder back when they differ, and nothing watches the
   location while the app runs. Someone who picks another folder in ⌘⇧5's Options menu gets no
   cards until the next launch, and that launch undoes their choice without a word. "Save macOS
   screenshots here" is the only way to stop that revert. When Vignette follows the location
   instead, taking macOS's choice as its own folder, the switch has no job left and can go.
6. **Keep the stepper.** The fault was the label, which read as if older screenshots get deleted.
   A menu of five values also breaks stored values: `recentCount` holds any number from 1 to 100,
   and a 37 would show as an empty pop-up.

## The mockups

The render harness draws each mockup with the app's own SwiftUI and AppKit controls, offscreen, in
light and dark. It never orders a window in, so every window draws as an inactive window: grey
window buttons, and on switches in grey instead of the accent colour. The mock views live in the
session's scratchpad (`render/mocks.swift`), not the repo.

| Mockup | States rendered |
|---|---|
| Setup | Welcome with the Desktop row and Open at login; the shortcut; the shortcut after allowing, with Try it; agents |
| Settings | General; Screenshots; Agents; General with a key combination and no menu bar icon; Screenshots with the folder refused; Agents after a failed install |
| Menu bar menu | The proposal, with the double tap as the shortcut. Drawn to match a macOS menu, since macOS draws real menus itself. |

The page shows the recommended option for each decision. The Screenshots tab shows the end state
of decision 5, with "Save macOS screenshots here" gone.

## Found in review

- **The folder step assumes Desktop.** The first launch takes macOS's current save location as
  Vignette's folder (`SettingsData.fromSystem`), which can be any folder: Pete's is
  `~/Dropbox/Screenshots`. The row appears only when macOS will ask about that folder, which it
  always does for Desktop, Documents and Downloads and doesn't for a plain folder such as Pete's
  Dropbox. Otherwise the welcome page has no folder row, and Try it shows the user their own screenshots,
  which is better proof that Vignette found the folder than a line naming it. A Dropbox kept by
  macOS under `~/Library/CloudStorage` may also ask; that is unverified.
- **Waiting for the folder has three loose ends.**
  - Closing setup without pressing Allow starts the watcher then, and macOS asks with no window
    open.
  - Setup's "take a screenshot first" check reads the watcher's index, which stays empty while the
    watcher waits. It has to wait for the folder too, or "Try it" asks for a screenshot the user
    already has.
  - Which call raises the prompt is unmeasured: `open(O_EVTONLY)` in `ScreenshotWatcher.start`,
    or the first listing. Both have to wait.
- **A refused folder shows only in setup.** `ScreenshotWatcher.isDenied` is read by the setup
  window and nothing else. If macOS's permission is turned off later, Vignette goes silent and
  Settings doesn't say why. The Save to row shows it, with a button to Privacy & Security.
- **The thumbnail time applies with "Open it to draw" on.** A lone thumbnail that comes back from
  the editor without a copy, after Send for example, stays `thumbnailSeconds`
  (`ThumbnailController.swift:997`). The row stays visible. It also stays a slider, since a menu
  of presets would show a stored 7 as an empty pop-up.

## What setup answers

The user's questions during setup, walked through on 2026-09-25. Setup answers four of them: the
user has the question at the moment of choosing, and nothing on screen answers it yet.

- **"Why does it need my Desktop?"** The folder row states a permission, "Vignette needs access to
  your Desktop", which raises the question before macOS's prompt can answer it. The line under it
  says why: "macOS saves your screenshots there."
- **"Why does it need Accessibility?"** macOS's alert gives no reason. The permission row says why,
  and that a key combination needs no permission, which is a way through setup without granting it.
- **"How do you hold a double tap?"** The shortcut's caption says to hold the second tap.
- **"Will my agents see my screenshots?"** The agents footer says "drawings you send them".

Left alone:

- **Whether typing capitals sets off the double tap.** It doesn't: any key or click between the taps
  cancels it (`ModifierTap`), and trying it shows that.
- **Where Vignette went after Done.** Its icon is in the menu bar, and the next screenshot shows it
  working. This is the first to add if people lose the app.
- **What "recent screenshots" are.** Try it shows them.
- **The replaced macOS thumbnail, another tool's folder, and what goes in `~/.claude`.** Expected,
  rare, or covered by Settings.

## The blue button

A macOS window has at most one blue button: the default, which Return presses. Setup gives it to
the next step rather than to Done, because the steps are what make Vignette work, and a blue Done
from the start draws the eye past them.

- **Setup.** On a page with a permission still missing, its Allow… carries it and Continue is
  plain. Once it is granted, or the user picks a key combination, Continue does. Done carries it on
  the last page. Continue stays clickable throughout, so no step is forced.
- **Settings.** No blue button: its changes apply as they are made, and a refused permission's
  Allow… stays plain.

The renders draw every window as inactive, where macOS shows no blue, so the mockups draw the blue
button by hand. The app uses a real default button (`.keyboardShortcut(.defaultAction)`), moved as
the steps complete.

## Every element

### The flow

| Element | Now | Issue or opportunity | Proposal |
|---|---|---|---|
| Move to Applications alert | "Move Vignette to Applications?" with Move to Applications and Quit | None. An app running from the disk image cannot open at login, so Quit is the honest other choice. | Keep. |
| Desktop prompt | macOS asks at launch, over the setup window | A question with no context, which people deny | Setup's first row asks for it (decision 4). |
| Setup activates the app | Yes, on the first launch only | Correct. The permission dialogs have to come up in front. | Keep. |
| Skill offer on the second launch | Opens Settings at Agents without being asked | A window nobody asked for, a day later | Setup covers it (approved plan). The offer stays only for installs that reached their second launch before this ships. |
| Getting back to Settings with the icon hidden | `open vignette://settings` in Terminal | A developer command in a user caption | Opening Vignette again opens Settings (`applicationShouldHandleReopen`). |
| macOS's own Save to choice | Ignored while running, undone at the next launch | The user's choice in ⌘⇧5 silently loses | Follow it (decision 5). |
| Menu bar menu | Show Recent Screenshots, Draw on Last Screenshot, two switches, Settings… | Two items name settings differently from the Settings window | See "Menu bar menu" below. |

### Setup window

| Element | Now | Issue or opportunity | Proposal |
|---|---|---|---|
| Layout | One form: sentence, shortcut, login and folder | Every question at once | Pages, one step each (decision 1). Back, the page dots and Continue along the bottom. The dots sit on the window's centre line, laid over the buttons rather than between them, so Back appearing on page 2 doesn't move them. |
| Title bar | "Welcome to Vignette" as the window title; the content starts with a sentence | Reads as a settings form rather than a first meeting | Transparent title bar. Each page has a picture, a heading and one line: the app icon and "Welcome to Vignette", the key and "Tap Right Shift twice", the agents' logos and "Your coding agents". |
| Intro line | "Cmd+Shift+3, 4 and 5 still take the screenshot. Vignette handles what comes after." | The first half is the right fact: you keep your keys. "What comes after" says nothing. | "Take screenshots with ⌘⇧3, 4 or 5, as before. Vignette keeps the recent ones one shortcut away, ready to draw on." It doesn't name the shortcut, since the user can change it a few rows below. |
| Screenshots folder | A read-only row showing `~/Desktop` | Shows a path the user can't act on. It is a permission, not a choice of folder: the folder is macOS's, and the row exists only because macOS protects it. | The first step, only when macOS will ask, in the same form as the Accessibility row: "Vignette needs access to your Desktop", with "macOS saves your screenshots there." under it and Allow…, which raises macOS's prompt. Granted, it reads "Vignette has access to your Desktop" with a check. Earlier drafts, "Read new screenshots" and "Screenshots folder" with Allow Access…, read as an instruction and as a place to pick a folder. |
| Folder not readable | A warning line and a button, two more rows | The layout jumps | The same row, with a warning symbol: "Vignette doesn't have access to your Desktop". Allow… opens Privacy & Security, since macOS doesn't ask twice. |
| Shortcut | Two-way switch; the recorder on an unlabelled row | Two controls for one setting | The pop-up (decision 2). |
| Shortcut caption | "Shows your recent screenshots. Hold it to draw on the newest one." | The only place the hold is taught, and with a double tap it doesn't say which press to hold | With a double tap: "Shows your recent screenshots. Hold the second tap to draw on the newest one." With a key combination it keeps "Hold it". In Settings it is the section's footer, since beside the wide pop-up a caption under the title got half the row (changed 2026-09-26). In setup it is the page's line under the heading. The Shortcut row has no caption in either. |
| Accessibility | A lock and a sentence, then the button on its own row | Three rows for one step. macOS's alert says Vignette wants to "control this computer" and gives no reason. | One row under the shortcut: "Needs Accessibility permission", with Allow… beside it and under it "Lets Vignette notice the double tap in any app. A key combination doesn't need it." |
| Try it | The status line changes in place; only its symbol is tinted | It is where the user learns the gesture | Keep, in the permission row's place, with only the symbol tinted. |
| Launch at login | A switch in a section with the folder | "Launch" is not Apple's word; macOS says "Open at Login" | "Open at login", a switch on the welcome page, on by default. It is about Vignette itself, which is that page's subject, and it lets the agents page drop out when no agent is installed. |
| Agents | None; the offer waits for the second launch | Approved to move here | The last page, only when Claude Code or Codex is installed. A switch per agent with the vendor's logo, on by default. Line under the heading: "Adds a skill that lets your coding agents show you images and reply to drawings you send them." "Drawings you send them" says the user decides what the agents see. |
| Done | Default button from the start | Draws the eye past the steps | Default on the last page only. See "The blue button". |

### Settings: General

| Element | Now | Issue or opportunity | Proposal |
|---|---|---|---|
| Toolbar and tabs | General, Screenshots, Agents | None. It is the macOS Settings pattern. | Keep. |
| Shortcut | As in setup | As in setup | The pop-up, the same row as setup. |
| Accessibility | The sentence sits in the label column and wraps to two lines | Reads as a label, not a problem | The row setup uses, with the same line under it, and a warning symbol, since here the shortcut doesn't work. Setup uses a lock, since there it is a step. |
| Keep recent screenshots | A field and stepper, 1 to 100 | Reads as if older screenshots get deleted | The same control, relabelled, in a "Recent screenshots" section (decision 6). |
| Show a new screenshot for | A slider, 2 to 15 seconds, with 14 ticks | It sits in General, away from the thumbnail it times | Moves to Screenshots, under "After a screenshot", as "Show the thumbnail for", always visible. |
| When you finish drawing | On the Screenshots tab, two radio rows | See Screenshots | "Close after copying a drawing", a switch, off by default. It also drops any screenshots queued for drawing (`endQueue`), as "Copy and close" does today. |
| Launch at login | A switch | Apple's word is "Open" | "Open at login". |
| Show in menu bar | Caption, while off: "Reopen Settings with open vignette://settings in Terminal." | Terminal | Caption while off: "Open Vignette again to get back to Settings." |

### Settings: Screenshots

| Element | Now | Issue or opportunity | Proposal |
|---|---|---|---|
| Save to | `~/Desktop` in grey, then Choose… | A path and a button for one choice. A refused folder isn't shown. | A pop-up like the Save to menu in macOS's own ⌘⇧5 Options: the current folder with its icon, Desktop, Documents, Other…. It shows when macOS refused the folder. The mockup's `NSPathControl` lists every parent folder in its menu, so one wrong pick would watch `/Users`, and it draws unlike the Format pop-up. |
| Save macOS screenshots here | A switch | Its only job is to stop Vignette undoing macOS's Save to choice | Remove it once Vignette follows that choice (decision 5). |
| Format | PNG or JPEG | macOS has no control for it | Keep. |
| Shadow on window screenshots | A switch | macOS has no control for it | Keep. |
| Copy to the clipboard | A switch under "After a screenshot" | None | Keep. |
| Open it to draw | A switch, "Instead of showing a thumbnail." | None | Keep. The thumbnail time follows it. |
| When you finish drawing | Two radio rows: Return to the stack, Copy and close | Names the wrong moment. It applies when you copy a drawing, not on Esc or Send. It also spends two rows on a yes or no. | Moves to General as a switch. |
| Original screenshot settings | A "macOS" section; Restore… with a three-line caption | A heading for one row, and a long caption | "macOS screenshot settings" with Restore…, and the footer "Vignette replaces the macOS thumbnail. Restore puts back the thumbnail and the folder, format and shadow macOS used before." |

### Settings: Agents

| Element | Now | Issue or opportunity | Proposal |
|---|---|---|---|
| Description | Its own boxed row | Looks like a setting. Doesn't mention replies. | The section footer, the same line as setup. It names "your coding agents", since this tab has no heading for "them" to point at. |
| Agent rows | Name, a status mid-row, Install or Remove | Three things per row for one on or off state | A switch per agent with the vendor's logo, which the app already draws on cards. Off deletes whatever is at `<root>/skills/vignette`, as Remove does today, including a copy installed another way. |
| A failed install | A toast, "Couldn't install the skill for Codex", which leaves no trace | The reason is only in the log | The switch flips back, and a line under the agent's name says why, from the installer's error. |
| Empty state | "No coding agent found on this Mac. Vignette looks for Claude Code and Codex." | None | Keep. |
| Developer tab | Debug builds only | None | Keep. |

### Menu bar menu

| Element | Now | Issue or opportunity | Proposal |
|---|---|---|---|
| Show Recent Screenshots | The shortcut as a badge, "double-tap Right Shift", or as a key equivalent for a combination | None | Keep. |
| Draw on Last Screenshot | Badge "hold double-tap Right Shift" | "Last" where the shortcut's caption says "newest", and a badge that doesn't say which press to hold | "Draw on Newest Screenshot", badge "hold the second tap". A combination keeps "hold ⇧⌘6". |
| Copy New Screenshots, Draw on New Screenshots | Two switches | Settings names the same two "Copy to the clipboard" and "Open it to draw", under "After a screenshot" | The same heading as a section header, "After a Screenshot", with "Copy to Clipboard" and "Open to Draw". The menu already uses a section header for Developer. |
| Open Screenshots Folder, Settings…, Check for Updates…, Quit Vignette | As listed | None | Keep. |

## Opportunities not mocked

- **Setup teaches the hold.** Built on 2026-09-25, after Pete asked for more character in "That
  works.". Each fire presses the key picture and turns its ×2 into a green check, and the check in
  the row bounces. The row says "There they are. Now try holding the second tap." (or "holding
  ⇧⌘6"), since the stack has just come up beside the window. After a hold, which posts
  `hotKeyHeld`, it says "That's the whole trick." The caption above already describes the hold, so
  the row asks for it rather than describing it again.
- **The Agents tab could explain Send.** Send lists Claude Code sessions only inside herdr. A Claude
  Code user without herdr sees no Claude Code in the target menu and no reason why. The row could
  say so when herdr isn't installed.
- **The setup header could show the stack.** A short loop from the trailer would show a new user
  what the double tap opens before they try it.

All copy above is draft and goes through `refine-prose` before it ships.

## Not changing

- The Settings window's width and its toolbar.
- The Move to Applications alert.
- The Developer tab.

## Build order

1. **Follow macOS's Save to choice.** `Settings` observes `location` in `com.apple.screencapture`
   through `UserDefaults(suiteName:)` and key-value observing. Measured on a scratch domain, a
   `defaults write` from another process reached the observer in 10 to 35 ms, so no polling. At
   launch Vignette takes macOS's location instead of writing its own back. Picking a folder in
   Vignette still writes `location`. `syncAppleSaveLocation` and its switch go.
2. **The watcher waits for setup.** On a first launch whose folder is inside the Desktop,
   Documents or Downloads, no watcher exists until setup's Allow… or the window closes.
   `recentShots` already answers empty with no watcher, so nothing reads the folder before then.
   A listing refused by macOS counts as denied, as a refused `open` does.
3. **The shortcut pop-up,** shared by setup and General.
4. **The setup pages,** with the agent skill install from `docs/setup-agent-skill-2026-09-25.md`.
5. **The Settings tabs:** General, Screenshots, Agents.
6. **The menu bar menu,** and reopening Vignette opens Settings.
7. **Docs:** `AGENTS.md`, `docs/settings.md`, `docs/using.md`.
8. **Checks,** below.

## Verified

- **Unit tests:** all 394 pass. `testLabelNamesTheKey` now covers the menu's hold badge and the
  keycaps. `testProtectedAreaIsTheDesktopDocumentsOrDownloadsAndWhatIsInside` covers the folders
  setup asks about, including `~/DesktopArchive`, which a plain prefix match would take for the
  Desktop.
- **Renders:** the harness drew the real windows, light and dark, trusted and untrusted, and each
  matched its mockup. Every setup page, with two pages or three, has its dots within half a pixel
  of the window's centre and at the same height. Two differences were fixed: the thumbnail
  slider drew 14 ticks, and the Keys recorder sat a line below its label.
- **Following Save to:** on the demo copy, with its scratch domain, a `defaults write` of
  `location` moved the watcher about 10 ms later. A folder set in the settings file wrote
  `location`, and that write coming back did not move anything.
- **URL commands:** a `vignette-demo://state` sent to the running demo logged no reopen and opened
  no window.
- **Pete's own run of setup, 2026-09-25:** Allow… for the Desktop, after a TCC reset, then
  Accessibility. It found two bugs, both fixed. Setup disappeared behind the previous app when
  macOS's folder prompt was answered. The shortcut page froze for 19 s on iCloud downloads
  (`docs/icloud-files-2026-09-25.md`).
- **Live on the demo copy, overnight 2026-09-26,** with a scratch folder holding one image and the
  shortcut set to a double Right Option, so Pete's own copy on Right Shift could not answer:
  - The welcome page has no folder row for a folder macOS doesn't protect. Continue moved on.
  - On the shortcut page, Continue was the blue default once Accessibility was granted. A double
    tap opened the stack in 63 ms. The ×2 turned into a check, and the line changed to "There
    they are. Now try holding the second tap."
  - A hold opened the editor on the newest screenshot, and the line changed to "That's the whole
    trick."
  - With Codex's switch turned off, Done logged `skill=none`. Nothing was written to `~/.codex`,
    and the settings file recorded `setup` done and `agentSkill` off.
  - Opening the running app again logged `[app] reopened` and showed Settings. The window opened
    with "How many to show" focused and its number selected, which the mockups don't show. It now
    opens with nothing focused.
  - The menu bar menu matched its mockup.
  - Save to's pop-up listed the current folder, Desktop, Documents and Other…. Other… opened a
    folder panel at the current folder. Choosing another folder there moved the setting, the
    scratch domain's `location` and the watcher.
- **Still not checked:** an Agents switch, since the demo sees Pete's real `~/.claude` and
  `~/.codex`, and setup installing the skill for the same reason. The CloudStorage Dropbox prompt
  is still unverified.

## Checks

- Setup B's page dots sit on the window's centre line on every page, with or without a Back button
  and whatever the buttons' widths: laid over the button row, not between the buttons. Measured in
  the mockup, the dots' centre is within half a pixel of the window's on every page. The build
  is measured the same way, from a render of each page.

- Unit tests, `scripts/build.sh --test`.
- The harness renders every window again, light and dark, trusted and untrusted, and each change is
  compared with its mockup.
- The flow on the demo copy with a fresh scratch settings file, which opens the setup window. The
  skill install runs with a scratch `HOME` if the app follows it, and otherwise waits for Pete's
  go-ahead. The Desktop prompt needs the demo watching a protected folder, and a TCC reset for the
  demo's own bundle id only: `tccutil reset SystemPolicyDesktopFolder com.petepetrash.vignette.demo`.
- The folder prompt for a Dropbox kept under `~/Library/CloudStorage`, on a Mac or account that
  has one, since this Mac's Dropbox is a plain folder.
- Following macOS's Save to choice: change the location the way ⌘⇧5's Options menu does, on the
  demo's scratch settings, and confirm the demo moves its watch and the next launch keeps the
  choice. It must not touch Pete's real `com.apple.screencapture` defaults. The demo writes those
  same defaults, so this check needs a way to aim it at a scratch domain first, or waits for Pete.
