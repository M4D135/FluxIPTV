#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This compatibility test requires macOS and Xcode.' >&2
  exit 1
fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
smoke_root="$(mktemp -d "${TMPDIR:-/tmp}/flux-keychain-guard.XXXXXX")"
trap 'rm -rf "$smoke_root"' EXIT
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
compat_root="$repo_root/FluxIPTVMac/Compatibility"
xcrun clang -isysroot "$sdk_path" -mmacosx-version-min=14.0 \
  -Wall -Wextra -Werror -c "$compat_root/LegacyKeychainInteraction.c" \
  -o "$smoke_root/LegacyKeychainInteraction.o"
xcrun swiftc -parse-as-library -swift-version 5 -warnings-as-errors \
  -D FLUX_KEYCHAIN_TESTING -sdk "$sdk_path" -target "$(uname -m)-apple-macosx14.0" \
  -import-objc-header "$compat_root/LegacyKeychainInteraction.h" \
  "$repo_root/Sources/FluxIPTVCore/IPTVModels.swift" \
  "$repo_root/Sources/FluxIPTVCore/PrivateCredentialStore.swift" \
  "$repo_root/FluxIPTVMac/SourcePersistence.swift" \
  "$repo_root/Tests/Native/KeychainInteractionSmoke.swift" \
  "$smoke_root/LegacyKeychainInteraction.o" -o "$smoke_root/KeychainInteractionSmoke"
"$smoke_root/KeychainInteractionSmoke"
