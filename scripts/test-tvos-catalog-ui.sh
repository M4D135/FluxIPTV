#!/bin/bash
# Real tvOS Simulator captures. Requires an already installed tvOS runtime;
# never downloads one, alters a user's simulator, or edits production sources.
set -euo pipefail

if [[ $# -gt 1 ]]; then
  printf 'Usage: %s [capture-directory]\n' "$0" >&2
  exit 64
fi
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This native tvOS UI test requires macOS, Xcode and an installed tvOS Simulator runtime.' >&2
  exit 1
fi
for executable in xcrun xcodebuild python3 rsync; do
  if ! command -v "$executable" >/dev/null 2>&1; then
    printf 'Required executable is missing: %s\n' "$executable" >&2
    exit 1
  fi
done
if ! xcrun --find simctl >/dev/null 2>&1; then
  echo 'Select a full Xcode installation with tvOS Simulator support before running this test.' >&2
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
capture_root="${1:-$repo_root/build/logs/tvos-catalog-ui}"
mkdir -p "$capture_root"
capture_root="$(cd "$capture_root" && pwd)"
smoke_root="$(mktemp -d "${TMPDIR:-/tmp}/flux-tvos-catalog-ui.XXXXXX")"
simulator_id=""
bundle_id='com.m4d135.FluxIPTV.TVCatalogUISmoke'

# macOS has no built-in `timeout`. Bound simulator operations and terminate
# only the command's own process group, never another developer's processes.
run_bounded() {
  python3 - "$@" <<'PY'
import os
import signal
import subprocess
import sys

seconds = float(sys.argv[1])
command = sys.argv[2:]
process = subprocess.Popen(command, start_new_session=True)
try:
    status = process.wait(timeout=seconds)
except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
    print("Timed out or interrupted: " + " ".join(command), file=sys.stderr)
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    except ProcessLookupError:
        pass
    status = 124 if isinstance(error, subprocess.TimeoutExpired) else 130
sys.exit(status if status >= 0 else 128 - status)
PY
}

cleanup() {
  if [[ -n "$simulator_id" ]]; then
    run_bounded 15 xcrun simctl terminate "$simulator_id" "$bundle_id" >/dev/null 2>&1 || true
    run_bounded 30 xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
    if ! run_bounded 30 xcrun simctl delete "$simulator_id" >/dev/null 2>&1; then
      printf 'Cleanup could not delete the temporary Flux TV UI simulator: %s\n' "$simulator_id" >&2
    fi
  fi
  rm -rf "$smoke_root"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_bounded 30 xcrun simctl list -j > "$smoke_root/simulators.json"
python3 - "$smoke_root/simulators.json" "$repo_root/FluxIPTV-AppleTV.xcodeproj/project.pbxproj" > "$smoke_root/selection.txt" <<'PY'
import json
import re
import sys

def version(value):
    parts = [int(part) for part in re.findall(r"\d+", str(value))]
    return tuple((parts + [0, 0, 0])[:3])

with open(sys.argv[1]) as file:
    inventory = json.load(file)
with open(sys.argv[2]) as file:
    targets = re.findall(r'TVOS_DEPLOYMENT_TARGET\s*=\s*([\d.]+)', file.read())
minimum = max((version(value) for value in targets), default=(17, 0, 0))
runtimes = [runtime for runtime in inventory.get("runtimes", [])
            if ".tvOS-" in runtime.get("identifier", "")
            and runtime.get("isAvailable", False)
            and version(runtime.get("version", "0")) >= minimum]
types = [device for device in inventory.get("devicetypes", [])
         if device.get("productFamily") == "Apple TV" or "Apple-TV" in device.get("identifier", "")]
for runtime in sorted(runtimes, key=lambda item: version(item.get("version", "0")), reverse=True):
    supported = {item.get("identifier") for item in runtime.get("supportedDeviceTypes", []) if isinstance(item, dict)}
    compatible = [device for device in types
                  if (not supported or device["identifier"] in supported)
                  and version(device.get("minRuntimeVersionString", "0")) <= version(runtime["version"])
                  and version(device.get("maxRuntimeVersionString", "65535")) >= version(runtime["version"])]
    # A 1080p Apple TV keeps compositor captures portable and inexpensive.
    compatible.sort(key=lambda item: ("1080p" in item.get("name", "").lower(),
                                      "4K" in item.get("name", ""), item.get("name", "")), reverse=True)
    if compatible:
        print(runtime["identifier"])
        print(compatible[0]["identifier"])
        print(runtime.get("name", runtime["identifier"]))
        print(compatible[0].get("name", compatible[0]["identifier"]))
        break
else:
    print("No available tvOS Simulator runtime/device matches this target. Install a compatible tvOS runtime in Xcode Settings > Components, then rerun. No runtime was downloaded and this check has NOT passed.", file=sys.stderr)
    sys.exit(1)
PY
{
  IFS= read -r runtime_id
  IFS= read -r device_type
  IFS= read -r runtime_name
  IFS= read -r device_name
} < "$smoke_root/selection.txt"
printf 'Native capture runtime: %s; device: %s\n' "$runtime_name" "$device_name" | tee "$capture_root/simulator.log"

smoke_repo="$smoke_root/repository"
mkdir -p "$smoke_repo"
rsync -a --exclude='.git/' --exclude='build/' --exclude='.build/' --exclude='DerivedData/' \
  "$repo_root/" "$smoke_repo/"
if [[ ! -f "$smoke_repo/Vendor/YouTubeKit/Package.swift" ]]; then
  echo 'The local Vendor/YouTubeKit package is missing. Restore the repository vendor files before running this test.' >&2
  exit 1
fi
# Only this copy's normal @main file is replaced. All views, styles, project
# settings and bundled resources are the production ones under review.
cp "$repo_root/Tests/Native/TVCatalogUISmoke.swift" "$smoke_repo/FluxIPTVMac/FluxIPTVApp.swift"
simulator_id="$(run_bounded 30 xcrun simctl create "Flux TV UI Smoke $$" "$device_type" "$runtime_id")"
if [[ ! "$simulator_id" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  echo 'simctl did not return a valid temporary simulator identifier.' >&2
  exit 1
fi
printf 'Temporary simulator: %s\n' "$simulator_id" >> "$capture_root/simulator.log"

if run_bounded 900 xcodebuild -project "$smoke_repo/FluxIPTV-AppleTV.xcodeproj" \
  -scheme FluxIPTVTV -configuration Debug -destination "platform=tvOS Simulator,id=$simulator_id" \
  -derivedDataPath "$smoke_root/DerivedData" \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG FLUX_CATALOG_UI_TESTING' \
  "PRODUCT_BUNDLE_IDENTIFIER=$bundle_id" CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build \
  > "$capture_root/build.log" 2>&1; then
  echo 'Built the native tvOS fixture with production ContentView and styles.'
else
  tail -80 "$capture_root/build.log" >&2
  printf 'Native tvOS fixture build failed. See %s\n' "$capture_root/build.log" >&2
  exit 1
fi

run_bounded 30 xcrun simctl boot "$simulator_id" >> "$capture_root/simulator.log" 2>&1
run_bounded 180 xcrun simctl bootstatus "$simulator_id" -b >> "$capture_root/simulator.log" 2>&1
fixture_app="$smoke_root/DerivedData/Build/Products/Debug-appletvsimulator/FluxIPTVTV.app"
run_bounded 30 xcrun simctl install "$simulator_id" "$fixture_app" >> "$capture_root/simulator.log" 2>&1
data_container="$(run_bounded 15 xcrun simctl get_app_container "$simulator_id" "$bundle_id" data)"
ready_file="$data_container/Library/Caches/FluxTVCatalogUI-ready.json"
failed=0
for scenario in movie movies series live welcome; do
  case "$scenario" in
    movie) filename='movie-detail.png' ;;
    movies) filename='movie-catalog.png' ;;
    series) filename='series-s12-e15-detail.png' ;;
    live) filename='live-catalog.png' ;;
    welcome) filename='welcome.png' ;;
  esac
  rm -f "$ready_file" "$capture_root/$scenario-ready.json" "$capture_root/$filename"
  if ! run_bounded 30 env "SIMCTL_CHILD_FLUX_UI_SCENARIO=$scenario" xcrun simctl launch \
    "--stdout=$capture_root/$scenario-stdout.log" "--stderr=$capture_root/$scenario-stderr.log" \
    "$simulator_id" "$bundle_id" >> "$capture_root/simulator.log" 2>&1; then
    printf 'Failed to launch the %s scenario.\n' "$scenario" >&2
    failed=1
  fi
  ready=false
  for ((attempt = 0; attempt < 30; attempt++)); do
    if [[ -f "$ready_file" ]]; then
      cp "$ready_file" "$capture_root/$scenario-ready.json"
      ready=true
      break
    fi
    sleep 1
  done
  # Retain compositor evidence even when readiness/focus assertions failed.
  if ! run_bounded 20 xcrun simctl io "$simulator_id" screenshot --type=png "$capture_root/$filename" \
    >> "$capture_root/simulator.log" 2>&1; then failed=1; fi
  if [[ "$ready" != true ]]; then
    printf 'No readiness report for %s after 30 seconds; its screenshot is diagnostic only.\n' "$scenario" >&2
    failed=1
  elif ! python3 - "$capture_root/$scenario-ready.json" "$scenario" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    report = json.load(file)
