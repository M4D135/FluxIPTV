#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This visual integration test requires macOS and the Xcode command-line tools." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
capture_root="${1:-$repo_root/build/logs/catalog-ui}"
smoke_root="$(mktemp -d "${TMPDIR:-/tmp}/flux-catalog-ui.XXXXXX")"
trap 'rm -rf "$smoke_root"' EXIT
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

"$smoke_app/Contents/MacOS/CatalogUISmoke" "$capture_root"
