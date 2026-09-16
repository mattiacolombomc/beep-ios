# Beep

Native SwiftUI client for WeBeep, the Moodle platform of Politecnico di Milano.
iOS and iPadOS 26+, Liquid Glass, adaptive layout (iPhone, iPad, foldable).

Beep is sync-centric: it keeps a local index of your courses and files, downloads
new material automatically for the courses you choose, shows what's new, and lets
you search files inside a course or across all of them. Downloaded files live in
the Files app ("On My iPhone → Beep") so any other app can open and edit them.

## Features

- Sign in with Polimi credentials or SPID once; the WeBeep access key is stored in the Keychain and renewed silently.
- Courses grouped by academic year with favourites, archive, filters and instant search.
- Course view with folders, in-course file search by type, download all, and QuickLook preview.
- Background downloads for the courses you choose, "what's new" badges, recent-files feed, global file search.
- Background checks with local notifications for new files and announcements (frequency and Wi-Fi-only configurable).
- WeBeep notifications, read-only announcements and forums, Moodle pages.
- WeBeep catalogue: enrol in new courses and leave self-enrolment courses from the app.
- Spotlight indexing, "Latest material" home-screen widget, Siri/Shortcuts intents, `beep://` deep links.
- Files live in the Files app, one folder per course (renamable), so any other app can open them.

Successor of [myPoliFile](https://github.com/matteovisotto/myPoliFile) by Matteo
Visotto (MIT). See `NOTICE` for attributions.

## Requirements

- Xcode 27, iOS 26 SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- fastlane + 1Password CLI for TestFlight uploads (optional)

## Build

```sh
xcodegen generate
open Beep.xcodeproj
# or
xcodebuild -project Beep.xcodeproj -scheme Beep \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project Beep.xcodeproj -scheme Beep \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

`project.yml` is the source of truth; `Beep.xcodeproj` is generated and committed
so fastlane can bump build numbers.

## Structure

```
Beep/
  App/          entry point, root view, tabs
  MoodleKit/    WeBeep/Moodle REST client, DTOs, parsers (pure, testable)
  Auth/         Keychain token store, SSO web login, manual token fallback
  Store/        SwiftData models and queries
  Sync/         SyncEngine, Indexer (diff), DownloadManager, background refresh, notifications
  Features/     one folder per screen
  Design/       theme tokens and shared components
  Resources/    assets, string catalog (en, it)
BeepTests/      unit tests with JSON fixtures
docs/superpowers/specs/  design documents
fastlane/       TestFlight lanes
```

## Design document

See `docs/superpowers/specs/2026-09-16-beep-design.md`.

## License

MIT — see `LICENSE`. Not affiliated with Politecnico di Milano.