print(json.dumps(report, ensure_ascii=False, indent=2))
if (report.get("status") != "ready" or report.get("scenario") != sys.argv[2]
        or report.get("boundedNativeFocus") is not True
        or report.get("largeEnoughNativeControl") is not True
        or report.get("sceneKitViewMounted") is not False):
    print("Native focus/detail readiness failed; screenshot retained for inspection.", file=sys.stderr)
    sys.exit(1)
if sys.argv[2] == "series" and report.get("requestedEpisodeID") != "fixture-series-s12-e15":
    print("The episode 15 restoration fixture was not selected.", file=sys.stderr)
    sys.exit(1)
if sys.argv[2] == "live" and report.get("selectedItemID") != "fixture-live-0":
    print("The live fixture did not select its first channel.", file=sys.stderr)
    sys.exit(1)
if sys.argv[2] == "movies" and report.get("selectedItemID") != "fixture-movie-1":
    print("The movie catalogue fixture did not select its second poster.", file=sys.stderr)
    sys.exit(1)
if sys.argv[2] == "movies" and report.get("fullyVisibleNativeFocus") is not True:
    print("The focused movie card extends outside its visible safe viewport.", file=sys.stderr)
    sys.exit(1)
if sys.argv[2] == "welcome" and report.get("selectedItemID") != "":
    print("The welcome fixture unexpectedly selected catalogue content.", file=sys.stderr)
    sys.exit(1)
