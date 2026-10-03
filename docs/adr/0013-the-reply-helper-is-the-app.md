# The reply helper is the app's own binary

An agent replies by running the skill's `scripts/reply`, a shell script that runs `<app> reply`.
The app's binary handles that command and exits before any window exists. Nothing shipped depends
on Python, because `/usr/bin/python3` on a Mac without Apple's developer tools is a stub that asks
to install them. The script runs only a bundle whose Info.plist declares `VignetteReplyCommand`,
since any other binary would start the app and replace the running instance.

## Considered options

- The Python helper it replaced.
- A shell helper on its own, which has no JSON parser on macOS 14.

Sources: `docs/reply-command-2026-09-26.md`, commit ddc8125.
