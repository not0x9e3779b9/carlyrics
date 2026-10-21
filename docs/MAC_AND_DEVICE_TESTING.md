# Mac and device testing

This guide will be completed with exact generated scheme/build commands once the project definition exists. None of the native or physical steps has been run on the Windows development host.

Required acceptance sequence: install Xcode with the iOS 26 SDK or newer, install XcodeGen, generate/open the project, configure app and extension identifiers and signing team, configure Spotify's exact redirect URI, add ignored local configuration, build for a simulator, install on an iPhone, authenticate, import the synthetic LRC fixture, start/stop the Live Activity, test pause/resume/seeks/track changes, then test wired CarPlay followed by the unchanged wireless bridge. Record layout, synchronization, stale behavior, privacy, and fallback results while parked. No custom CarPlay entitlement or adapter installation is involved.
