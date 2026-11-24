# FLUX IPTV 0.8.4 — Correctifs issus de GitHub Actions

Version du 24 novembre 2026, build 17, à partir du pack complet 0.8.3 publié sur `main` au commit `7ef1cf8199e5d27ff6d64a1625fbd61d4c5a586c`.

## Résultats natifs obtenus sur la base 0.8.3

Après le passage du dépôt en public, la [deuxième tentative de l’exécution 45495499497](https://github.com/M4D135/FluxIPTV/actions/runs/45495499497/attempts/2) a effectivement démarré les runners.

- macOS : compilation Xcode réussie et application archivée.
- iOS Simulator : compilation Xcode réussie et application archivée.
- Pack complet des sources : créé avec SHA-256 et identifiant du commit.
- tvOS Simulator : échec sur un appel `controlSize`, indisponible sur tvOS.
- Tests du cœur : installation de Swift interrompue, car `ubuntu-latest` utilisait Ubuntu 26.04, non pris en charge par la version utilisée de l’action d’installation. Aucun test du cœur n’avait été exécuté dans ce job.

Ces compilations macOS/iOS confirment notamment que les corrections MainActor et de chargement des pistes de la 0.8.3 passent le compilateur Apple. Les tests locaux du cœur et les tests ciblés précédents restent documentés dans [VALIDATION-0.8.3.md](VALIDATION-0.8.3.md).

## Corrections 0.8.4

Les deux appels `controlSize` de l’application, dans `AddSourceSheet` et `PlayerSurface`, sont maintenant conditionnés à `!os(tvOS)`. macOS et iOS conservent leurs tailles d’indicateur ; tvOS utilise le composant natif à sa taille par défaut. L’analyse syntaxique des deux fichiers corrigés réussit pour les trois triples de compilation Apple.

La première exécution 0.8.4, [45497345108](https://github.com/M4D135/FluxIPTV/actions/runs/45497345108), a ensuite validé les 98 tests du cœur, le pack des sources et les compilations macOS/iOS. tvOS a signalé une autre différence d’API : `LongPressGesture(minimumDuration:maximumDistance:)` n’y est pas disponible. La carte emploie désormais sur tvOS l’initialiseur spécifique `LongPressGesture(minimumDuration:)`. La durée de 0,65 seconde, l’action des favoris et le geste simultané sont conservés ; le seuil de déplacement tactile de 14 points reste utilisé sur macOS/iOS.

Les jobs Linux utilisent explicitement `ubuntu-24.04`. Le système est consigné dans un journal avant l’installation de Swift, pour conserver un diagnostic même en cas d’échec de cette étape. Les trois compilations Apple restent sur `macos-15`.

La version affichée, le projet Xcode, l’agent utilisateur des métadonnées et l’installateur passent à 0.8.4. L’installateur utilise `DerivedData-084`. Les 18 fonds, les réglages et les identifiants d’application sont conservés.

## Contrôle du workflow et des archives

Le workflow et chacun de ses blocs shell ont été vérifiés. Dix cas de commande ont vérifié le script de compilation, notamment les arguments invalides, la capture de stdout/stderr et la propagation du code d’erreur Xcode même si `tee` échoue également.

Le job indépendant de sources utilise le commit effectivement extrait par Actions. Il archive tous les fichiers suivis par Git, conserve l’exécutable de l’installateur, puis fournit le ZIP, son SHA-256 et `COMMIT.txt`. Les archives d’applications sont produites après une compilation réussie et les diagnostics sont conservés même après un échec. Les artefacts sont disponibles 14 jours.

## Validation de cette version

Consulter l’[exécution GitHub Actions du commit 0.8.4](https://github.com/M4D135/FluxIPTV/actions/workflows/ci.yml) pour le résultat de chaque plateforme. Ce document décrit les corrections et les résultats de la base qui les ont motivées ; il ne préjuge pas du statut d’une exécution ultérieure. Un pack de sources disponible ne signifie pas que tous les jobs sont réussis.

La compilation native et les tests unitaires ne remplacent pas un essai de lecture, de navigation au trackpad ou à la Siri Remote et de fonctionnement du fournisseur IPTV sur les appareils visés. Les builds Actions sont non signés pour distribution ; iOS et tvOS ciblent les simulateurs. Le pack complet garde l’installateur pour compiler sur le Mac de l’utilisateur et le projet pour signer sur appareil physique.
