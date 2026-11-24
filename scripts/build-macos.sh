#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild \
  -project FluxIPTV.xcodeproj \
  -scheme FluxIPTV \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$PWD/build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build
printf '\nBuild créé dans build/DerivedData/Build/Products/Debug/FluxIPTV.app\n'
