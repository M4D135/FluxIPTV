#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This integration test requires macOS, SceneKit, and the Xcode command-line tools." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
capture_root="${1:-$repo_root/build/logs/case-scene}"
smoke_root="$(mktemp -d "${TMPDIR:-/tmp}/flux-case-scene.XXXXXX")"
trap 'rm -rf "$smoke_root"' EXIT
smoke_app="$smoke_root/CaseSceneSmoke.app"
mkdir -p "$smoke_app/Contents/MacOS" "$capture_root"
cat > "$smoke_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CaseSceneSmoke</string>
  <key>CFBundleIdentifier</key><string>com.m4d135.FluxIPTV.CaseSceneSmoke</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

# Compile the production coordinator and its real support sources. Only the
# fixture entry point and conditional accessors belong to the test harness.
xcrun swiftc -parse-as-library -swift-version 5 -D FLUX_CASE_TESTING \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target "$(uname -m)-apple-macosx14.0" \
  "$repo_root"/Sources/FluxIPTVCore/*.swift \
  "$repo_root/FluxIPTVMac/ArtworkView.swift" \
  "$repo_root/FluxIPTVMac/GlassStyle.swift" \
  "$repo_root/FluxIPTVMac/Case3DView.swift" \
  "$repo_root/Tests/Native/CaseSceneSmoke.swift" \
  -o "$smoke_app/Contents/MacOS/CaseSceneSmoke"

"$smoke_app/Contents/MacOS/CaseSceneSmoke" "$capture_root"
