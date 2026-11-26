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
# In a git worktree .git is a file, not a directory: leave both out.
rsync -a --exclude='.git' --exclude='build/' --exclude='.build/' --exclude='DerivedData/' \
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
# A freshly migrated CI simulator can install slowly after bootstatus succeeds.
# Keep installation bounded without changing any native scenario deadline.
run_bounded 120 xcrun simctl install "$simulator_id" "$fixture_app" >> "$capture_root/simulator.log" 2>&1
data_container="$(run_bounded 15 xcrun simctl get_app_container "$simulator_id" "$bundle_id" data)"
ready_file="$data_container/Library/Caches/FluxTVCatalogUI-ready.json"
failed=0
capture_paths=()
# Retain every restoration attempt while exposing only the last successful one
# through the twenty-one canonical gallery paths. Never reuse an older run's pair.
rm -f "$capture_root/live-restored-ready.json" "$capture_root/live-restored.png" \
  "$capture_root/live-restored-stdout.log" "$capture_root/live-restored-stderr.log"
for capture_case in home movie movies lists series seasons live player player-film player-tracks player-settings zapping settings welcome add-source search-empty search-result live-fr live-es country-picker live-restored:1 live-restored:2 live-restored:3; do
  scenario="${capture_case%%:*}"
  capture_label="$scenario"
  scenario_root="$capture_root"
  if [[ "$scenario" == live-restored ]]; then
    capture_label="live-restored-attempt-${capture_case#*:}"
    scenario_root="$capture_root/repeats/$capture_label"
  fi
  mkdir -p "$scenario_root"
  scenario_failed=0
  printf 'Native tvOS scenario: %s\n' "$capture_label"
  case "$scenario" in
    movie) filename='movie-detail.png' ;;
    movies) filename='movie-catalog.png' ;;
    lists) filename='favorite-lists.png' ;;
    series) filename='series-s12-e15-detail.png' ;;
    seasons) filename='series-seasons.png' ;;
    live) filename='live-catalog.png' ;;
    home) filename='home.png' ;;
    player) filename='player-live.png' ;;
    player-film) filename='player-film.png' ;;
    player-tracks) filename='player-languages.png' ;;
    player-settings) filename='player-settings.png' ;;
    zapping) filename='player-zapping.png' ;;
    settings) filename='settings-sources.png' ;;
    welcome) filename='welcome.png' ;;
    add-source) filename='add-source.png' ;;
    search-empty) filename='search-empty.png' ;;
    search-result) filename='search-result.png' ;;
    live-fr) filename='live-france.png' ;;
    live-es) filename='live-spain.png' ;;
    country-picker) filename='live-country-picker.png' ;;
    live-restored) filename='live-restored.png' ;;
  esac
  rm -f "$ready_file" "$scenario_root/$scenario-ready.json" "$scenario_root/$filename" \
    "$scenario_root/$scenario-stdout.log" "$scenario_root/$scenario-stderr.log"
  # Terminate any surviving fixture process before each launch, including repeats.
  if ! run_bounded 30 env "SIMCTL_CHILD_FLUX_UI_SCENARIO=$scenario" xcrun simctl launch --terminate-running-process \
    "--stdout=$scenario_root/$scenario-stdout.log" "--stderr=$scenario_root/$scenario-stderr.log" \
    "$simulator_id" "$bundle_id" >> "$capture_root/simulator.log" 2>&1; then
    printf 'Failed to launch the %s scenario.\n' "$capture_label" >&2
    scenario_failed=1
  fi
  ready=false
  for ((attempt = 0; attempt < 30; attempt++)); do
    if [[ -f "$ready_file" ]]; then
      cp "$ready_file" "$scenario_root/$scenario-ready.json"
      ready=true
      break
    fi
    sleep 1
  done
  # A fresh tvOS simulator may show its first-use Control Center tip over the
  # first screenshot. Let that system overlay expire after readiness is proven.
  if [[ "$scenario" == home && "$ready" == true ]]; then sleep 10; fi
  # Retain compositor evidence even when readiness/focus assertions failed.
  if ! run_bounded 20 xcrun simctl io "$simulator_id" screenshot --type=png "$scenario_root/$filename" \
    >> "$capture_root/simulator.log" 2>&1; then scenario_failed=1; fi
  capture_paths+=("$scenario_root/$filename")
  if [[ "$ready" != true ]]; then
    printf 'No readiness report for %s after 30 seconds; its screenshot is diagnostic only.\n' "$capture_label" >&2
    scenario_failed=1
  elif ! python3 - "$scenario_root/$scenario-ready.json" "$scenario" <<'PY'
