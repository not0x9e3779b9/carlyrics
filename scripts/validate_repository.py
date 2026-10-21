"""Check tracked project files and configuration without reading local secrets."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN_SUFFIXES = {".p12", ".p8", ".pfx", ".key", ".mobileprovision", ".cer", ".xcuserstate"}
SECRET_PATTERNS = (
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"),
    re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
    re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{40,}\b"),
    re.compile(rb"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(rb"\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\b"),
)
APPLE_IMPORTS = re.compile(r"^\s*import\s+(UIKit|SwiftUI|ActivityKit|WidgetKit|AuthenticationServices|Security)\b", re.M)


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args], cwd=ROOT)


def inspect_file(name: str, data: bytes) -> list[str]:
    path = PurePosixPath(name)
    issues = []
    if path.name == "Config.local.xcconfig" or path.name == ".env" or (path.name.startswith(".env.") and path.name != ".env.example"):
        issues.append(f"Local configuration is tracked: {name}")
    if path.suffix.lower() in FORBIDDEN_SUFFIXES or any(part in {"DerivedData", "xcuserdata", ".build", ".swiftpm"} for part in path.parts):
        issues.append(f"Private signing material or local build state is tracked: {name}")
    if any(pattern.search(data) for pattern in SECRET_PATTERNS):
        issues.append(f"Potential credential detected in {name}; value suppressed")
    if not name.startswith(("Tests/", "scripts/")):
        literal = re.compile(rb'''\b(?:client_?secret|access_?token|refresh_?token)["']?\s*[:=]\s*["'](?!REPLACE_|YOUR_|\$\()[^"'\r\n]{8,}["']''', re.I)
        # Swift enum raw values describe response field names, not credentials.
        declaration_lines = b"\n".join(line for line in data.splitlines() if not line.lstrip().startswith(b"case "))
        if literal.search(declaration_lines):
            issues.append(f"Literal authentication material detected in {name}; value suppressed")
    if name.startswith("Sources/LyricsCore/") and APPLE_IMPORTS.search(data.decode("utf-8", errors="replace")):
        issues.append(f"Platform-only import in portable core: {name}")
    return issues


def configuration_issues(example: str, spec: str) -> list[str]:
    required = ["SPOTIFY_CLIENT_ID", "SPOTIFY_REDIRECT_URI", "SPOTIFY_CALLBACK_SCHEME", "APP_BUNDLE_IDENTIFIER",
                "WIDGET_BUNDLE_IDENTIFIER", "APP_GROUP_IDENTIFIER", "DEVELOPMENT_TEAM", "SPOTIFY_LYRICS_ENABLED"]
    issues = [f"Missing example configuration key: {key}" for key in required if not re.search(rf"^{key}\s*=", example, re.M)]
    if not re.search(r"^SPOTIFY_LYRICS_ENABLED\s*=\s*NO\s*$", example, re.M):
        issues.append("Example configuration must keep Spotify lyric synchronization disabled")
    if "SPOTIFY_CLIENT_SECRET" in example:
        issues.append("The public-client configuration must not define a client secret")
    for reference in ["CarLyricsApp", "ApplePlatformServices", "Shared", "CarLyricsLiveActivity"]:
        if not (ROOT / "ios" / reference).is_dir():
            issues.append(f"Missing iOS source directory: {reference}")
    for required_text in ["'26.0'", "NSSupportsLiveActivities: true", "com.apple.widgetkit-extension", "product: SpotifyIntegration"]:
        if required_text not in spec:
            issues.append(f"Missing project setting: {required_text}")
    if "UIBackgroundModes" in spec or "com.apple.developer.carplay" in spec:
        issues.append("Unexpected background mode or CarPlay entitlement")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="Inspect index contents instead of working files")
    args = parser.parse_args()
    names = [name.decode("utf-8") for name in git("ls-files", "-z").split(b"\0") if name]
    issues = []
    for name in names:
        try:
            data = git("show", f":{name}") if args.staged else (ROOT / name).read_bytes()
        except OSError:
            issues.append(f"Tracked file is unavailable: {name}")
            continue
        issues.extend(inspect_file(name, data))
    def read(name: str) -> str:
        return (git("show", f":{name}") if args.staged else (ROOT / name).read_bytes()).decode("utf-8")
    issues.extend(configuration_issues(read("Config.example.xcconfig"), read("ios/project.yml")))
    if any(name.startswith("ios/CarLyrics.xcodeproj/") for name in names):
        issues.append("Generated Xcode project is tracked")
    for name in ["Config.local.xcconfig", ".env", "signing.p12", "profile.mobileprovision", "DerivedData/build.log"]:
        if subprocess.run(["git", "check-ignore", "-q", "--", name], cwd=ROOT).returncode != 0:
            issues.append(f"Expected ignore rule missing for {name}")
    print(json.dumps({"tracked_files_checked": len(names), "issues": issues}, indent=2))
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
