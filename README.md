# WhatFun

WhatFun is a local-first entertainment tracker for iPhone and iPad. It keeps a durable history of books, comics, movies, TV shows, games, and podcasts: what you plan to consume, each session, and when you finished.

The app is built with SwiftUI and SwiftData for iOS 26. It has no runtime dependencies and no backend. Its data model is intentionally ready for a later private CloudKit configuration, while portable CSV archives remain the long-term interoperability format.

## Status

WhatFun is under active development. The first milestones establish the versioned history model, native metadata clients, offline artwork, import/export, and the Liquid Glass interface.

## Requirements

- Xcode 26 or newer
- iOS 26 or newer
- Optional API keys for TMDB and RAWG; see `WhatFun/Support/Config.swift`

Open `WhatFun.xcodeproj`, choose an iOS 26 simulator, and run the `WhatFun` scheme.

## Principles

- Sessions and lifecycle events are archival truth; current status is a rebuildable projection.
- The app remains useful with no network connection and every item can be entered manually.
- Export formats are documented, versioned, and based on stable UUIDs.
- Provider credentials and private podcast feed URLs never enter portable exports.

## License

WhatFun is available under the MIT License.

