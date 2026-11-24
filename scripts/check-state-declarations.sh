#!/usr/bin/env bash
# Uses the Swift toolchain's own SwiftSyntax modules, not a network dependency.
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="$(swiftc -print-target-info | python3 -c 'import json,sys; print(json.load(sys.stdin)["paths"]["runtimeResourcePath"])')/host"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
swiftc -I "$HOST" -L "$HOST" -Xlinker -rpath -Xlinker "$HOST" scripts/check-state-declarations.swift -o "$TMP/check"
if [[ $# -gt 0 ]]; then
  "$TMP/check" "$@"
else
  find FluxIPTVMac Sources Tests -name '*.swift' -print0 | xargs -0 "$TMP/check"
fi
