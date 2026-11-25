#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This API compatibility check requires macOS and Xcode.' >&2
  exit 1
fi
case "${1:-}" in
  iOS) sdk=iphonesimulator; triple=arm64-apple-ios17.0-simulator ;;
  tvOS) sdk=appletvsimulator; triple=arm64-apple-tvos17.0-simulator ;;
  tvOS-device) sdk=appletvos; triple=arm64-apple-tvos17.0 ;;
  *) echo 'Usage: check-keychain-platform.sh [iOS|tvOS|tvOS-device]' >&2; exit 64 ;;
esac

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
check_root="$(mktemp -d "${TMPDIR:-/tmp}/flux-keychain-api.XXXXXX")"
trap 'rm -rf "$check_root"' EXIT
sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
compat_root="$repo_root/FluxIPTVMac/Compatibility"
# Bash 3.2 treats an empty array expansion as unset under nounset. Keep the
# compiler argument array nonempty on iOS, where no bridge header is needed.
swift_args=(-typecheck -parse-as-library -swift-version 5 -warnings-as-errors
  -sdk "$sdk_path" -target "$triple")
if [[ "$sdk" != iphonesimulator ]]; then
  # Real tvOS headers, including availability and CF ownership annotations.
  # No credential operation or authentication request is performed.
  xcrun clang -isysroot "$sdk_path" -target "$triple" \
    -Wall -Wextra -Werror -c "$compat_root/LegacyKeychainInteraction.c" \
    -o "$check_root/LegacyKeychainInteraction.o"
  swift_args+=(-import-objc-header "$compat_root/LegacyKeychainInteraction.h")
fi
xcrun swiftc "${swift_args[@]}" \
  "$repo_root/Sources/FluxIPTVCore/IPTVModels.swift" \
  "$repo_root/Sources/FluxIPTVCore/PrivateCredentialStore.swift" \
  "$repo_root/FluxIPTVMac/SourcePersistence.swift"
printf 'PASS: silent Keychain APIs compile without warnings for %s; no credentials accessed.\n' "$1"