import json
import sys

with open(sys.argv[1]) as file:
    report = json.load(file)
print(json.dumps(report, ensure_ascii=False, indent=2))
if (report.get("status") != "ready" or report.get("scenario") != sys.argv[2]
        or report.get("boundedNativeFocus") is not True
        or report.get("largeEnoughNativeControl") is not True
        or report.get("expectedControlFrameObserved") is not True
        or report.get("expectedControlProbeCount") != 1
        or report.get("nativeFocusMatchesExpectedControl") is not True
        or report.get("sceneKitViewMounted") is not False):
    print("Native focus/detail readiness failed; screenshot retained for inspection.", file=sys.stderr)
    sys.exit(1)
if sys.argv[2] == "series" and report.get("requestedEpisodeID") != "fixture-series-s12-e15":
    print("The episode 15 restoration fixture was not selected.", file=sys.stderr)
    sys.exit(1)
if sys.argv[2] in ("movie", "series"):
    if (any(report.get(key) is not True for key in ("detailBoxTested", "detailBoxLargeEnough", "detailBoxFullyVisible"))
            or report.get("detailBoxProbeCount") != 1
            or report.get("detailTrailerControlIDs") != []
            or report.get("detailPlayerLayerCount") != 0
            or report.get("detailWebViewCount") != 0):
        print("The film/series detail must show one large visible box without trailer controls or a mounted player.", file=sys.stderr)
        sys.exit(1)
if sys.argv[2] == "live" and report.get("selectedItemID") != "fixture-live-0":
    print("The live fixture did not select its first channel.", file=sys.stderr)
    sys.exit(1)
if sys.argv[2] == "movies" and report.get("selectedItemID") != "fixture-movie-1":
    print("The movie catalogue fixture did not select its second poster.", file=sys.stderr)
    sys.exit(1)
if sys.argv[2] in ("movies", "search-result") and report.get("fullyVisibleNativeFocus") is not True:
    print("The focused movie card extends outside its visible safe viewport.", file=sys.stderr)
    sys.exit(1)
if sys.argv[2] == "welcome" and report.get("selectedItemID") != "":
    print("The welcome fixture unexpectedly selected catalogue content.", file=sys.stderr)
    sys.exit(1)
if sys.argv[2] == "add-source":
    if (report.get("sourceFormTested") is not True
            or report.get("sourceFormSubmitProbeCount") != 1
            or report.get("sourceFormSubmitVisible") is not True
            or report.get("sourceFormScrolls") is not False
            or report.get("fullyVisibleNativeFocus") is not True):
        print("The source form must fill the screen: its submit button inside the safe area, nothing to scroll.", file=sys.stderr)
        sys.exit(1)
if sys.argv[2].startswith("search-"):
    required = ("searchSubmissionTested", "searchDeferredDuringFiltering", "searchSettledOnExpectedTarget",
                "searchResultsMatch", "searchRejectedStaleActivation")
    if any(report.get(key) is not True for key in required):
        print("The production search submit/filter/activation assertions did not pass.", file=sys.stderr)
        sys.exit(1)
    expected_control, expected_focus, expected_results = (
        ("navigation-tab-movie", "tab-movie", []) if sys.argv[2] == "search-empty"
        else ("catalog-card-fixture-movie-0", "fixture-movie-0", ["fixture-movie-0"]))
    if (report.get("expectedInitialControlIdentifier") != expected_control
            or report.get("searchExpectedFocusID") != expected_focus
            or report.get("searchResultIDs") != expected_results):
        print("The search scenario did not target its expected movie tab/result.", file=sys.stderr)
        sys.exit(1)
