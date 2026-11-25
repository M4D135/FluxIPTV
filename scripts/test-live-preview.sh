#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This integration test requires macOS and the Xcode command-line tools." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
smoke_root="$(mktemp -d "${TMPDIR:-/tmp}/flux-live-smoke.XXXXXX")"
trap 'rm -rf "$smoke_root"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -D FLUX_LIVE_PREVIEW_TESTING \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target "$(uname -m)-apple-macosx14.0" \
  "$repo_root/Sources/FluxIPTVCore/LiveTVPreviewDelay.swift" \
  "$repo_root/FluxIPTVMac/LiveTVPreviewController.swift" \
  "$repo_root/Tests/Native/LiveTVPreviewSmoke.swift" \
  -o "$smoke_root/LiveTVPreviewSmoke"
"$smoke_root/LiveTVPreviewSmoke"
