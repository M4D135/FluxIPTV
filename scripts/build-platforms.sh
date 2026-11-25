#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  printf 'Usage: %s [macOS|iOS|tvOS|tvOS-device]\n' "$0" >&2
  exit 64
fi
if [[ $# -eq 1 ]]; then
  case "$1" in
    macOS|iOS|tvOS|tvOS-device) ;;
    *) printf 'Plateforme inconnue : %s. Choisir macOS, iOS, tvOS ou tvOS-device.\n' "$1" >&2; exit 64;;
  esac
fi

cd "$(dirname "$0")/.."
mkdir -p build/logs build/results
build_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
for target in macOS iOS tvOS tvOS-device; do
  project=FluxIPTV.xcodeproj
  configuration=Debug
  case "$target" in
    macOS) scheme=FluxIPTV; destination='platform=macOS';;
    iOS) scheme=FluxIPTViOS; destination='generic/platform=iOS Simulator';;
    tvOS) project=FluxIPTV-AppleTV.xcodeproj; scheme=FluxIPTVTV; destination='generic/platform=tvOS Simulator';;
    tvOS-device) project=FluxIPTV-AppleTV.xcodeproj; scheme=FluxIPTVTV; destination='generic/platform=tvOS'; configuration=Release;;
  esac
  if [[ $# -gt 0 && "$1" != "$target" ]]; then continue; fi
  log="$PWD/build/logs/$target-$build_id.log"
  result="$PWD/build/results/$target-$build_id.xcresult"
  if xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -configuration "$configuration" \
    -destination "$destination" \
    -derivedDataPath "$PWD/build/$target" \
    -resultBundlePath "$result" \
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build 2>&1 | tee "$log"; then
    printf '\nCompilation %s terminée. Journal : %s\n' "$target" "$log"
  else
    # Capture immediately: another command would overwrite PIPESTATUS.
    pipeline_status=("${PIPESTATUS[@]}")
    if [[ ${pipeline_status[0]} -ne 0 ]]; then
      exit "${pipeline_status[0]}"
    fi
    exit "${pipeline_status[1]}"
  fi
done
