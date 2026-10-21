// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CarLyrics",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "LyricsCore", targets: ["LyricsCore"]),
        .library(name: "SpotifyIntegration", targets: ["SpotifyIntegration"])
    ],
    targets: [
        .target(name: "LyricsCore"),
        .testTarget(name: "LyricsCoreTests", dependencies: ["LyricsCore"]),
        .target(name: "SpotifyIntegration", dependencies: ["LyricsCore"], path: "ios/SpotifyIntegration"),
        .testTarget(name: "SpotifyIntegrationTests", dependencies: ["SpotifyIntegration"], path: "Tests/SpotifyIntegrationTests")
    ]
)
