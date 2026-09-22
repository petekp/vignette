# First-run shortcut setup

Built 2026-09-21. The goal was that a new user chooses the shortcut before anything asks for a
permission, and that double-tap Right Shift is what they choose.

What shipped differs from the plan below in one place: `ModifierTap` gained no `onTrusted`
callback. The window polls `AXIsProcessTrusted` once a second while it is open instead, which keeps
the window's business in the window rather than threading a callback through AppDelegate's tap.

## The trap

Changing `recentHotkey`'s default to `"double-rshift"` on its own makes things worse, not better.

`registerHotKey()` runs during launch. With a double-tap spec it builds a `ModifierTap`, whose
`init` calls `trusted(prompt: true)` (`ModifierTap.swift:41`). So the macOS Accessibility dialog
would appear seconds into the first launch, before the user has seen the app, chosen anything, or
learned what a shortcut is for. That is the dialog people dismiss.

macOS gives an app a limited number of chances at that dialog. Spend it once, on a question the
user just asked.

So the permission prompt has to move out of launch and into the moment the user picks the double
tap. Construct the launch-time `ModifierTap` with `prompt: false`; let the setup window be the only
thing that passes `true`.

## Why a window and not the Settings window

The Settings window already has the whole shortcut control: the segmented picker, the recorder, the
"Needs Accessibility permission." caption and the Open System Settings button
(`SettingsWindow.swift:205-225`). Opening it at General on first launch is the cheap move, and the
agent-skill offer already sets that precedent (`AppDelegate.offerAgentSkill`).

It is not enough, because a settings form cannot do the two things that decide whether the grant
sticks:

- **Say when it worked.** Today the user walks to System Settings, flips a switch, and comes back
  to nothing. `ModifierTap` polls every two seconds and installs itself the moment trust appears
  (`ModifierTap.swift:44-50`), so the app knows. It only writes a log line.
- **Let them try it once.** The shortcut is muscle memory. A user who taps Right Shift twice and
  watches the stack slide in has learned the product. A user who closes a settings pane has not.

One window, one screen. Not a wizard: three steps of chrome would contradict an app whose pitch is
three tools and no colour picker.

## The flow

1. First launch opens the setup window, centred, app activated. It replaces the current first-launch
   toast (`AppDelegate.swift:100`), which says the watch folder and that launch at login is off.
2. One line on what Vignette does, then the shortcut control with **Double-tap Right Shift**
   preselected.
3. Status line under it, which changes in place:
   - untrusted: "Needs Accessibility permission." plus the Open System Settings button
   - trusted: "Try it: tap Right Shift twice."
   - after the hotkey fires once: "That works. You're set."
4. Footer: a Launch at login checkbox, the watch folder as a line of text, and Done.

Picking Key combination instead swaps in the recorder and drops the permission line. That path needs
no permission and no confirmation step, so Done is immediately available.

The confirmation triggers on the hotkey **firing**, not on the stack appearing. On a fresh Mac the
watch folder may hold no screenshots, and the stack would come up empty; the window should still say
it worked, and can add that the stack fills as you capture.

## What to build

1. `recentHotkey` default becomes `"double-rshift"` (`Settings.swift:29`).
2. `ModifierTap(prompt:)`, defaulting to `false`. `AppDelegate.registerHotKey` passes nothing; the
   setup window passes `true` when the user picks the double tap.
3. `ModifierTap` gains an `onTrusted` callback fired where it currently logs
   "Accessibility granted; modifier tap active".
4. Extract the shortcut rows from `SettingsView.general` into a view both it and the setup window
   use, so there is one shortcut control, not two.
5. A `setup` key in settings.json in the shape of `agentSkill`: `unasked`, then `done`. Recorded as
   the window opens, so the question is asked once whatever the user does. `settings.firstLaunch` is
   not enough on its own, since it is true only for the run that creates the file, and a user who
   quits mid-setup would never see it again.
6. The setup window suppresses the agent-skill offer for that launch, so two windows never compete
   for a first-time user. The offer comes on the next launch.

## Fallback when the user walks away

A user who closes the window having chosen the double tap without granting has no working shortcut.
The menu bar item still opens the stack, and Settings General still shows "Needs Accessibility
permission." with its button.

Registering Cmd+Shift+6 as a temporary second hotkey until trust arrives would close that gap. It is
machinery for a transient state, and it means the shortcut a user was taught is not the one that
works. Not proposed.

## Verified 2026-09-21

Against a real untrusted state (`tccutil reset Accessibility com.petepetrash.vignette`, relaunched
through `open` so the app did not inherit the terminal's trust):

- No Accessibility dialog during launch.
- The untrusted status line and its button render, and the window grows to fit them.
- **The button does not raise the dialog, and that is fine.** macOS suppresses it for a bundle id
  that has prompted before, so what `trusted(prompt: true)` actually buys is the entry in the
  Accessibility list: without it the pane opens with nothing for the user to switch on. The plan's
  claim that the dialog is the shorter route holds only on a Mac that has never prompted.
- Granting in System Settings flips the status line to "Try it" within a second, and `ModifierTap`'s
  own retry installs the monitors (`[hotkey] Accessibility granted; modifier tap active`).
- A real right-Shift double tap then reaches the app and the line becomes "That works. You're set."

Still unverified: what a Mac that has never prompted for this bundle id does, which is every new
user. That needs a fresh macOS install or a VM.
- The grant survives a rebuild only with a real certificate. See [building.md](building.md); an
  ad-hoc build is a new app to macOS on every build, so test the flow on a signed build.
