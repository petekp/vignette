# Setup, the disk image and updates

- The first launch opens the setup window (`SetupWindow.swift`), and it has that launch to itself.
  It is pages, one step each: welcome, with the folder permission when macOS protects the watch
  folder, and Open at login; the shortcut; live ink; and the agent skill, only when `~/.claude` or
  `~/.codex` exists. Its main job is the shortcut, whose default, `double-rshift`, needs
  Accessibility. Nothing else may raise that dialog: `ModifierTap` is constructed with
  `prompt: false`, so the only
  `trusted(prompt: true)` in the app is `Accessibility.request()`, which runs from a button the user
  pressed: this window's shortcut and live ink pages, the Settings window's shortcut row (General) and live ink
  rows (Live Ink), and the status menu's Allow Accessibility for the Shortcut, Live Ink or both. A dialog raised
  during launch, on a question nobody asked, is the one people dismiss. For the same reason, macOS 15's window
  picker question comes from the Screen Recording row's Allow… after the reopen, not from the
  reopen itself (`PickerQuestion`, `docs/live-ink-setup.md`). `request()` raises macOS's
  own alert and nothing else, and opens the pane itself only when no `universalAccessAuthWarn`
  window is up 1.5 s later (measured: the alert came up within half a second). Opening both at
  once put the pane in front of the alert, which then waited behind it and outlived the grant. A
  press while the alert is up brings the alert to the front, since any window can cover it:
  Vignette yields its activation to the alert's app and activates it (`bringForward`). It does not
  ask again, which would queue a second alert behind the first. The window learns the grant landed
  by polling (AXIsProcessTrusted announces nothing), comes back to the front then, since System
  Settings was covering it, and learns the shortcut works from the `.hotKeyFired`
  notification, which `registerHotKey`'s `fire` posts: the keys firing is what proves the setup
  worked, since the stack appearing does not on a Mac with no screenshots yet. Each fire turns the
  key picture's ×2 into a check, and the line then asks for the hold, which posts `.hotKeyHeld`.
  A modifier's keycap in the picture goes down while that key is held (`HeldModifiers`), so the
  picture responds to the keys before Accessibility is granted: a local monitor hears them while
  setup is key, and a global one everywhere once the app is trusted. A combination's own key never reaches the window,
  since the hotkey takes it, so its firing presses the picture. That same poll reads
  the watch folder's count, and an empty folder asks for a capture first, ahead of the fired state:
  a tap with nothing to show opens nothing, so reporting success would report it about an empty
  corner. The two menu items that act on a screenshot, Show Recent Screenshots and Draw on Newest
  Screenshot, are greyed out while the folder is empty (`validateMenuItem`), which is the rest of
  that silence: both used to answer only in the log. `setup` in
  settings.json records `unasked` then `done`, written when the window closes rather than when it
  opens, so a launch quit part way through asks again. The permissions belong to the Mac, and a
  settings.json synced by dotfiles carries `done` to a new one, so the app's own defaults keep
  `setupDoneOnThisMac` too, and a file's `done` counts without it only where an earlier launch left
  the Application Support folder, as every release did (`SetupWindowController.isUnasked`). A test
  launch goes by its scratch file alone. `ShortcutSetting` is the one shortcut
  control, shared with the Settings window's General tab: a pop-up of double taps, then Key
  Combination…, which shows a recorder that starts listening at once. A new settings file starts with
  `launchAtLogin` on: first run turns Apple's thumbnail off, so a restart that does not bring
  Vignette back leaves every capture silent. The window shows the switch and saves it when it
  closes, with setup's other choices. The login item is registered then too, not as the launch
  starts. When the menu bar intro plays, the registration waits for the intro to go, since macOS
  announces a new login item in the corner the intro points at. A login item the person
  removed under Open at Login reads `.notFound` (measured), and a launch then turns
  `launchAtLogin` off instead of registering it again; a copy that moved is told apart by the path
  it registered from (`LoginItem.removedByPerson`). The folder row is a
  permission, not a choice of folder: it appears only for a folder inside the Desktop, Documents or
  Downloads, its Allow… starts the watcher, whose first read raises macOS's prompt, and a refusal
  turns it into a warning whose Allow… opens Privacy & Security > Files and Folders. The window's one
  default button is the next step still to take: a missing permission's Allow…, then Continue or
  Done. The page dots are laid over the buttons, so they sit on the window's centre line whatever
  the buttons are. The skill page's switches start on, and closing the window installs the ones
  still on, but only for someone who reached that page: closed earlier, `agentSkill` stays
  `unasked`, and the next launch offers the skill in the Settings window instead. The Setup Lab
  (`SetupLab.swift`, `vignette://setup-lab`, needs `debug`) runs setup as a new person sees it, all
  of it or live ink's pages alone, from any page. It simulates the permissions, the window picker
  question, the watch folder,
  Save to, the agents and the menu bar icon, which setup reads through
  `SetupWindowController.Callbacks`. A run records nothing. Allow… on a simulated permission flips
  the lab's value a second later instead of asking macOS, and closing plays the intro but writes no
  setting, login item or plugin.
  `docs/settings-polish-2026-09-25.md` has the design and its reasons. Closing the window is where
  the menu bar icon is introduced (`MenuBarIntro`), since otherwise it appears in a busy bar with
  nothing pointing at it: a picture of the window covers it, the window closes, and the picture
  pours into the icon, row by row, as macOS's genie pours a window into the Dock: the top edge leads,
  each row narrows to the icon's width ahead of its travel, and each fades as it enters the icon, so
  nothing piles up over it. A shader bends the picture (`Sources/IntroFunnel.metal`) and draws its
  edge, corners and shadow from one distance to the bent shape; SwiftUI's `.shadow` drew nothing
  under that effect. `docs/intro-funnel-2026-09-30.md` has the design and the measurements, and the
  Intro Lab (`vignette://intro-lab`, needs `debug`) tunes it. `ui.introFunnel` at 0 flies the
  picture as one piece instead, on the flight's bowed path. Either way the motion accelerates the
  whole way and arrives at speed, because it goes into something, where a card lands in a slot: a
  spring that settles spends as long on the last tenth of the way as on the rest. A copy of the menu
  bar's highlight comes up behind the icon as the picture reaches it. At the impact the
  icon pops, a light crosses the highlight, and a popover under it names the shortcut, or, while
  something the menu must fix is missing (`missing()`, which the menu's own items come from), names
  that and says to click the icon. All of it is timed from one moment
  on the media clock (`MenuBarIntro.keyframes`), and `ui.introDuration` sets the flight's length.
  The popover draws the shortcut as a key and goes after 5 s, when the shortcut fires, or at a click
  on the icon; a second intro, from the Intro Lab, closes the first one's. The picture is the window as the window
  server draws it, captured with ScreenCaptureKit's `SCShareableContent.currentProcess`, which lets an
  app capture its own windows without Screen Recording permission (macOS 14.4). The window's views
  drawn with `cacheDisplay` lack the wallpaper's tint, and the picture went flat at the handover;
  they are the fallback before 14.4 or when the capture fails or takes over 0.25 s. Neither has the
  outline and the dark-mode rim the window server draws at a window's edge, so the picture draws
  them, as measured on macOS 15. The capture holds the screen's own pixel values labelled sRGB,
  so the picture is labelled with the screen's colour space, and while it covers the window only
  the picture casts a shadow. The picture covers the window before the window closes, because the
  window server takes a window down at once. macOS can give
  the icon a window and draw nothing, under the notch or past the end of a full bar, so the intro
  plays only when `MenuBarIntro.canSee` says the icon shows, and `[state] app.menuBarIcon` reports
  the same answer. With no icon to point at, the last page says to open Vignette again for its
  settings.
- A launch from the disk image offers to move the app to Applications (`AppLocation.swift`),
  from `main` before `Settings.shared` exists, so the copy on the image never creates the settings
  file or touches Apple's defaults. "On the disk image" is a read-only volume or a translocated
  path; a notarized, stapled image is not translocated (observed), so the volume check is the one
  that fires for a real download. The move copies beside the destination, clears the quarantine
  flag (the user already answered Gatekeeper for this app), puts an older copy in the Trash, opens
  the new copy as a new instance, and exits; the new copy replaces the old instance as any launch
  does and detaches the image with `hdiutil detach`, because `NSWorkspace.unmountAndEjectDevice`
  unmounted an APFS image's volume and left the image attached, so opening the same file again
  mounted nothing. `VIGNETTE_SETTINGS` is passed to the moved copy, so a test launch stays on its
  scratch file. The destination is /Applications, or ~/Applications for a user who cannot write
  there. A copy there with a higher `CFBundleVersion` is opened instead, and the image ejected, so an
  old image never replaces what the updater installed. The alert is a non-activating panel
  (`runKeyed`): macOS refuses to activate a menu bar app before `NSApp.run`, and an inactive alert has
  no default button, so Return did nothing (measured on macOS 15, opened from Finder).

- Updates come from Sparkle (`Updater.swift`). The app checks the feed that `SUFeedURL` names once a
  day, and nothing installs until the person presses Install in Sparkle's window. A version a
  scheduled check finds waits as a gentle reminder, Sparkle's name for one that does not take the
  focus (`supportsGentleScheduledUpdateReminders`): a dot on the status item, with a clear ring cut
  into the icon around it, and an "Update Available…" item in its menu, above the screenshot items,
  in place of "Check for Updates…". With the menu bar icon hidden there is nowhere to show the
  reminder, so Sparkle shows its window, without activating the app. `[update]` lines log what each check found, and `[state] app.update` says what is waiting.
  The dot springs in (scaling up from 0.3 with a little bounce) and springs out the same way
  without the bounce. The icon swaps with a crossfade on springs: a picture of the old icon fades
  out while one of the new icon fades in, added together so nothing dims, and a swap that starts
  mid-fade begins from the blend on screen. All of it
  scales with `ui.motion` and is instant under Reduce Motion. A dot wanted again mid-exit reverses
  from where it is drawn (`springDot`), and is removed from the button only when its exit ends.
  Sparkle compares `CFBundleVersion`, which the build phase stamps with the commit count. So each
  release needs more commits behind it than the last, which a release cut from main has. Every
  download is checked against `SUPublicEDKey`. Installs trust only images signed with the private key
  in the Keychain account `vignette`, so a lost key leaves every install unable to update. A test
  launch runs no updater unless `VIGNETTE_FEED` names a feed. Sparkle relaunches an updated app
  through LaunchServices, with no environment, so a test copy that must stay on scratch files sets
  `VIGNETTE_SETTINGS`, `CFFIXED_USER_HOME` and `VIGNETTE_FEED` under `LSEnvironment` in its Info.plist.
  The end-to-end copies set the first two (`scripts/e2e/build.sh`).
  `docs/updater-2026-09-27.md` has the tests.
