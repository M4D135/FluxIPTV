# GitHub Actions — FLUX IPTV 0.8.8

Le workflow [Swift / Apple platforms](https://github.com/M4D135/FluxIPTV/actions/workflows/ci.yml) vérifie le commit indiqué en tête de chaque exécution. Il fonctionne sur `main`, sur les branches `work/three-rooms-*`, sur les pull requests et par lancement manuel.

## Ce que produit une exécution

| Job | Travail | Fichiers disponibles |
|---|---|---|
| Tests du cœur | Swift 6.2 sur Linux, garde syntaxique et déclarations SwiftUI, intégrité des 18 fonds et cohérence des projets Xcode partagé et Apple TV générés | Journal des tests et vérifications |
| macOS | Compilation Xcode de `FluxIPTV`, signature désactivée | Journal, résultat `.xcresult`, application compressée si la compilation réussit |
| iOS | Compilation Xcode de `FluxIPTViOS` pour simulateur | Journal, résultat `.xcresult`, application de simulateur compressée si la compilation réussit |
| tvOS | Compilation de `FluxIPTV-AppleTV.xcodeproj`, schéma `FluxIPTVTV`, pour simulateur | Journal, résultat `.xcresult`, application de simulateur compressée si la compilation réussit |
| tvOS pour appareil | Compilation ARM64 Release optimisée du même projet Apple TV, signature désactivée | Journal, résultat `.xcresult`, application non signée |
| Pack des sources | Archive de tous les fichiers suivis par Git dans le commit exécuté | ZIP complet, SHA-256 et identifiant du commit |

Les quatre compilations Apple sont indépendantes : l’échec de l’une n’annule pas les autres. Le job du pack des sources est lui aussi indépendant. Un pack disponible ne signifie donc pas que tous les tests ou toutes les compilations sont réussis.

Les jobs Apple utilisent l’image `macos-26` et Xcode **26.3** explicitement sélectionné. Une garde refuse un SDK macOS, iOS Simulator, tvOS Simulator ou tvOS pour appareil antérieur à 26. Cela empêche une compilation apparemment réussie avec l’ancien Xcode 16 de retirer silencieusement le code Liquid Glass. La version de Swift, de Xcode et des SDK est jointe aux diagnostics.

Le job macOS exécute aussi `scripts/test-youtube-session.sh` : une vraie fenêtre AppKit et une vraie WKWebView chargent le document du lecteur avec une API IFrame locale contrôlée. Le test couvre les états, la sourdine, le démarrage plein écran avec son, les commandes, les erreurs, la conservation du lecteur entre deux hôtes SwiftUI et sa libération. Il ne contacte pas YouTube et ne prouve pas la lecture d’une vidéo distante.

`scripts/test-live-preview.sh` crée une vraie vidéo locale avec AVFoundation et vérifie délai, sélection stable, annulation, repli d’URL, sourdine et nettoyage de l’aperçu TV. `scripts/test-native-youtube.sh --live` exécute les fixtures du paquet local, compile le résolveur utilisé sur tvOS et sonde deux vidéos publiques avec AVURLAsset. Un refus réseau/distant est signalé comme indisponible ; il ne devient pas une preuve de lecture. Le probe distingue résolution, readiness et lecture effective.

`scripts/test-catalog-ui.sh` capture le catalogue Mac et les fiches film/épisodes dans une vraie fenêtre SwiftUI avec jaquettes locales. `scripts/test-tvos-catalog-ui.sh` construit une copie isolée de l’app avec un catalogue local, crée son propre simulateur Apple TV et capture le direct, le catalogue des films, l’accueil sans liste, la fiche film et la saison 12 / épisode 15. Le test attend un focus natif stable, vérifie ses bornes et l’absence de SCNView. La carte de film doit aussi tenir entièrement dans le viewport natif, après conversion de son cadre vers les coordonnées de la fenêtre. Les PNG et rapports sont conservés dans les diagnostics tvOS, y compris en cas d’échec. Ce test ne contient ni flux IPTV ni lecture YouTube et n’injecte pas une fausse navigation de télécommande.

`scripts/test-keychain-interaction.sh` vérifie le pont de compatibilité Mac sans accéder aux identifiants. `scripts/check-keychain-platform.sh` type-vérifie le code réel avec les SDK iOS/tvOS et les avertissements traités comme erreurs. tvOS utilise le petit pont C vers la constante publique de refus d’interaction ; iOS utilise LAContext. La dépréciation est isolée à la fonction de compatibilité, jamais masquée sur tout le projet.

Le contrôle des SDK exige son marqueur de réussite exact dans le journal. Son tableau d'arguments est non vide sur toutes les plateformes pour rester compatible avec le Bash livré sur macOS et `set -u` ; l'erreur d'expansion d'un tableau vide ne peut plus laisser un contrôle iOS apparemment réussi.

Toutes les vérifications natives restent des étapes séparées après compilation. Leur échec bloque la livraison du job. Aucun score de fluidité sur Apple TV physique n’est déduit d’une capture ou d’un build.

Le workflow dispose uniquement de la permission GitHub `contents: read`. Il ne publie pas de release, ne modifie pas le dépôt et n’emploie aucun certificat de signature Apple. Une nouvelle exécution sur la même branche annule celle qui serait encore en cours.

## Télécharger

1. Ouvrir [Actions](https://github.com/M4D135/FluxIPTV/actions).
2. Choisir l’exécution correspondant au commit voulu et consulter les résultats de ses jobs.
3. Dans **Artifacts**, télécharger le pack des sources ou les fichiers de la plateforme voulue.
4. Pour le pack des sources, comparer l’empreinte du ZIP au fichier SHA-256 fourni et consulter le fichier indiquant le commit.

Les archives d’applications conservent leur structure et leurs permissions. Le build macOS n’est pas une distribution signée ou notariée. Les builds iOS et tvOS Simulator ciblent les simulateurs. Le build tvOS pour appareil est non signé ; ouvrir `FluxIPTV-AppleTV.xcodeproj` et sélectionner une équipe de signature pour l’installation sur une vraie Apple TV.

## Relancer

Depuis le workflow, utiliser **Run workflow** et choisir `main` ou une branche de travail. Depuis une exécution déjà terminée, **Re-run jobs** permet de retenter les jobs. Un push du correctif lance automatiquement une nouvelle exécution sur les branches couvertes.

Pour lancer localement les mêmes compilations Apple depuis un Mac disposant de Xcode :

```bash
bash scripts/build-platforms.sh macOS
bash scripts/build-platforms.sh iOS
bash scripts/build-platforms.sh tvOS
bash scripts/build-platforms.sh tvOS-device
```

Sans argument, le script compile les quatre destinations. Un argument invalide échoue immédiatement. Les logs et résultats Xcode sont écrits dans le répertoire `build/` du projet ; ce répertoire n’est pas suivi par Git.

## Lire un échec

Un job qui échoue avant l’affectation d’un runner et sans étape exécutée n’a pas compilé le projet. Lire le message de l’exécution GitHub avant de conclure à une erreur Swift. Quand Xcode a démarré, le journal et le résultat `.xcresult` permettent d’identifier les erreurs réelles. Une compilation réussie reste distincte d’un essai de lecture et de navigation sur appareil.
