#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Le projet Apple TV doit être ouvert dans Xcode sur un Mac.' >&2
  exit 1
fi
project_root="$(cd "$(dirname "$0")" && pwd)"
project_path="$project_root/FluxIPTV-AppleTV.xcodeproj"
if [[ ! -f "$project_path/project.pbxproj" ]]; then
  echo 'Projet introuvable : décompressez le dossier complet avant de lancer ce fichier.' >&2
  exit 1
fi
printf '\nFLUX IPTV — Apple TV\n\n'
printf 'Schéma : FluxIPTVTV\nDestination : un simulateur Apple TV, ou votre Apple TV jumelée.\n'
printf 'Pour une vraie Apple TV : choisissez votre équipe dans Signing & Capabilities.\n'
printf 'Guide complet : LISEZ-MOI APPLE TV.txt\n\n'
open -a Xcode "$project_path"
