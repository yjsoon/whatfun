# Setup

## Toolchain

WhatFun targets iOS and iPadOS 26 and uses Swift 6 language mode. Build it with Xcode 26; no package resolution or dependency bootstrap is required.

1. Clone `https://github.com/yjsoon/whatfun.git`.
2. Open `WhatFun.xcodeproj`.
3. Select the `WhatFun` scheme and an iOS 26 simulator, then run.
4. For a physical device, select your development team under **Signing & Capabilities**. The checked-in bundle identifier is `com.yjsoon.whatfun`; use an identifier owned by your team if necessary.

Run the Swift Testing suite with **Product > Test** (`Command-U`). Tests use an in-memory SwiftData store and do not need API credentials.

## Metadata configuration

The app accepts provider credentials from its Keychain-backed fields under **Settings → Metadata**. For an owner build that works without in-app setup, copy `Configuration/Secrets.xcconfig.local.example` to `Configuration/Secrets.xcconfig.local` and add the credentials there:

```xcconfig
TMDB_READ_ACCESS_TOKEN = your-token
RAWG_API_KEY = your-key
```

`Secrets.xcconfig.local` matches the repository's `*.xcconfig.local` ignore rule. Never remove that rule or commit the local file. Xcode loads the committed `Config.xcconfig` for Debug and Release builds, optionally includes the local values, and substitutes them into the built app's Info.plist. This keeps credentials out of Git, but—as with every credential shipped inside a client app—does not make them secret from someone who can inspect a distributed binary.

| Media | Provider | Setup |
| --- | --- | --- |
| Movies and TV | TMDB | Create an API read-access token in [TMDB API settings](https://www.themoviedb.org/settings/api), then save it in Settings or `Secrets.xcconfig.local`. |
| Books and comics | Open Library | No key is required. Replace `YOUR_CONTACT_EMAIL` in `WhatFun/Support/Config.swift` with a contact address so requests identify the app responsibly. |
| Games | RAWG | Request a key from the [RAWG API documentation](https://rawg.io/apidocs), then save it in Settings or `Secrets.xcconfig.local`. |
| Podcasts | Apple Search and podcast RSS | No key is required. |

Placeholder or missing TMDB/RAWG credentials disable that provider cleanly. Network errors do not block manual entry or access to existing local data. Remote covers are cached in Application Support for offline display.

Credentials supplied through `Secrets.xcconfig.local` are build configuration, while values entered in Settings are stored in Keychain. Neither is library data, and credentials are never included in either export format.

## Local permissions

- Notifications are requested only when a local start reminder is scheduled.
- User-selected artwork is imported through system pickers.
- Private podcast feed URLs are stored in Keychain rather than SwiftData.

There is no account, analytics SDK, or WhatFun server.
