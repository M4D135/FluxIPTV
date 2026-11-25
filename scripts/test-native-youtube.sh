#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Native YouTube smoke requires macOS and Xcode command-line tools." >&2
  exit 1
fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
smoke_root="$(mktemp -d "${TMPDIR:-/tmp}/flux-native-youtube.XXXXXX")"
trap 'rm -rf "$smoke_root"' EXIT
package_root="$repo_root/Vendor/YouTubeKit"
package_build="$smoke_root/package"
xcrun swift test --package-path "$package_root" --scratch-path "$package_build"
xcrun swift build --package-path "$package_root" --scratch-path "$package_build" --product YouTubeKit
package_bin="$(xcrun swift build --package-path "$package_root" --scratch-path "$package_build" --show-bin-path)"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -parse-as-library -swift-version 5 -D FLUX_NATIVE_YOUTUBE_TESTING \
  -sdk "$sdk_path" -target "$(uname -m)-apple-macosx14.0" \
  -I "$package_bin/Modules" -L "$package_bin" -lYouTubeKit \
  -framework AVFoundation -framework JavaScriptCore -framework VideoToolbox \
  "$repo_root/Sources/FluxIPTVCore/TrailerPreview.swift" \
  "$repo_root/FluxIPTVMac/NativeYouTubeTrailerResolver.swift" \
  "$repo_root/Tests/Native/NativeYouTubeSmoke.swift" \
  -o "$smoke_root/NativeYouTubeSmoke"
if [[ -d "$package_bin/YouTubeKit_YouTubeKit.bundle" ]]; then
  cp -R "$package_bin/YouTubeKit_YouTubeKit.bundle" "$smoke_root/"
fi
"$smoke_root/NativeYouTubeSmoke" "$@"
