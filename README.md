# FLUX IPTV 🍏

**Lecteur IPTV natif pour macOS**, développé en SwiftUI et AVKit, avec un cœur réseau/playlist en Swift `Foundation` réutilisable pour un futur portage **Apple TV (tvOS)**.

## Première version : 0.1.0

- Connexion à un serveur compatible **Xtream Codes Player API** avec adresse du serveur, identifiant et mot de passe.
- Import de **playlist M3U distante** (URL) ou **locale** (`.m3u`, `.m3u8` servant de liste de chaînes).
- Catalogue des **chaînes en direct**, des **films VOD Xtream**, catégories, recherche, logos, favoris.
- Lecture intégrée via **AVPlayer / VideoPlayer** ; priorité aux flux HLS `.m3u8`.
- Choix du format Xtream Live `.m3u8` ou `.ts` à la création de la source.
- Plusieurs sources, actualisation, suppression, bibliothèque persistée.
- **Mots de passe et URL de playlists distantes enregistrés dans le Trousseau macOS**, et non dans les préférences ; fichiers M3U importés copiés localement sous Application Support.
- Projet Xcode **sans dépendance externe**. Aucun contenu, compte, fournisseur ou service IPTV n'est inclus.

## Construire et lancer

**Prérequis :** Mac avec **macOS 14 ou ultérieur**, Xcode 16 ou ultérieur recommandé.

1. Cloner ce dépôt.
2. Ouvrir `FluxIPTV.xcodeproj` dans Xcode.
3. Choisir le schéma `FluxIPTV` et la destination **My Mac**.
4. Lancer avec **⌘R**.

En terminal sur macOS :

```bash
./scripts/build-macos.sh
```

Pour tester le moteur indépendant de l'UI (possible aussi sur Linux avec Swift 5.9+) :

```bash
swift test
```

## Mode d'emploi

Cliquez sur **Ajouter une source**, puis sélectionnez :

- **Xtream Codes** : URL de base du serveur (`https://mon-serveur.example:8080`), identifiant, mot de passe. Sélectionnez HLS si disponible.
- **URL M3U** : lien HTTP(S) vers une playlist de chaînes.
- **Fichier M3U** : fichier local sélectionné depuis le Mac.

Choisissez ensuite une chaîne ou un film. La petite étoile permet de la placer dans les favoris. Le menu contextuel d'une source permet de la supprimer, y compris ses identifiants du Trousseau.

## Limites de cette version

- **AVPlayer dépend des formats et codecs pris en charge par macOS**. Certains flux TS, MKV, AC3, flux non-HLS ou variantes Xtream ne seront pas décodables. Un lecteur vidéo alternatif pourra être ajouté plus tard si nécessaire.
- Pas encore d'**EPG XMLTV**, de **séries / épisodes Xtream**, de sous-titres externes, de contrôle parental ni de replay.
- Les attributs M3U propriétaires (`#EXTVLCOPT`, headers HTTP spécifiques, DRM) ne sont pas encore interprétés.
- Pour des serveurs IPTV qui ne proposent que HTTP, une exception ATS globale est présente dans `Info.plist`. **Elle est volontairement documentée et devra être réduite/justifiée avant une distribution App Store**. Privilégiez les fournisseurs HTTPS : les identifiants envoyés en HTTP ne sont pas chiffrés sur le réseau.
- Le projet **n'a pas encore été compilé avec Xcode sur un Mac** dans cet environnement. Le cœur Swift est testé automatiquement ; la CI macOS effectuera la validation de l'interface après publication.

## Architecture

```text
FluxIPTV.xcodeproj/             Application native macOS
FluxIPTVMac/                   Interface, lecteur, Trousseau, persistance
Sources/FluxIPTVCore/          Modèles, parseur M3U, client Xtream (Foundation seul)
Tests/FluxIPTVCoreTests/       Tests unitaires Swift Package Manager
Package.swift                  Cible Core autonome, portable tvOS
.github/workflows/ci.yml       Tests + build macOS via GitHub Actions
scripts/generate-xcodeproj.py  Générateur reproductible du projet Xcode
```

Le dossier `FluxIPTVCore` est compilé directement dans la cible macOS, mais reste aussi une librairie Swift indépendante pour les tests et le portage. La future UI tvOS pourra compiler et utiliser ces mêmes sources sans embarquer AppKit.

## Roadmap

Voir [docs/ROADMAP.md](docs/ROADMAP.md) pour la suite du projet.

## Utilisation et droits

Utiliser uniquement des playlists, flux et accès auxquels vous êtes autorisé. L'application n'offre aucun contenu et ne contourne aucune protection DRM. Aucun identifiant utilisateur ne doit être commité dans ce dépôt.

© 2026 M4D135. Tous droits réservés à ce stade.