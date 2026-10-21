# Verification

## Local Windows checks

| Command | Actual result |
| --- | --- |
| `git --version` | Git 2.55.0.windows.5 |
| `gh --version` | GitHub CLI 2.102.0 |
| `gh auth status` | Authenticated account with repository/workflow access when network access was available; no credential values recorded |
| `Get-Command swift -ErrorAction SilentlyContinue` | Swift not found; local Swift tests could not run |
| `python -m unittest discover -s scripts -p 'test_*.py' -v` | Ten repository-safeguard tests passed |
| `python scripts/validate_repository.py` | Tracked-file and configuration safeguards passed after corrections |
| `python scripts/validate_repository.py --staged` | Index-content safeguards passed before publication |
| `git diff --check` and `git diff --cached --check` | Passed after whitespace cleanup |

These Python/static checks do not execute Swift or validate Apple SDK behavior. No large toolchain was installed on Windows. A first scanner run identified a deleted unstaged placeholder; another flagged Swift response coding keys as possible credentials. Both were corrected and regression coverage was added for the coding-key case.

## Hosted Swift checks

The Core Tests workflow runs `swift --version` and `swift test --parallel` in `swift:6.0-jammy` on Linux. The observed compiler was Swift 6.0.3.

- Initial core CI compiled the package and executed 48 XCTest cases. One failed: signed malformed minute tags were classified as unknown metadata, producing two warnings where three were expected.
- The Spotify milestone compiled both modules and executed 78 tests. The same parser assertion was the only failure; the 30 Spotify tests reported no failures.
- The parser now requires a metadata key to start with a letter and adds a signed-minute/recovery regression test. A presentation regression also distinguishes before-first waiting from instrumental gaps.
- Post-fix CI for `b76c38e` passed all 80 XCTest cases (50 core, 30 Spotify), using `swift test --parallel` with Swift 6.0.3. Both push and pull-request runs succeeded. See [Core Tests](https://github.com/not0x9e3779b9/carlyrics/actions/runs/39654805782).
- Final review identified an account-switch race in in-flight Spotify playback requests. Revision-bound guards and five deterministic regression tests were added at `3a57ff0`. Its [Core Tests run](https://github.com/not0x9e3779b9/carlyrics/actions/runs/39655935503) passed all 85 tests (50 core, 35 Spotify) with `swift test --parallel` under Swift 6.0.3.

Do not interpret Swift Testing's separate “0 tests” footer as the XCTest total; package tests use XCTest.

## Hosted native checks

The iOS Build workflow checks the Xcode/SDK version, runs `xcodegen generate --spec ios/project.yml --project ios`, then:

```sh
xcodebuild -project ios/CarLyrics.xcodeproj -scheme CarLyrics \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The default runner is `macos-26` with `/Applications/Xcode_26.6.app/Contents/Developer`, verified against the [official runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md). The [iOS Build for b76c38e](https://github.com/not0x9e3779b9/carlyrics/actions/runs/39654805699) successfully generated the project and compiled both the application and widget with Xcode 26.6 (17F113). This unsigned build is not signing, simulator runtime, preview, or hardware acceptance.

The final source revision `3a57ff0` also passed [iOS Build](https://github.com/not0x9e3779b9/carlyrics/actions/runs/39655935336), including the authorization-window and pending-activity warning fixes. Its only build notice was skipped AppIntents metadata extraction because the project has no AppIntents dependency.

The [Repository Checks workflow](https://github.com/not0x9e3779b9/carlyrics/actions/runs/39654805619) also passed the tracked-content/configuration scan, ten Python safeguards, and committed whitespace validation for the same revision.

[Repository Checks for final source revision 3a57ff0](https://github.com/not0x9e3779b9/carlyrics/actions/runs/39655935185) passed those checks again. The final documentation milestone changes no application or test source. Local documentation-link validation found zero missing relative targets.

## Remaining acceptance

No local Xcode, simulator, preview, signing, physical iPhone OAuth/Keychain/import validation, wired CarPlay, wireless-adapter CarPlay, Lock Screen privacy, or eight-hour lifecycle test has run on the Windows host. Complete [MAC_AND_DEVICE_TESTING](MAC_AND_DEVICE_TESTING.md), recording actual device results. Spotify synchronization permission remains a production blocker; synthetic rehearsal and metadata-only playback are the default behavior.
