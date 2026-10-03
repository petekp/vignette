# Releases are notarized disk images built on the maintainer's Mac, and Sparkle updates them

`scripts/release.sh` builds, signs, notarizes and staples a disk image on the maintainer's Mac rather than in
CI, which keeps the signing identity and the notary credentials in one place. A zip was rejected:
an app launched from a downloaded zip runs from a randomized read-only path, and a URL scheme, a
settings file and an Accessibility grant do not survive that. Sparkle checks for updates once a
day, installs nothing until the person presses Install, and verifies every download against an
EdDSA key kept in the Keychain.

## Consequences

- Losing the update key leaves every install unable to update.
- Sparkle compares `CFBundleVersion`, which is the commit count, so each release needs more commits
  behind it than the last.

Sources: `docs/shipping-a-download-2026-09-21.md`, `docs/updater-2026-09-27.md`.
