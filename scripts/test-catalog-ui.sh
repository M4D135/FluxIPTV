#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This visual integration test requires macOS and the Xcode command-line tools." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
capture_root="${1:-$repo_root/build/logs/catalog-ui}"
smoke_root="$(mktemp -d "${TMPDIR:-/tmp}/flux-catalog-ui.XXXXXX")"
capture_accessibility_changed=false
capture_previous_transparency=""
capture_previous_motion=""
cleanup() {
  if [[ "$capture_accessibility_changed" == true ]]; then
    if [[ -n "$capture_previous_transparency" ]]; then
      defaults write com.apple.universalaccess reduceTransparency -bool "$capture_previous_transparency"
    else
      defaults delete com.apple.universalaccess reduceTransparency >/dev/null 2>&1 || true
    fi
    if [[ -n "$capture_previous_motion" ]]; then
      defaults write com.apple.universalaccess reduceMotion -bool "$capture_previous_motion"
    else
      defaults delete com.apple.universalaccess reduceMotion >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$smoke_root"
}
trap cleanup EXIT
smoke_app="$smoke_root/CatalogUISmoke.app"
mkdir -p "$smoke_app/Contents/MacOS" "$smoke_app/Contents/Resources/RoomBakes" "$capture_root"
cat > "$smoke_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CatalogUISmoke</string>
  <key>CFBundleIdentifier</key><string>com.m4d135.FluxIPTV.CatalogUISmoke</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([0-9.]*\);/\1/p' "$repo_root/FluxIPTV.xcodeproj/project.pbxproj" | sort -u)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $version" "$smoke_app/Contents/Info.plist"

# Copy only the production room assets actually used by these two captures.
for room in livingRoom-neo90 cinema-neo90; do
  cp "$repo_root/FluxIPTVMac/RoomBakes/$room.jpg" "$smoke_app/Contents/Resources/RoomBakes/"
done

# All real app sources, with only its ordinary @main entry point omitted.
production_sources=()
for source in "$repo_root"/FluxIPTVMac/*.swift; do
  if [[ "${source##*/}" != "FluxIPTVApp.swift" ]]; then
    production_sources+=("$source")
  fi
done
xcrun swiftc -parse-as-library -swift-version 5 -D FLUX_CATALOG_UI_TESTING \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target "$(uname -m)-apple-macosx14.0" \
  "$repo_root"/Sources/FluxIPTVCore/*.swift \
  "${production_sources[@]}" \
  "$repo_root/Tests/Native/CatalogUISmoke.swift" \
  -o "$smoke_app/Contents/MacOS/CatalogUISmoke"

# Hosted images explicitly disable graphic effects. The fixture's SwiftUI
# environment selects the normal app branches; the native AppKit material also
# needs the temporary CI user's system preferences restored to normal before
# this new process starts. A developer's personal settings are never changed.
if [[ "${GITHUB_ACTIONS:-false}" == true ]]; then
  capture_previous_transparency="$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || true)"
  capture_previous_motion="$(defaults read com.apple.universalaccess reduceMotion 2>/dev/null || true)"
  printf 'CI accessibility before capture: reduceTransparency=%s reduceMotion=%s\n' "${capture_previous_transparency:-unset}" "${capture_previous_motion:-unset}"
  capture_accessibility_changed=true
  defaults write com.apple.universalaccess reduceTransparency -bool false
  defaults write com.apple.universalaccess reduceMotion -bool false
  printf 'CI accessibility for native capture: reduceTransparency=%s reduceMotion=%s\n' \
    "$(defaults read com.apple.universalaccess reduceTransparency)" "$(defaults read com.apple.universalaccess reduceMotion)"
fi

"$smoke_app/Contents/MacOS/CatalogUISmoke" "$capture_root"