PY
  then failed=1; fi
  run_bounded 15 xcrun simctl terminate "$simulator_id" "$bundle_id" >> "$capture_root/simulator.log" 2>&1 || true
done

# Validate actual simctl PNGs with Apple's decoder. No third-party Python image
# packages are required, and the images remain available even on assertion failure.
cat > "$smoke_root/ValidateCaptures.swift" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO

var failed = false
for path in CommandLine.arguments.dropFirst() {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let context = CGContext(data: nil, width: 96, height: 54, bitsPerComponent: 8, bytesPerRow: 96 * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
        fputs("FAIL: Missing or unreadable simulator PNG: \(path)\n", stderr)
        failed = true
        continue
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: 96, height: 54))
    var low = 255, high = 0, visible = 0, bright = 0
    for pixel in 0..<(96 * 54) where bytes[pixel * 4 + 3] > 20 {
        visible += 1
        let luminance = (3 * Int(bytes[pixel * 4]) + 6 * Int(bytes[pixel * 4 + 1]) + Int(bytes[pixel * 4 + 2])) / 10
        low = min(low, luminance); high = max(high, luminance)
        if luminance > 190 { bright += 1 }
    }
    let nonempty = image.width >= 1920 && image.height >= 1080 && visible > 4000 && high - low > 35
    print("\(URL(fileURLWithPath: path).lastPathComponent): \(image.width)×\(image.height), luminance range=\(high - low), bright fraction=\(Double(bright) / Double(max(1, visible))), nonempty=\(nonempty)")
    if !nonempty { failed = true }
}
exit(failed ? 1 : 0)
SWIFT
if ! run_bounded 120 xcrun swift -module-cache-path "$smoke_root/ModuleCache" "$smoke_root/ValidateCaptures.swift" \
  "$capture_root/movie-detail.png" "$capture_root/movie-catalog.png" "$capture_root/series-s12-e15-detail.png" \
  "$capture_root/live-catalog.png" "$capture_root/welcome.png" \
  > "$capture_root/capture-validation.log" 2>&1; then failed=1; fi
cat "$capture_root/capture-validation.log"

if [[ "$failed" -ne 0 ]]; then
  printf 'FAIL: Native tvOS UI capture checks failed. Review PNGs and logs in %s\n' "$capture_root" >&2
  exit 1
fi
printf 'PASS: Native tvOS film detail, movie catalogue, S12/E15, live catalogue and welcome screens have bounded initial focus and nonempty compositor captures.\n'
printf 'Review the PNGs in %s for actual glass, readable menus, channel size, clipping and episode restoration.\n' "$capture_root"
printf 'This checks initial native focus and layout only; remote navigation, physical Apple TV rendering and trailer playback still need their own verification.\n'
