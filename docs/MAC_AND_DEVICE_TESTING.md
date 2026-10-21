# Mac, iPhone, and CarPlay testing

These are future acceptance steps. Windows cannot perform them. An unsigned CI build does not establish device, signing, or vehicle acceptance. Perform vehicle setup while parked.

## Mac setup

1. Install Xcode 26 or newer with the iOS 26 SDK on a supported Mac. Launch it, accept the license, and install iPhone simulator components. Check Apple's [Xcode support matrix](https://developer.apple.com/support/xcode/).
2. Select and inspect the toolchain:

   ```sh
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   xcodebuild -version
   xcodebuild -showsdks
   swift --version
   ```

3. Install XcodeGen 2.44+ with `brew install xcodegen` if Homebrew is configured, or follow its [official release instructions](https://github.com/yonaskolb/XcodeGen/releases). Verify with `xcodegen --version`.
4. Clone and prepare the project:

   ```sh
   git clone https://github.com/not0x9e3779b9/carlyrics.git
   cd carlyrics
   git switch feature/carplay-live-lyrics
   swift test --parallel
   python3 scripts/validate_repository.py
   cp Config.example.xcconfig Config.local.xcconfig
   ```

5. Set unique app and widget bundle IDs and your Apple development team in the ignored local configuration. The extension ID must start with the app ID followed by a dot. The app group is a reserved placeholder; no app-group entitlement or shared container is enabled. Keep `SPOTIFY_LYRICS_ENABLED = NO` unless Spotify permission and lyric rights are resolved.
6. Create a Spotify developer application, copy its public client ID into local configuration, and add your listener to its test allowlist where required. Check current Development Mode requirements; an authorized listener may still receive 403 without API access. Never embed a client secret.
7. Register the exact expanded redirect URI. The example expands to `carlyrics://callback`. Custom schemes remain documented for native apps. Universal Links are preferred for production but require associated-domain and browser callback changes; do not simply replace the scheme with HTTPS in the present implementation.
8. Generate and open the project:

   ```sh
   xcodegen generate --spec ios/project.yml --project ios
   open ios/CarLyrics.xcodeproj
   ```

   Re-run generation after editing project.yml. The Xcode project and Info.plist files are generated and ignored.
9. Select the `CarLyrics` scheme in Xcode. In Signing & Capabilities, select your team for both `CarLyrics` and `CarLyricsLiveActivity` and verify the IDs. Use automatic signing. No CarPlay audio entitlement, background audio mode, Keychain sharing group, or app group is required. The app's `NSSupportsLiveActivities` and embedded WidgetKit extension provide Live Activity support.

## Simulator and iPhone

10. Compile without signing:

    ```sh
    xcodebuild -project ios/CarLyrics.xcodeproj -scheme CarLyrics \
      -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
    ```

    Select an installed iOS 26+ iPhone simulator and Run for interactive testing. Inspect Lock Screen, Dynamic Island, private, stale, and small previews. Simulator results do not establish vehicle compatibility.
11. Connect a physical iPhone, trust the Mac, enable Developer Mode if prompted, choose the phone as destination, and Run with signing enabled. Resolve trust/provisioning prompts locally; never commit signing material.
12. Start **Try lyric rehearsal**. It uses original synthetic words and an independent clock and plays no audio. Check first-line waiting, instrumental gaps, exact boundaries, before/after timing, and nearby lines.
13. In Settings, connect Spotify. Verify consent requests only playback reading; test browser cancellation, callback return, and successful authorization. Play a Spotify track and check title, artist, album, artwork, progress, pause status, and Listen on Spotify. Real Spotify remains metadata-only by default.
14. Copy `Examples/LanternRoad.lrc` to Files on the iPhone. In rehearsal, import and match it in Lyrics. Confirm reimport retains earlier documents but replaces the binding, relaunch restores the library, and deleting the active document clears its match. Try malformed/empty files, Unicode, UTF-8/UTF-16, oversized files, and provider failures.
15. Adjust timing in Now Playing. Positive user values show lines earlier; positive file `[offset:]` delays timestamps by milliseconds. Check negative values and Reset.
16. Start the Live Activity. Privacy defaults to hiding details: verify only generic information appears. Enable details while parked and inspect Lock Screen, compact, expanded, and small surfaces. Stop and verify dismissal. Test disabled Live Activities, system/user dismissal, and restoration after relaunch.
17. Pause/resume and seek ±5 seconds in rehearsal. In Spotify, use Spotify's controls, since CarLyrics has no playback-control permission. Check foreground correction, track changes, no device/playback, advertisements, episodes, unsupported/local items, and missing lyrics. Actual Spotify lyric synchronization requires separate permission.
18. Test offline/recovery, controlled mock rate limits, expired/revoked authorization, refresh, storage failure, and disconnect/reconnect. Local disconnect removes credentials; revoke account access separately in Spotify settings. Reports must omit credentials and callback contents.
19. Lock/background the phone. Verify stale presentation and that the app does not claim ongoing lyric advancement. Reopen and verify correction. Test app termination, reboot, system dismissal, eight-hour expiry, and restoring an existing activity. No backend or unlimited background execution is implemented.

## Vehicle acceptance

20. Connect the iPhone directly to factory wired CarPlay. While parked, start the Live Activity and check the system-selected Dashboard/notification surface and relevant iPhone/CarPlay settings. iOS controls placement; the small layout is non-interactive. Test display sizes and zoom settings where available.
21. Repeat with the wireless adapter unchanged. Do not flash firmware, install files, or modify protocols. Record any transport-related differences in visibility or freshness.
22. Check larger Dynamic Type, VoiceOver on the phone, Reduced Motion, light/dark mode, daylight/night contrast, long metadata, Unicode, privacy redaction, paused/stale/unsupported states, and details toggles. Small layouts omit nearby lines to keep the current information readable.
23. If the surface does not appear, check system settings and active activity status, then retry direct wired CarPlay. Fall back to the foreground phone or Lock Screen safely while parked; do not bypass restrictions.
24. Record date, commit, Xcode/iOS version, iPhone model, vehicle/head unit, wired/wireless connection, display zoom, steps, expected/actual behavior, and redacted screenshots. Record timing error, stale delay, clipping, and placement separately. Treat untested combinations as unverified.
