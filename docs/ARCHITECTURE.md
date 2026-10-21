# Architecture

`LyricsCore` owns TrackMetadata, PlaybackSnapshot, lyric documents, parsing, provider interfaces, an injectable clock, synchronization, and portable presentation state. Its dependencies are Swift/Foundation only.

`SpotifyIntegration` depends on LyricsCore. A URLSession transport performs PKCE token exchange/refresh and read-only playback requests. A token-store protocol separates secure Apple persistence from in-memory test doubles. The SwiftUI application receives dependencies through its state container.

`ApplePlatformServices` provides Keychain storage, configuration validation, local document persistence and security-scoped import, browser authentication, and ActivityKit lifecycle. Shared activity attributes are compiled into both app and widget extension without depending on application UI.

`CarLyricsApp` performs conservative foreground polling and advances the estimated playback clock locally. Scene changes stop foreground work and mark Live Activity content stale. The widget extension renders a compact state without network calls, token access, or background lyric processing. An update-sink interface can later accommodate server-originated state.

Imported LRC documents and explicit track bindings stay on the device. Playback metadata is ephemeral. Credentials exist only in Keychain. No app group is required for ActivityKit's state transport; a future shared library feature would need a separately reviewed group capability.
