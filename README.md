# CarLyrics

CarLyrics is an iPhone prototype for importing user-owned timed lyrics, matching them to playback metadata, and presenting a glanceable Live Activity. It targets iOS 26 or newer and uses public APIs. The wireless CarPlay adapter is only a transport bridge and requires no modification.

## Status

Repository foundation is in place. Implementation proceeds on `feature/carplay-live-lyrics`; `main` retains the initial foundation. Native compilation, signing, simulator behavior, and physical iPhone and CarPlay compatibility require later validation on a Mac and real hardware. No physical compatibility is claimed.

Spotify playback and lyrics are separate subsystems. Spotify's published compliance guidance lists synchronization with lyrics as a prohibited use case. Permission and rights must be resolved before using or distributing that integration; local synthetic demonstrations do not establish approval. See [technical notes](docs/TECHNICAL_NOTES.md).

## Structure

- `Sources/LyricsCore`, `Tests/LyricsCoreTests`: portable models, LRC parsing, synchronization, providers, and tests.
- `ios/SpotifyIntegration`: PKCE, token management interfaces, playback responses, client, and mocks.
- `ios/ApplePlatformServices`: Keychain, importing, configuration, and ActivityKit services.
- `ios/CarLyricsApp`: SwiftUI screens and application state.
- `ios/CarLyricsLiveActivity`: WidgetKit presentation and shared activity attributes.
- `ios/project.yml`: reproducible XcodeGen project definition.
- `.github/workflows`, `scripts`: automated verification.

## Development

Windows supports source work and static checks. Run `swift test` if Swift is installed. A Swift toolchain will not be installed automatically. Apple frameworks require Xcode on macOS. See the [Mac and device guide](docs/MAC_AND_DEVICE_TESTING.md) for platform setup and testing requirements.

Only import lyrics you have the right to use. No lyrics service is scraped, and no commercial lyrics are bundled. Tokens belong in Keychain, never configuration, source, or preferences. A software license still needs to be selected.
