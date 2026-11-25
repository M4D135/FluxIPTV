#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This integration test requires macOS, AppKit, and the Xcode command-line tools." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
smoke_root="$(mktemp -d "${TMPDIR:-/tmp}/flux-youtube-smoke.XXXXXX")"
trap 'rm -rf "$smoke_root"' EXIT
smoke_app="$smoke_root/YouTubeSessionSmoke.app"
mkdir -p "$smoke_app/Contents/MacOS"
cat > "$smoke_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>YouTubeSessionSmoke</string>
  <key>CFBundleIdentifier</key><string>com.m4d135.FluxIPTV.NativeSmoke</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

xcrun swiftc -parse-as-library -swift-version 5 -D FLUX_TRAILER_TESTING \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target "$(uname -m)-apple-macosx14.0" \
  "$repo_root/Sources/FluxIPTVCore/TrailerPreview.swift" \
  "$repo_root/FluxIPTVMac/YouTubeTrailerPlayer.swift" \
  "$repo_root/Tests/Native/YouTubeSessionSmoke.swift" \
  -o "$smoke_app/Contents/MacOS/YouTubeSessionSmoke"

"$smoke_app/Contents/MacOS/YouTubeSessionSmoke" \
  "$repo_root/Tests/Native/Fixtures/YouTubeIFrameFixture.js"
