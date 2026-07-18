# Contributing to NetworkingKit

Thank you for helping improve NetworkingKit.

## Development setup

- Xcode with Swift 6.0 or later.
- iOS 17 and macOS 14 deployment targets.

Run the package tests before opening a pull request:

```sh
swift test
```

Also build both Demo schemes without signing:

```sh
xcodebuild -project Examples/NetworkingKitDemo/NetworkingKitDemo.xcodeproj -scheme NetworkingKitDemo-iOS -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Examples/NetworkingKitDemo/NetworkingKitDemo.xcodeproj -scheme NetworkingKitDemo-macOS -sdk macosx -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

## Pull requests

- Keep each pull request focused on one behavior change.
- Add or update tests for public behavior.
- Update both README languages and `CHANGELOG.md` for user-visible changes.
- Preserve Swift API documentation and the standard file header on new source files.
- Do not include secrets, API tokens, or generated build output.
