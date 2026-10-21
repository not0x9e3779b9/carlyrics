# Technical notes

## Verification boundary

Official documentation was reviewed on 2026-10-20. The statements below describe documented APIs and the implementation's intended behavior. Hosted CI subsequently verified unsigned app/widget compilation; documentation review alone does not establish Spotify dashboard access, simulator behavior, or compatibility with a physical iPhone, vehicle, or wireless adapter. Consult [verification results](VERIFICATION.md) and the [testing guide](MAC_AND_DEVICE_TESTING.md) for validation status.

## Spotify permission boundary

Spotify's [compliance tips](https://developer.spotify.com/compliance-tips) expressly identify synchronization of its recordings with lyrics as a disallowed use case. Its [developer policy](https://developer.spotify.com/policy) also applies. This is a product permission blocker, separate from OAuth and ownership of an imported lyric file.

The committed configuration therefore sets `SPOTIFY_LYRICS_ENABLED = NO`. With that setting, Spotify mode reads and presents playback metadata; imported lyrics remain available in the local library but are not connected to the Spotify clock or included in its Live Activity. The independent synthetic rehearsal uses original sample text and a local demo clock. There is no in-app switch that resolves the restriction. Written Spotify permission and the required lyric rights must be established before changing the configuration or deploying Spotify lyric synchronization.

## Apple presentation behavior

