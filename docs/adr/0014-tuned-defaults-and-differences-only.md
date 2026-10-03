# The maintainer's tuned UI is the default, and settings.json keeps only differences

The maintainer runs Vignette on its defaults, so what the maintainer tunes becomes the default for
everyone. settings.json
stores only the `ui` values that differ from the defaults, so a default tuned in a later build
reaches every install. The file is version 2, and a build from before it opens such a file
read-only.

## Considered options

- Writing every `ui` key, which fixed each install's defaults at its first launch.
- Per-person overrides of the tuned defaults.

Sources: `docs/prerelease-fixes-2026-09-26.md`, commits 09f2ac1 and a9091fd.
