#!/bin/bash
# Builds the application on this Mac; never asks for an administrator password.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  printf 'Cet installateur doit être lancé sur un Mac.\n' >&2
  exit 1
fi
if ! xcrun --find xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  if [[ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    printf 'Xcode complet est nécessaire pour cette première compilation.\n' >&2
    exit 1
  fi
fi
CACHE="$HOME/Library/Caches/FluxIPTV-Installer"
LOGDIR="$HOME/Library/Logs/FluxIPTV"
mkdir -p "$CACHE" "$LOGDIR"
LOG="$LOGDIR/installation-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1
STAGE=""
BACKUP=""
DEST=""
SWAPPED=0
VERIFIED=0
cleanup() {
  local rc=$?
  trap - EXIT
  if [[ "$VERIFIED" == 0 && "$SWAPPED" == 1 && -n "$STAGE" && -e "$DEST" ]]; then
    if ! mv "$DEST" "$STAGE/failed.app"; then
      printf 'Impossible de déplacer le candidat. Sauvegarde conservée : %s\n' "$BACKUP"
      STAGE=""
    fi
  fi
  if [[ "$VERIFIED" == 0 && -n "$BACKUP" && -e "$BACKUP" && ! -e "$DEST" ]]; then
    if ! mv "$BACKUP" "$DEST"; then
      printf 'Impossible de restaurer l’ancienne application. Sauvegarde conservée : %s\n' "$BACKUP"
      STAGE=""
    fi
  fi
  if [[ -n "$STAGE" && -d "$STAGE" ]]; then rm -rf -- "$STAGE"; fi
  if [[ $rc -ne 0 ]]; then
    printf '\nInstallation interrompue. Consultez le journal :\n%s\n' "$LOG"
  fi
  exit "$rc"
}
trap cleanup EXIT
if pgrep -x FluxIPTV >/dev/null 2>&1; then
  printf 'Fermez FLUX IPTV (et arrêtez son exécution dans Xcode), puis relancez cet installateur.\n'
  exit 1
fi
# Keep a single install location; do not overwrite any system-owned directory.
INSTALL_DIR="$HOME/Applications"
if [[ -d /Applications/FluxIPTV.app && -w /Applications ]]; then INSTALL_DIR=/Applications; fi
mkdir -p "$INSTALL_DIR"
DEST="$INSTALL_DIR/FluxIPTV.app"
# Prefer the same signing certificate on each install. Apple Development or
# Developer ID Application identities are accepted. With none, use ad-hoc.
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
IDENTITY_FILE="$CACHE/signing-identity"
IDENTITY="${FLUX_CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" && -f "$IDENTITY_FILE" ]]; then
  SAVED="$(cat "$IDENTITY_FILE")"
  if [[ "$SAVED" != '-' && -n "$SAVED" ]] && { printf '%s\n' "$IDENTITIES" | grep -Fq "$SAVED"; }; then IDENTITY="$SAVED"; fi
fi
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(printf '%s\n' "$IDENTITIES" | awk '/"(Apple Development|Developer ID Application):/ {print $2; exit}')"
fi
IDENTITY="${IDENTITY:--}"
printf '\nFLUX IPTV 0.9.1 — installation macOS\n\n'
if [[ "$IDENTITY" == '-' ]]; then
  printf 'Signature locale ad hoc : stable tant que cette application installée n’est pas remplacée.\nSi vous utilisez le Trousseau, une nouvelle compilation peut nécessiter une autorisation. Le stockage local privé optionnel évite cet accès.\n'
else
  printf 'Signature avec un certificat de développement/distribution Apple existant.\n'
fi
printf '\nCompilation Debug du lecteur Apple natif (VLC intégré exclu du Mac)…\n'
xcodebuild \
  -project "$ROOT/FluxIPTV.xcodeproj" -scheme FluxIPTV \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$CACHE/DerivedData-088" \
  -clonedSourcePackagesDirPath "$CACHE/SourcePackages" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  ENABLE_DEBUG_DYLIB=NO ONLY_ACTIVE_ARCH=YES build
APP="$CACHE/DerivedData-088/Build/Products/Debug/FluxIPTV.app"
[[ -d "$APP" && -x "$APP/Contents/MacOS/FluxIPTV" ]] || { printf 'Produit .app introuvable.\n'; exit 1; }
# Never install an incomplete or incorrectly signed bundle.
codesign --verify --deep --strict --verbose=2 "$APP"
STAGE="$(mktemp -d "$INSTALL_DIR/.flux-install.XXXXXX")"
ditto "$APP" "$STAGE/FluxIPTV.app"
BIN="$STAGE/FluxIPTV.app/Contents/MacOS/FluxIPTV"
# Inspect actual linkage and validate the bundled runtime before installation.
otool -L "$BIN"
otool -l "$BIN" | awk '/cmd LC_RPATH/{n=3} n>0{print;n--}'
if otool -L "$BIN" | grep -i 'VLCKit' >/dev/null || [[ -d "$STAGE/FluxIPTV.app/Contents/Frameworks/VLCKit.framework" ]]; then echo 'Le candidat Mac charge encore VLCKit : installation annulée.'; exit 1; fi
codesign --verify --deep --strict --verbose=2 "$STAGE/FluxIPTV.app"
if pgrep -x FluxIPTV >/dev/null 2>&1; then
  printf 'FLUX IPTV a été relancé durant la compilation : fermez-le et réessayez.\n'
  exit 1
fi
if [[ -e "$DEST" ]]; then
  BACKUP="$STAGE/previous.app"
  mv "$DEST" "$BACKUP"
fi
mv "$STAGE/FluxIPTV.app" "$DEST"
SWAPPED=1
codesign --verify --deep --strict --verbose=2 "$DEST"
printf '\nTest de démarrage de la version installée…\n'
open "$DEST"
PID=""
for ((i=0;i<15;i++)); do
  PID="$(pgrep -x FluxIPTV | head -n 1 || true)"
  [[ -n "$PID" ]] && break
  sleep 1
done
if [[ -z "$PID" ]]; then echo 'Aucun processus FluxIPTV après lancement.'; exit 1; fi
for ((i=0;i<8;i++)); do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo 'FluxIPTV s’est arrêté pendant le lancement.'
    echo 'Rapports de crash récents (si disponibles) :'
    find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -type f \( -name 'FluxIPTV*.ips' -o -name 'FluxIPTV*.crash' \) -mmin -5 -print 2>/dev/null || true
    exit 1
  fi
  sleep 1
done
VERIFIED=1
printf '%s\n' "$IDENTITY" > "$IDENTITY_FILE"
printf '\nApplication installée et processus encore actif : %s\n' "$DEST"
printf 'Le test vérifie le démarrage, pas la lecture vidéo. Ouvrez ensuite FLUX IPTV depuis Applications.\n'
