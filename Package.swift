// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CarLyrics",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "LyricsCore", targets: ["LyricsCore"])
    ],
    targets: [
        .target(name: "LyricsCore"),
        .testTarget(name: "LyricsCoreTests", dependencies: ["LyricsCore"])
    ]
)
