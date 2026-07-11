# Data portability and privacy

WhatFun has two first-party export formats with different jobs. They are versioned semantic exports, not copies of the SwiftData database file.

## Portable CSV archive: the archive of record

A portable export is a directory package containing UTF-8 RFC 4180 CSV tables, `manifest.json`, `SCHEMA.md`, and any user-owned artwork assets. It is intended to remain understandable and realistically importable without WhatFun.

The tables preserve stable UUID joins for canonical items, nested units, consumption cycles, sessions, lifecycle events, notable quotes, lists and smart rules, list and tag membership, artwork, credits, reminders, and metadata references. Dates use ISO 8601 instants; sessions also retain their original IANA time-zone identifier. Ratings use half steps on a 0.5–5 scale, and page, elapsed-time, playtime, and percentage progress have named columns.

Each listed file has a SHA-256 checksum, byte count, and, for tables, row count. WhatFun validates the manifest, safe relative paths, required tables, and checksums before decoding a restore. The generated `SCHEMA.md` inside every package documents its exact table version and stable value vocabulary.

Portable archives deliberately exclude:

- private podcast feed URLs;
- Keychain credential identifiers;
- TMDB and RAWG developer credentials;
- disposable downloaded metadata and cover caches.

Public provider identities and URLs remain portable. User-supplied artwork is archival and may be placed under the checksummed `assets/` directory.

## Full-fidelity JSON backup

The WhatFun JSON envelope is for exact app-to-app restore. It preserves the same semantic history with stable IDs plus supported app preferences. Restore supports two explicit modes:

- **Replace all** validates first, then replaces current semantic records.
- **Merge new** inserts IDs absent from the current library and never overwrites an existing record with the same stable ID.

Current status, counts, rating summaries, dates, and progress are rebuildable projections; restore recalculates them from the history records rather than trusting stale display state.

Private podcast feed URLs never appear in the ordinary JSON payload. When the user chooses to include them, WhatFun serializes them into a separate authenticated AES-GCM-256 block. A user passphrase is converted to a 256-bit key with PBKDF2-HMAC-SHA256, a random 16-byte salt, and the iteration count recorded in the envelope. The passphrase and derived key are not stored. Losing the passphrase means the private feeds cannot be restored, while the non-private backup data remains independently readable.

Treat both formats as sensitive: titles, dates, notes, quotes, and history can reveal personal habits even when feed secrets are redacted.

## Staged imports

Legacy imports never silently merge ambiguous rows. Each adapter creates a transient review batch, offers existing-library match candidates, and leaves uncertain dates, media types, URLs, or close title matches for confirmation. Skipped or unresolved rows do not mutate the library.

### Podcast OPML

OPML imports subscription outlines: title, feed URL, optional site/author, and nested category path. It does not contain episode history, playback position, ratings, quotes, or notes, so those cannot be reconstructed. Duplicate feed URLs are ignored. Accepted private feed URLs move to Keychain; staging data is not persisted or logged as ordinary app data.

### Overcast All Data CSV

This is a best-effort file import, not live Overcast sync. Column names have changed across Overcast versions, so the adapter accepts known aliases and requires review. It can stage podcast/episode identity, publish date, duration, elapsed or percentage progress, completion, starred/notable state, and notes when present. It cannot recover fields absent from the exported rows, and rows without a podcast title may need manual matching. Duplicate episode rows are reported and ignored.

### Sofa CSV

Sofa exports vary by app version. The adapter accepts common aliases for title, media type, status, dates, rating, notes, lists, tags, external IDs, and type-specific progress. A source row stays a distinct history candidate, so repeated titles are not collapsed during staging. Numeric dates that could be day-first or month-first, unknown media types, missing completion dates, and uncertain title matches require review. Unsupported or absent Sofa fields cannot be invented; keeping the original export beside a WhatFun portable archive is prudent until the reviewed result has been verified.

## Backup practice

Use portable exports as the long-lived, app-neutral record and make one after important imports or edits. Use full JSON backups for rapid exact restoration to WhatFun. Before deleting a source database, inspect a few old sessions, completion dates, ratings, progress values, notes, and list memberships after import.
