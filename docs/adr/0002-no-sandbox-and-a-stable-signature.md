# No sandbox, the hardened runtime, and one signing certificate for every build

Vignette runs outside the App Sandbox on purpose, with the hardened runtime on, because it writes
Apple's `com.apple.screencapture` defaults, watches a folder without security-scoped bookmarks, and
installs global event monitors. Every build is signed with
the same certificate, because macOS ties Accessibility trust to the signature's designated
requirement, and an ad-hoc signature changes with every build. macOS also keys that trust by bundle
id, so a test copy that needs its own trust needs its own bundle id.

## Consequences

The Mac App Store requires the sandbox, so it is not a channel for Vignette.

Sources: `docs/building.md`, commits 52f9dce and 1a5e375.
