# Live ink asks for Screen Recording

An ask about live ink sends a capture of the window under the ink, so live ink needs Screen
Recording, a permission nothing else in Vignette needs. Turning the switch on raises macOS's own
alert; after that, a row under the switch and the menu's first item open its pane. Setup does not
ask, since live ink is off by default and setup's job is the shortcut. Without pixels the responder
would have only the window's name, and Accessibility gives little in the apps measured: Ghostty no
text under a point, Dia nothing until asked, the Codex app nothing.

On macOS 15 the first capture also raises macOS's "bypass the system private window picker" alert,
and macOS asks again about once a month, so some people will turn the permission off.

## Considered options

- Accessibility and Vision without a capture: Vision needs pixels, and Accessibility alone is too thin.
- Freezing the screen when the chord goes down, which needs the same permission.

Sources: docs/live-ink-integration-2026-10-04.md (decision 4), docs/live-ink-step2-spike-2026-10-04.md.
