# Implementation plan

- [x] Inspect environment, existing identity, and GitHub authentication.
- [x] Establish specification, development documentation, and repository structure.
- [ ] Push private repository foundation on main; switch to feature branch.
- [ ] Implement portable lyrics models, resilient LRC parser, binary-search synchronization, providers, and deterministic tests.
- [ ] Implement Spotify PKCE, secure-storage boundary, refresh, decoding, playback client, error handling, mocks, and tests.
- [ ] Implement SwiftUI navigation, onboarding, playback, importing/matching, offsets, settings, diagnostics, and accessibility.
- [ ] Implement ActivityKit lifecycle and compact/small WidgetKit layouts with privacy and stale-state handling.
- [ ] Add CI, reproducible project generation, configuration/repository validation, and expanded tests.
- [ ] Complete documentation and final verification; push final milestone and update draft PR.

## Later acceptance gates

- [ ] Resolve Spotify synchronization permission and lyric rights before production use.
- [ ] Run native builds and previews with Xcode and validate simulator behavior.
- [ ] Configure real Spotify application and perform device OAuth testing.
- [ ] Validate iPhone signing, background behavior, privacy, and system dismissal.
- [ ] Validate wired CarPlay, then wireless transport, without adapter changes.
