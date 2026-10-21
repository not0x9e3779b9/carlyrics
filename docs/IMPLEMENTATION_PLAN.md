# Implementation plan

- [x] Inspect environment, existing identity, and GitHub authentication.
- [x] Establish specification, development documentation, and repository structure.
- [x] Push private repository foundation on main; switch to feature branch.
- [x] Implement portable lyrics models, resilient LRC parser, binary-search synchronization, providers, and deterministic tests.
- [x] Implement Spotify PKCE, secure-storage boundary, refresh, decoding, playback client, error handling, mocks, and tests.
- [x] Implement SwiftUI navigation, onboarding, playback, importing/matching, offsets, settings, diagnostics, and accessibility.
- [x] Implement ActivityKit lifecycle and compact/small WidgetKit layouts with privacy and stale-state handling.
- [x] Add CI, reproducible project generation, configuration/repository validation, and expanded tests.
- [x] Verify hosted portable tests and unsigned app/widget compilation under Xcode 26.6.
- [x] Complete documentation and final verification; push final milestone and update draft PR.

## Later acceptance gates

- [ ] Resolve Spotify synchronization permission and lyric rights before production use.
- [ ] Validate interactive previews and simulator behavior locally with Xcode.
- [ ] Configure real Spotify application and perform device OAuth testing.
- [ ] Validate iPhone signing, background behavior, privacy, and system dismissal.
- [ ] Validate wired CarPlay, then wireless transport, without adapter changes.
