# One geometry and one renderer draw marks everywhere

A mark looks the same in the editor, on a card, in flight and in an exported image, because one
geometry gives its paths and one renderer draws it. Cards draw their marks live and keep no preview
images. Nothing steps when a flight hands over to the editor, and a card is current as soon as its
drawing is saved.

## Considered options

- Stored card previews. They existed only to show the web editor's drafts, and were deleted with it.

Sources: `docs/native-editor-2026-09-23.md`, `docs/editor.md`.