if sys.argv[2] in ("live-fr", "live-es", "country-picker", "live-restored"):
    required = ("countryFilterTested", "countrySelectionMatches", "countryFilteringSettled",
                "countryResultsMatch", "countryAvailableCountsMatch", "countryUnclassifiedRetained",
                "fullyVisibleNativeFocus")
    if any(report.get(key) is not True for key in required):
        print("The production country filter, inventory or visible focus assertions did not pass.", file=sys.stderr)
        sys.exit(1)
    if sys.argv[2] == "live-restored":
        expected_code, expected_ids = "FR", ["fixture-country-fr-1"]
    elif sys.argv[2] == "live-es":
        expected_code, expected_ids = "ES", ["fixture-country-es-0", "fixture-country-es-1"]
    else:
        expected_code, expected_ids = "FR", ["fixture-country-fr-0", "fixture-country-fr-1", "fixture-country-fr-2"]
    expected_control = "live-country-option-FR" if sys.argv[2] == "country-picker" else "live-channel-" + expected_ids[0]
    if (report.get("countryCode") != expected_code
            or report.get("countryResultIDs") != expected_ids
            or report.get("selectedItemID") != expected_ids[0]
            or report.get("expectedInitialControlIdentifier") != expected_control
            or report.get("countryAvailableCounts") != {"FR": 3, "ES": 2, "GB": 2, "unclassified": 2}
            or report.get("countryPickerRequested") is not (sys.argv[2] == "country-picker")):
        print("The country scenario did not preserve the intended mixed catalogue and selected control.", file=sys.stderr)
        sys.exit(1)
if sys.argv[2] == "live-restored":
    if (report.get("browsingUIRestorationTested") is not True
            or report.get("browsingUIRestorationMatches") is not True
            or report.get("browsingUISelectionSeeded") is not False
            or report.get("browsingRestoredGroup") != "[FR] Cinéma"
            or report.get("browsingRestoredSearch") != "Grand écran"
            or report.get("browsingRestoredGroupSearch") != "Cin"
            or report.get("browsingRestoredItemID") != "fixture-country-fr-1"):
        print("The actual UI did not restore persisted filters and native focus without a seeded selection.", file=sys.stderr)
        sys.exit(1)
if sys.argv[2] == "country-picker":
    required = ("browsingPersistenceTested", "browsingSectionRoundTripPassed", "browsingStoredDataObserved",
                "browsingRecreationPassed", "browsingRefreshPassed", "browsingMediaContextsIndependent")
    if any(report.get(key) is not True for key in required):
        print("Browsing filters did not survive section changes, preferences recreation and catalogue refresh.", file=sys.stderr)
        sys.exit(1)
PY
  then scenario_failed=1; fi
  run_bounded 15 xcrun simctl terminate "$simulator_id" "$bundle_id" >> "$capture_root/simulator.log" 2>&1 || true
  if [[ "$scenario_failed" -ne 0 ]]; then
    failed=1
  elif [[ "$scenario" == live-restored ]]; then
    cp "$scenario_root/$filename" "$capture_root/$filename"
    cp "$scenario_root/$scenario-ready.json" "$capture_root/$scenario-ready.json"
    for stream in stdout stderr; do
      if [[ -f "$scenario_root/$scenario-$stream.log" ]]; then
        cp "$scenario_root/$scenario-$stream.log" "$capture_root/$scenario-$stream.log"
      fi
    done
  fi
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
  "${capture_paths[@]}" \
  > "$capture_root/capture-validation.log" 2>&1; then failed=1; fi