Apple documents iOS 26 support for iPhone Live Activities in CarPlay Dashboard and, when appropriate, notifications. A separate CarPlay application is unnecessary for this surface. CarPlay selects the `.small` activity family and can use Dynamic Island compact leading/trailing views as a fallback. Live Activities in CarPlay are noninteractive. The user and system control whether and where the presentation appears. See [Turbocharge your app for CarPlay](https://developer.apple.com/videos/play/wwdc2025/216/).

`CarLyricsLiveActivity` declares `.supplementalActivityFamilies([.small, .medium])` and reads `activityFamily`. Its small layout shows a current line or status plus compact metadata. The medium Lock Screen layout can include secondary neighboring lines. Neither layout scrolls or provides driving-time search or typing. Dynamic Island compact/minimal layouts emphasize status. Apple describes these families in [creating custom views for Live Activities](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities).

The project requests no CarPlay audio-app entitlement and implements no custom CarPlay scene. The USB wireless adapter remains an unchanged transport bridge. It does not execute the app, supply a lyric renderer, or permit arbitrary screen overlays. Test the factory wired connection and the adapter separately; neither has been verified here.

## ActivityKit limits and lifecycle

Apple limits the combined static attributes and dynamic state to 4 KB. A Live Activity can remain active for at most eight hours, then may remain on the Lock Screen for up to four further hours. Its widget extension cannot fetch network data or location. Updates must come from the application while it can execute, or through the supported push mechanism. See [displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

The implementation checks `areActivitiesEnabled`, restores the newest existing session, ends duplicate sessions, observes dismissal, and ends requested sessions with immediate dismissal. It filters private content before transport and validates an encoded attributes/state envelope against a conservative 3,800-byte local budget. Portable presentation generation caps title and artist at 64 UTF-8 bytes each and each neighboring/current line at 128 bytes. Artwork, credentials, and complete lyric documents never enter the payload. The local eight-hour check also ends an expired session when an update is attempted.

Local content becomes stale after 15 seconds by default. Foreground publication sends changed display state and a ten-second freshness heartbeat. Leaving the foreground requests one stale update and cancels polling/ticker tasks. The stale deadline still provides a fallback if suspension prevents that final update. A stale label communicates old information; it does not schedule future lyric updates.

`LiveActivityServerUpdateSink` reserves a future authenticated push integration. No sink, backend, push credential, or push-token upload is configured by default. Apple applies delivery budgets and throttling to remote updates; adding a server would not establish exact per-line timing. See [starting and updating Live Activities with push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications).

## Foreground and background execution

The app currently requests Spotify state about every five seconds while active and connected. Its local 100-millisecond ticker estimates progress between responses without additional requests. The estimate pauses when fresh playback is unavailable, and the interface distinguishes stale or offline information. The polling interval is an implementation choice, not a guaranteed Spotify allowance.

A Live Activity grants no unlimited execution time. The app does not enable silent audio or another background mode to keep polling alive. Apple schedules background refresh at its discretion; `BGAppRefreshTask` work receives up to 30 seconds rather than a continuous timer. There is no background refresh implementation in this phase. See [choosing background strategies for your app](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app). Expect lyric changes to stop when the app is suspended; do not promise uninterrupted locked-phone or vehicle updates from this local design.

## Spotify authorization and playback

The production adapter uses Authorization Code with PKCE, random verifier/state values, SHA-256 challenges, exact callback validation, and a form-encoded token exchange. No client secret is required or embedded. Pending authorization state is held in memory and consumed once. Browser cancellation, denial, duplicate/mismatched state, and stale transactions are handled. See Spotify's [PKCE tutorial](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow).

The only requested scope is `user-read-playback-state`, used with `GET https://api.spotify.com/v1/me/player`. That endpoint provides active-device information, track metadata, playing/paused state, and nullable progress/item values. It supplies no lyrics. The decoder converts milliseconds to seconds and distinguishes no active device, no current content, advertisements, episodes, local recordings, and unknown types. Missing optional album/artwork data does not discard an otherwise valid track. See [Get Playback State](https://developer.spotify.com/documentation/web-api/reference/get-information-about-the-users-current-playback).

Access-token expiry comes from `expires_in`; Spotify currently documents one-hour access tokens and six-month refresh tokens. Refreshing does not extend the refresh token's lifetime. Refresh requests include the client ID, and a replacement refresh token is persisted when supplied; otherwise the existing one is retained. An invalid grant clears credentials and requires authorization again. Concurrent refreshes share an operation; a rejected playback access token triggers one refresh/retry before credentials are invalidated. See [refreshing tokens](https://developer.spotify.com/documentation/web-api/tutorials/refreshing-tokens).

The client honors `429` and `Retry-After` before another request, and uses bounded exponential backoff for network/server failures. Playback and token endpoints each maintain a cooldown. `403` can indicate application/account permission restrictions and does not automatically erase valid credentials. There is no guaranteed universal request rate. See [rate limits](https://developer.spotify.com/documentation/web-api/concepts/rate-limits).

Playback operations are bound to the authorization revision that issued their token. Old responses cannot supply metadata, refresh or revoke a replacement account, clear a newer in-flight operation, or mutate its cooldown. Restoring storage first removes the previous in-memory session. This is enforced locally and tested with held responses; it is not a behavior guaranteed by Spotify itself.

The redirect must match the registered URI exactly. Spotify recommends Universal Links for mobile integrations and documents support for custom callback schemes; this project provides a configurable custom-scheme placeholder. Verify the current dashboard's allowed URI and the Xcode callback scheme together. HTTP localhost names are unsuitable; permitted HTTP loopback forms use literal addresses. See [redirect requirements](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri) and [the redirect-security announcement](https://developer.spotify.com/blog/2025-02-12-increasing-the-security-requirements-for-integrating-with-spotify).

Development access requires an eligible application owner and explicitly allowed users; OAuth success alone does not establish endpoint eligibility or production quota. Check current [quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes) when configuring the developer application. Spotify artwork and metadata must retain the required identification and links, and artwork must preserve its appearance. See [Spotify design guidelines](https://developer.spotify.com/documentation/design).

## Lyrics conventions and extension point

`LRCParser` supports minute/second timestamps, one to three fractional digits, repeated timestamps, metadata, Unicode, instrumental blank timed lines, and stable sorting. Invalid tags/untimed text produce line-numbered warnings; valid timestamps recover on the same or later lines. Unknown metadata is retained. Duplicates remain in source order, and the synchronization engine's upper-bound search chooses the final duplicate at an exact boundary.

File offsets and the user's correction have different explicit contracts:

| Setting | Positive value | Negative value |
| --- | --- | --- |
| LRC `[offset:...]`, in milliseconds | Adds to every timestamp and delays display | Subtracts from timestamps and advances display |
| User synchronization correction, in seconds | Adds to the playback lookup position and advances display | Subtracts from the lookup position and delays display |

For example, `[offset:+250]` moves `[00:10.00]` to 10.25 seconds. A user correction of `+0.25` selects the line at 10.25 when playback is at 10.00. File timestamps below zero clamp to zero. These are the implemented import conventions; check files from editors that use a different offset convention.

`LyricsProvider` is independent of Spotify. `LocalLRCProvider` supplies explicitly bound user imports; `MockLyricsProvider` supplies original fixtures. A future licensed provider must implement that boundary and separately resolve rights, attribution, caching, deletion, offline access, rate limits, and any playback-platform permissions. No website scraping, unofficial lyric endpoint, or commercial lyric fixture is included.

## Remaining verification

Native compilation, SwiftUI previews, callback routing, Keychain access, file protection while locked, actual ActivityKit lifecycle/payload encoding, and CarPlay layout remain subject to macOS and device testing. Verify Dynamic Type, VoiceOver, privacy changes, stale-state timing, short instrumental gaps, and long/multilingual lines. Compare wired and wireless behavior with the phone both foregrounded and locked. Record measured drift and network latency rather than treating a local clock estimate as sample-accurate playback.
