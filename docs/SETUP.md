# Setup

## Toolchain

WhatFun targets iOS and iPadOS 26 and uses Swift 6 language mode. Build it with Xcode 26; no package resolution or dependency bootstrap is required.

1. Clone `https://github.com/yjsoon/whatfun.git`.
2. Open `WhatFun.xcodeproj`.
3. Select the `WhatFun` scheme and an iOS 26 simulator, then run.
4. For a physical device, select your development team under **Signing & Capabilities**. The checked-in bundle identifier is `com.yjsoon.whatfun`; use an identifier owned by your team if necessary.

Run the Swift Testing suite with **Product > Test** (`Command-U`). Tests use an in-memory SwiftData store and do not need API credentials.

## Metadata configuration

All provider settings are in `WhatFun/Support/Config.swift`. Keep this as the single setup point and do not commit production credentials to a public fork.

| Media | Provider | Setup |
| --- | --- | --- |
| Movies and TV | TMDB | Create an API read-access token in [TMDB API settings](https://www.themoviedb.org/settings/api) and replace `YOUR_TMDB_READ_ACCESS_TOKEN`. |
| Books and comics | Open Library | No key is required. Replace `YOUR_CONTACT_EMAIL` with a contact address so requests identify the app responsibly. |
| Games | RAWG | Request a key from the [RAWG API documentation](https://rawg.io/apidocs) and replace `YOUR_RAWG_API_KEY`. |
| Podcasts | Apple Search and podcast RSS | No key is required. |

Placeholder or missing TMDB/RAWG credentials disable that provider cleanly. Network errors do not block manual entry or access to existing local data. Remote covers are cached in Application Support for offline display.

API credentials in `Config.swift` are build configuration, not library data. They are never included in either export format.

## Local permissions

- Notifications are requested only when a local start reminder is scheduled.
- User-selected artwork is imported through system pickers.
- Private podcast feed URLs are stored in Keychain rather than SwiftData.

There is no account, analytics SDK, or WhatFun server.
