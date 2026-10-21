# CarLyrics

CarLyrics is an iPhone prototype for importing user-owned timed lyrics, matching them to playback metadata, and presenting a glanceable Live Activity. It targets iOS 26 or newer and uses public APIs. The wireless CarPlay adapter is only a transport bridge and requires no modification.

## Status

Implemented: portable models, LRC parsing, binary-search synchronization, local/mock lyric providers, original synthetic fixtures, Spotify PKCE/token lifecycle and read-only playback clients, SwiftUI screens, private importing/matching, ActivityKit lifecycle and small/compact widget layouts, XcodeGen, tests, and CI. Implementation proceeds on `feature/carplay-live-lyrics`; `main` retains the initial foundation.

Hosted CI has passed portable Swift tests, repository safeguards, project generation, and unsigned compilation of the app and widget. Native previews, signing, iPhone OAuth, background behavior, and physical CarPlay remain unverified until the [device checklist](docs/MAC_AND_DEVICE_TESTING.md) is completed. Exact automated results and commands are recorded in [verification](docs/VERIFICATION.md). No physical compatibility is claimed.

Spotify playback and lyrics are separate subsystems. Spotify's published compliance guidance lists synchronization with lyrics as a prohibited use case. Permission and rights must be resolved before using or distributing that integration; local synthetic demonstrations do not establish approval. See [technical notes](docs/TECHNICAL_NOTES.md).

**Spotify lyric synchronization is disabled by default.** Real Spotify playback shows metadata; lyric rehearsal uses original synthetic words and an independent clock. Owning an LRC file or obtaining an OAuth token does not resolve Spotify's platform restriction.

## Structure

- `Sources/LyricsCore`, `Tests/LyricsCoreTests`: portable models, LRC parsing, synchronization, providers, and tests.
- `ios/SpotifyIntegration`: PKCE, token management interfaces, playback responses, client, and mocks.
- `ios/ApplePlatformServices`: Keychain, importing, configuration, and ActivityKit services.
- `ios/CarLyricsApp`: SwiftUI screens and application state.
- `ios/CarLyricsLiveActivity`: WidgetKit presentation and shared activity attributes.
- `ios/project.yml`: reproducible XcodeGen project definition.
- `.github/workflows`, `scripts`: automated verification.

## Development

Windows supports source work and static checks. Run `swift test` if Swift is installed. A Swift toolchain will not be installed automatically. Apple frameworks require Xcode on macOS. Exact setup and build commands will be maintained in [development](docs/DEVELOPMENT.md) and the [Mac and device guide](docs/MAC_AND_DEVICE_TESTING.md).

```powershell
python scripts/validate_repository.py
python -m unittest discover -s scripts -p 'test_*.py' -v
git diff --check
# If Swift is installed:
swift test --parallel
```

Swift is unavailable on the current Windows host. Linux CI runs package tests; macOS CI generates and compiles the app and extension unsigned. Hosted runner/Xcode settings are adjustable. A passing build does not establish simulator or vehicle behavior.

## Mac setup and use

With Xcode 26+, an iOS 26 SDK, and XcodeGen 2.44+:

```sh
git clone https://github.com/not0x9e3779b9/carlyrics.git
cd carlyrics
git switch feature/carplay-live-lyrics
swift test --parallel
cp Config.example.xcconfig Config.local.xcconfig
# Edit the local configuration.
xcodegen generate --spec ios/project.yml --project ios
open ios/CarLyrics.xcodeproj
```

Choose the CarLyrics scheme and an iOS 26+ simulator. For a phone, choose your Apple development team for both targets and unique app/extension IDs; the widget ID must start with the app ID plus a dot. No app-group or CarPlay audio entitlement is enabled. Follow [signing and installation steps](docs/MAC_AND_DEVICE_TESTING.md) for physical use.

1. Choose **Try lyric rehearsal**. No audio is played.
2. Copy `Examples/LanternRoad.lrc` into Files on the iPhone. Import it in Lyrics and match it to the current rehearsal track. Documents and bindings stay on the device.
3. Adjust lyric timing in Now Playing. Positive user values show lyrics earlier; positive file `[offset:]` delays timestamps. Test pause/resume and seeks with rehearsal controls.
4. Start the Live Activity. Privacy defaults to hidden details; change this in Settings while parked if desired. Stop Live Activity dismisses it.
5. Configure Spotify for metadata. Playback controls stay in Spotify; CarLyrics requests no playback-modification scope.

## Spotify configuration

Create a developer app in the [Spotify dashboard](https://developer.spotify.com/dashboard), obtain its public client ID, and register the exact redirect URI. The example expands to `carlyrics://callback` using xcconfig slash variables. Put your values in ignored `Config.local.xcconfig`; never add a client secret. PKCE protects the code exchange and the callback/state is validated.

Custom native schemes remain documented; Universal Links are preferred for production and require additional domain/authentication work. Current [Development Mode requirements](https://developer.spotify.com/documentation/web-api/concepts/quota-modes) restrict test access. Add your listener to the allowlist where required. Authorization can succeed while API calls still return 403. Network/offline failures, refresh/revocation, rate limits, no device/playback, advertisements, episodes, unsupported/local items, and missing lyrics are handled. Spotify APIs do not supply lyrics here.

## CarPlay and background limits

Apple [documents Live Activities in iOS 26 CarPlay](https://developer.apple.com/videos/play/wwdc2025/216/). The non-interactive small layout appears only on system-supported surfaces selected by iOS. There is no unrestricted overlay or full CarPlay audio app.

Test factory wired CarPlay first, then the unchanged wireless adapter while parked. Do not modify firmware, install files, or reverse engineer the bridge. If the activity does not appear, check system settings and fall back to the foreground phone/Lock Screen when safely parked. No specific vehicle compatibility is established here.

Polling and local clock updates run only in the foreground. Backgrounding or unavailable data marks content stale. ActivityKit does not grant indefinite execution and has payload/lifetime limits. No server supplies updates in this phase; continuous synchronized lyrics while suspended are not promised.

## Security and contribution

Tokens stay in device-only Keychain storage. Diagnostics omit tokens, callbacks, and server bodies. Local configuration, signing material, generated projects, and build products are ignored. Disconnect deletes local credentials; revoke account access separately in Spotify settings. Artwork is displayed without cropping and links to Spotify. There is no analytics or lyric scraping.

Read the [specification](docs/PROJECT_SPEC.md), [architecture](docs/ARCHITECTURE.md), [development guide](docs/DEVELOPMENT.md), and [progress checklist](docs/IMPLEMENTATION_PLAN.md). Keep core code portable, extend only licensed providers, and test meaningful behavior changes. Keep the draft pull request unmerged pending a separate instruction.

Only import lyrics you have the right to use. No lyrics service is scraped, and no commercial lyrics are bundled. Tokens belong in Keychain, never configuration, source, or preferences. A software license still needs to be selected.
