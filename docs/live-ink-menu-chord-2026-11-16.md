# The chord while a menu is open (2026-11-16)

Holding ⌃⌥ while one of Vignette's own menus was open began no chord. Over other apps' menus it
began as usual. This note has the measurement, the cause and why the fix is shaped as it is. The
rule is in `docs/live-ink.md`, at the chord.

## The measurement

A throwaway process, trusted for Accessibility, logged every change of modifiers three ways: an
NSEvent global monitor, a listen-only event tap at the session level, and the HID state read every
50 ms. It also logged when a window above the status bar's level came and went. Pete held ⌃⌥ with
no menu open, then with menus open. Its times were matched to Vignette's log by the length of each
hold.

- Two holds while the only window above the menu bar was Vignette's own (its status menu): the
  listener's monitor, tap and HID state all heard ⌃ and ⌥ go down and up. Vignette's log has no line
  for either hold, not even `[live-ink] not inking`, so its chord never began.
- A hold over another app's menu: Vignette inked (`[live-ink] inking`), and letting go closed the
  menu (`menus closing count=1 refused=0`, `menus closed`) and opened the note.

## The cause

`ModifierChord` heard the modifiers only through NSEvent monitors. A global monitor hears only events
sent to other apps. A local monitor is not called for events that a nested tracking loop, such as a
menu's, consumes (the documentation of `NSEvent.addLocalMonitorForEvents`). While Vignette's own
menu tracks, every modifier change is Vignette's own and goes to that loop, so neither monitor hears
it. Another app's menu does not stop Vignette's global monitor.

## The fix

- `ModifierChord` hears the modifiers through a listen-only event tap (`FlagsTap`), which sees
  every event at the session level before any app's loop does. Its callback runs on
  `EventTapThread`, the thread `LiveInkTap` uses, and hands a copy of each event to the main queue,
  which runs during a menu's tracking too.
- The tap is listen-only, not active. An active tap would be on for as long as live ink is, and an
  active tap left on while Accessibility is taken away has been reported to block the Mac's input
  until a restart (Apple developer forums, unverified here). macOS gives a listen-only tap on keys
  only to a process with access to listen to keys, so the tap is made only when
  `CGPreflightListenEventAccess` answers true, which never prompts. Otherwise the monitors hear the
  chord as before.
- Vignette's own menu tracks on the main thread, where inking runs, and holds the keys the note
  would take. So the chord closes whichever of Vignette's menus is open, the status menu or the
  note's target menu, before inking starts (`LiveMenus.Own`). Closing the target menu this way is
  the same as dismissing it with no pick.
- The chord's 50 ms key poll runs in the common run loop modes, so it keeps running while any of
  Vignette's tracking loops runs.

## Not checked

- No run has shown the tap hearing ⌃⌥ with Vignette's own menu open, or the menu closing as inking
  starts. Checking it needs a person's hands on this Mac's keys, which a VM's VNC cannot press.
- Whether Vignette has access to listen to keys on Pete's Mac was not read. Without it, the log says
  `[live-ink] the chord: no access to listen to keys`, and the chord over Vignette's own menu still
  begins nothing.
