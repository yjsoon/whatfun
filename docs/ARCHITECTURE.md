# Architecture

## Product shape

WhatFun is a personal archive, not a playback client. One canonical library item can have many consumption cycles and many timestamped sessions. Marking an item complete is a lifecycle event separate from logging a session.

The six root media kinds are books, comics, movies, TV shows, games, and podcasts. A generic nested content unit represents TV seasons and episodes, comic volumes and issues, and podcast episodes. This keeps shared history behavior uniform without SwiftData inheritance.

## Visual and interaction thesis

WhatFun is a warm personal archive: beige paper and coral signals in light mode, aubergine ink and softened coral in dark mode. Cover art carries the emotion. Liquid Glass belongs to navigation and actions rather than content cards.

Home answers “what am I consuming?” and “what did I consume?” Library is a cover-first archive, Lists organize intent, and Search adds or finds media. Session logging is a brief acknowledgement; filters move smoothly; cover-to-detail is the one richer transition. Motion always respects system accessibility settings.

## Data boundaries

- `WhatFunSchemaV1` starts explicit SwiftData versioning on the first release.
- Relationships are optional with explicit inverses, stable UUIDs have no uniqueness constraints, and delete rules avoid `.deny` for future CloudKit compatibility.
- Sessions, activity events, ratings, and nested units are source records. Query-friendly status, rating, count, date, and progress fields on the root item are rebuildable projections.
- Network and import actors exchange `Sendable` DTOs or persistent identifiers, never live SwiftData models.
- Remote artwork is durably cached in Application Support and downsampled for display. User artwork is archival data.
- Private podcast feeds live in Keychain; SwiftData stores only an opaque credential identifier.

## Navigation

The root uses native iOS 26 `Tab` navigation with Home, Library, Lists, and a semantic Search role. Each tab owns a value-based navigation path. Standard navigation, toolbar, sheet, and tab surfaces adopt Liquid Glass automatically.

## Archive contract

Portable exports are multi-file CSV packages with a manifest, checksums, ISO 8601 timestamps, explicit time zones, stable UUID joins, and named progress columns. A versioned JSON backup preserves exact app fidelity. Sofa, OPML, and Overcast files enter through staging adapters and a review step before insertion.

