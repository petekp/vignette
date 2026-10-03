# The drawing editor is native Swift, not tldraw

The first editor was tldraw in a web view. Its license allows a public download only with a
production key, and an annual key that expires hides the editor in every copy already downloaded.
The web editor also used 132 MB across WebKit's processes. Vignette replaced it with an AppKit view
over a pure reducer, and deleted the web editor, its local server and its drafts.

## Considered options

- Shipping on a hobby key, a commercial license, or a reissued key. Each kept the editor dependent
  on a key, for the few tldraw features Vignette used.
- An open-source Swift drawing library.

Sources: `docs/native-editor-2026-09-23.md`, commits 873c326 and 77047f4.
