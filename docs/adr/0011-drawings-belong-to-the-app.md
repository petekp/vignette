# Drawings belong to the app and are never migrated

Each screenshot's drawing is one JSON file in Vignette's Application Support folder, named by a
hash of the screenshot's path, and the screenshot itself is never changed. A change to the format,
to how a mark looks or to what a field means ships with no migration, compatibility reader or
fallback. This is a deliberate policy, not an oversight: drawings made by earlier builds are not
kept readable, so nobody should add a migration to be safe.

## Considered options

- A one-time conversion of the web editor's drafts. They were deleted instead.
- Drawing old marks in their stored colours when mark colours changed.

Sources: commits f1f4797, 9ccec8d and 56572c2.