cat "$capture_root/capture-validation.log"

# Add the UI-test runner only after the unchanged capture checks. The delivered
# projects stay untouched, and XCTest attachments live inside this xcresult,
# keeping the twenty-one canonical gallery PNG paths unchanged.
rm -rf "$capture_root/remote-navigation.xcresult" "$capture_root/remote-navigation-attachments"
rm -f "$capture_root/remote-navigation.log" "$capture_root/remote-attachments-export.log"
if python3 "$repo_root/scripts/add-tvos-remote-test-target.py" \
  --smoke-repository "$smoke_repo" --app-bundle-id "$bundle_id" \
  > "$capture_root/remote-target.log" 2>&1 \
  && run_bounded 30 plutil -lint "$smoke_repo/FluxIPTV-AppleTV.xcodeproj/project.pbxproj" \
  >> "$capture_root/remote-target.log" 2>&1; then
  # Eight flows: a hosted Intel runner needed more than ten minutes for six.
  if run_bounded 1500 xcodebuild -project "$smoke_repo/FluxIPTV-AppleTV.xcodeproj" \
    -scheme FluxIPTVTVRemoteNavigation -configuration Debug \
    -destination "platform=tvOS Simulator,id=$simulator_id" \
    -derivedDataPath "$smoke_root/DerivedData" -parallel-testing-enabled NO \
    -resultBundlePath "$capture_root/remote-navigation.xcresult" \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG FLUX_CATALOG_UI_TESTING' \
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test \
    > "$capture_root/remote-navigation.log" 2>&1; then
    echo 'PASS: XCUIRemote country selection in the column, every zone by the arrows alone, Menu retracing the screens down to the home screen, film fiche with its lists and description, series fiche by columns, player panels during a stream, restored-channel reentry and failed-source reconnect highlight.'
  else
    failed=1
    tail -100 "$capture_root/remote-navigation.log" >&2
  fi
else
  failed=1
  cat "$capture_root/remote-target.log" >&2
fi

# Export original attachments and Xcode's manifest even after test failures so
# the actual remote-action screenshots can be reviewed without a Mac/Xcode.
if [[ -d "$capture_root/remote-navigation.xcresult" ]]; then
  if run_bounded 30 xcrun xcresulttool help export attachments \
    > "$capture_root/remote-attachments-export.log" 2>&1 \
    && run_bounded 60 xcrun xcresulttool export attachments \
    --path "$capture_root/remote-navigation.xcresult" \
    --output-path "$capture_root/remote-navigation-attachments" \
    >> "$capture_root/remote-attachments-export.log" 2>&1; then
    printf 'Exported original XCTest attachments and manifest to %s\n' "$capture_root/remote-navigation-attachments"
  else
    failed=1
    echo 'FAIL: Could not export the XCTest remote-navigation attachments.' >&2
    tail -60 "$capture_root/remote-attachments-export.log" >&2
  fi
else
  failed=1
  echo 'FAIL: No remote-navigation xcresult was produced; no remote-action evidence is available.' >&2
fi

if [[ "$failed" -ne 0 ]]; then
  printf 'FAIL: Native tvOS UI capture or remote-navigation checks failed. Review PNGs, xcresult and logs in %s\n' "$capture_root" >&2
  exit 1
fi
printf 'PASS: Twenty-one native tvOS scenarios have bounded focus matching the measured intended control and nonempty compositor captures; both production search submissions reject stale activation; France, Spain and the country picker preserve the mixed catalogue; browsing filters survive section changes, preferences recreation and catalogue refresh; the actual UI restores saved filters and native focus without a seeded selection on all three cold launches.\n'
printf 'Review the PNGs in %s for actual glass, readable menus, channel size, clipping, episode restoration and country selection.\n' "$capture_root"
printf 'XCUIRemote also checks native simulator navigation with retained XCTest screenshots; physical Apple TV hardware rendering and provider playback still need their own verification.
'
