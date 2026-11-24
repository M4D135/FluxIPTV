#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for target in macOS iOS tvOS; do
  case "$target" in
    macOS) scheme=FluxIPTV; destination='platform=macOS';;
    iOS) scheme=FluxIPTViOS; destination='generic/platform=iOS Simulator';;
    tvOS) scheme=FluxIPTVTV; destination='generic/platform=tvOS Simulator';;
  esac
  if [[ $# -gt 0 && "$1" != "$target" ]]; then continue; fi
  xcodebuild -project FluxIPTV.xcodeproj -scheme "$scheme" -configuration Debug -destination "$destination" -derivedDataPath "$PWD/build/$target" CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build
done
