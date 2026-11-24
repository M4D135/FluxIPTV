# GitHub Actions — FLUX IPTV 0.8.4

Le workflow [Swift / Apple platforms](https://github.com/M4D135/FluxIPTV/actions/workflows/ci.yml) vérifie le commit indiqué en tête de chaque exécution. Il fonctionne sur `main`, sur les branches `work/three-rooms-*`, sur les pull requests et par lancement manuel.

## Ce que produit une exécution

| Job | Travail | Fichiers disponibles |
|---|---|---|
| Tests du cœur | Swift 6.2 sur Linux, garde des déclarations SwiftUI, intégrité des 18 fonds et cohérence du projet Xcode généré | Journal des tests et vérifications |
| macOS | Compilation Xcode de `FluxIPTV`, signature désactivée | Journal, résultat `.xcresult`, application compressée si la compilation réussit |
| iOS | Compilation Xcode de `FluxIPTViOS` pour simulateur | Journal, résultat `.xcresult`, application de simulateur compressée si la compilation réussit |
| tvOS | Compilation Xcode de `FluxIPTVTV` pour simulateur | Journal, résultat `.xcresult`, application de simulateur compressée si la compilation réussit |
| Pack des sources | Archive de tous les fichiers suivis par Git dans le commit exécuté | ZIP complet, SHA-256 et identifiant du commit |

Les trois compilations Apple sont indépendantes : l’échec de l’une n’annule pas les autres. Le job du pack des sources est lui aussi indépendant. Un pack disponible ne signifie donc pas que tous les tests ou toutes les compilations sont réussis.

Le workflow dispose uniquement de la permission GitHub `contents: read`. Il ne publie pas de release, ne modifie pas le dépôt et n’emploie aucun certificat de signature Apple. Une nouvelle exécution sur la même branche annule celle qui serait encore en cours.

## Télécharger

1. Ouvrir [Actions](https://github.com/M4D135/FluxIPTV/actions).
2. Choisir l’exécution correspondant au commit voulu et consulter les résultats de ses jobs.
3. Dans **Artifacts**, télécharger le pack des sources ou les fichiers de la plateforme voulue.
4. Pour le pack des sources, comparer l’empreinte du ZIP au fichier SHA-256 fourni et consulter le fichier indiquant le commit.

Les archives d’applications conservent leur structure et leurs permissions. Le build macOS n’est pas une distribution signée ou notariée. Les builds iOS/tvOS ciblent les simulateurs ; pour un appareil physique, ouvrir le projet dans Xcode et sélectionner une équipe de signature.

## Relancer

Depuis le workflow, utiliser **Run workflow** et choisir `main` ou une branche de travail. Depuis une exécution déjà terminée, **Re-run jobs** permet de retenter les jobs. Un push du correctif lance automatiquement une nouvelle exécution sur les branches couvertes.

Pour lancer localement les mêmes compilations Apple depuis un Mac disposant de Xcode :

```bash
bash scripts/build-platforms.sh macOS
bash scripts/build-platforms.sh iOS
bash scripts/build-platforms.sh tvOS
```

Sans argument, le script compile les trois plateformes. Un argument invalide échoue immédiatement. Les logs et résultats Xcode sont écrits dans le répertoire `build/` du projet ; ce répertoire n’est pas suivi par Git.

## Lire un échec

Un job qui échoue avant l’affectation d’un runner et sans étape exécutée n’a pas compilé le projet. Lire le message de l’exécution GitHub avant de conclure à une erreur Swift. Quand Xcode a démarré, le journal et le résultat `.xcresult` permettent d’identifier les erreurs réelles. Une compilation réussie reste distincte d’un essai de lecture et de navigation sur appareil.
