# Beep

Native SwiftUI client for WeBeep, the Moodle platform of Politecnico di Milano.
iOS and iPadOS 26+, Liquid Glass, adaptive layout (iPhone, iPad, foldable).

Beep is sync-centric: it keeps a local index of your courses and files, downloads
new material automatically for the courses you choose, shows what's new, and lets
you search files inside a course or across all of them. Downloaded files live in
the Files app ("On My iPhone → Beep") so any other app can open and edit them.

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
