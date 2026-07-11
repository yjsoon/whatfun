# WhatFun

WhatFun is a local-first entertainment tracker for iPhone and iPad. It keeps a durable history of books, comics, movies, TV shows, games, and podcasts: what you plan to consume, each session, and when you finished.

The app is built with SwiftUI and SwiftData for iOS 26. It has no third-party dependencies and no backend. Its data model is intentionally ready for a later private CloudKit configuration, while portable CSV archives remain the long-term interoperability format.

## What it tracks

- One canonical library item with repeatable reading, watching, playing, or listening cycles.
- Timestamped sessions, optional progress, lifecycle events, half-star ratings, notes, tags, favorites, and manual or smart lists.
- TV seasons and episodes, comic volumes and issues, podcast episodes, and notable quotes.
- Calendar week, month, and year summaries that preserve sessions while collapsing repeated titles for display.
- Cover metadata from TMDB, Open Library, RAWG, and Apple Podcasts, with offline artwork caching and manual entry when a provider is unavailable.
- Staged Sofa CSV, Overcast CSV, and podcast OPML imports; portable CSV archives and full-fidelity JSON backups.

## Status

WhatFun is under active development. The first milestones establish the versioned history model, native metadata clients, offline artwork, import/export, and the Liquid Glass interface.

## Requirements

- Xcode 26
- iOS 26 or iPadOS 26
- A development team for device builds

Clone the repository, open `WhatFun.xcodeproj`, choose the `WhatFun` scheme and an iOS 26 destination, then run. TMDB and RAWG search need developer credentials; everything else, including manual entry, remains usable without them. See [Setup](docs/SETUP.md) for signing, API-key, and test instructions.

## Principles

- Sessions and lifecycle events are archival truth; current status is a rebuildable projection.
- The app remains useful with no network connection and every item can be entered manually.
- Export formats are documented, versioned, and based on stable UUIDs.
- Provider credentials and private podcast feed URLs never enter portable exports.

The portable multi-file CSV package is the archive of record for moving data between apps. The versioned JSON format is for exact WhatFun restore; private podcast feed URLs can be included only in its separately encrypted block. See [Data portability and privacy](docs/DATA_PORTABILITY.md) for the contract and import limitations.

## Architecture

WhatFun currently stores data only on the device. CloudKit is deliberately disabled, not silently active. The schema and service boundaries are shaped to make a future private-database sync migration possible; see [Architecture](docs/ARCHITECTURE.md).

## License

WhatFun is available under the MIT License.
