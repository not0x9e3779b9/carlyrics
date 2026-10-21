# Technical notes

## Source verification

Reviewed official sources on 2026-10-20. Source review establishes API intent, not physical compatibility or native compilation.

- [Apple: creating custom views for Live Activities](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities) describes supplemental small/medium families and `activityFamily` layout selection.
- [Apple: Turbocharge your app for CarPlay](https://developer.apple.com/videos/play/wwdc2025/216/) introduces iOS 26 Live Activities in CarPlay. The small family is glanceable and non-interactive; system presentation is not a custom CarPlay app.
- [Spotify compliance tips](https://developer.spotify.com/compliance-tips) explicitly lists synchronization with lyrics among prohibited use cases. This is a product permission blocker, even for a playback-metadata-based design; do not assume local lyric ownership or API OAuth overrides it.
- [Spotify developer policy](https://developer.spotify.com/policy) applies in addition to rights in imported lyrics. Seek appropriate permission before deploying the Spotify synchronization use case.

## Limits and open questions

No Mac, Xcode, simulator, iPhone, or vehicle has been tested. Background polling cannot continue indefinitely when iOS suspends the application. ActivityKit presents state; it does not provide unlimited application execution. Server-driven updates could be an extension, but no server exists here and push delivery is not a real-time guarantee. The bridge adapter cannot render arbitrary content.

OAuth, endpoint, development-mode, payload, and lifecycle details will be recorded with their official sources during implementation. No CarPlay audio entitlement is requested. Physical acceptance includes both factory wired connection and the unchanged wireless adapter.
