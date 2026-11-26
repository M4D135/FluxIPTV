# GitHub Actions — FLUX IPTV 0.9.0 — build 38

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

Les jobs Apple utilisent l’image `macos-26-intel` et Xcode **26.3** explicitement sélectionné. Une garde refuse un SDK macOS, iOS Simulator, tvOS Simulator ou tvOS pour appareil antérieur à 26. Cela empêche une compilation apparemment réussie avec l’ancien Xcode 16 de retirer silencieusement le code Liquid Glass. La version de Swift, de Xcode et des SDK est jointe aux diagnostics.

Le job macOS exécute aussi `scripts/test-youtube-session.sh` : une vraie fenêtre AppKit et une vraie WKWebView chargent le document du lecteur avec une API IFrame locale contrôlée. Le test couvre les états, la sourdine, le démarrage plein écran avec son, les commandes, les erreurs, la conservation du lecteur entre deux hôtes SwiftUI et sa libération. Il ne contacte pas YouTube et ne prouve pas la lecture d’une vidéo distante.

`scripts/test-live-preview.sh` crée une vraie vidéo locale avec AVFoundation et vérifie délai, sélection stable, annulation, repli d’URL, sourdine et nettoyage de l’aperçu TV. `scripts/test-native-youtube.sh --live` exécute les fixtures du paquet local, compile le résolveur utilisé sur tvOS et sonde deux vidéos publiques avec AVURLAsset. Un refus réseau/distant est signalé comme indisponible ; il ne devient pas une preuve de lecture. Le probe distingue résolution, readiness et lecture effective.

`scripts/test-catalog-ui.sh` capture l’interface de bureau du Mac dans une vraie fenêtre SwiftUI avec un catalogue et des jaquettes locales : accueil, télévision en trois colonnes, films, fiche film, rayon des saisons, fiche série, favoris, réglages des sources, réglages du dock, réglages et liste de zapping posés sur le lecteur, et zones de l’écran. Quatre scénarios envoient les touches d’une télécommande à l’écran — Retour, flèches, OK — et échouent si la sélection n’arrive pas sur le dock, sur Actualiser, sur Accueil ou sur l’accueil. La fenêtre est lue auprès du serveur de fenêtres par le processus lui-même, ce qui restitue le verre et les matériaux sans permission d’enregistrement d’écran ; `screencapture` puis le cache de la vue restent les replis. Les fiches doivent toujours présenter un seul grand boîtier visible et la commande de lecture. En local, `FLUX_CATALOG_UI_BACKGROUND=1` garde les fenêtres hors écran et ne prend pas le premier plan ; les scénarios de focus de recherche, qui exigent la fenêtre active, ne sont alors pas exécutés et la sortie l’indique. `scripts/test-tvos-catalog-ui.sh` construit une copie isolée de l’app avec un catalogue local, crée son propre simulateur Apple TV et capture le direct, le catalogue des films, l’accueil sans liste, la fiche film et la saison 12 / épisode 15. Le test attend un focus natif stable, compare son rectangle au contrôle réellement mesuré dans la fenêtre, vérifie sa visibilité, ses bornes et l’absence de SCNView. La carte de film doit aussi tenir entièrement dans le viewport natif, après conversion de son cadre vers les coordonnées de la fenêtre et intersection des zones de découpage. Un identifiant d’accessibilité absent ne suffit jamais à valider le focus. Deux scénarios supplémentaires soumettent une recherche avec résultat et une recherche vide au traitement de production ; ils vérifient la fin du filtrage, le refus d’ouvrir un ancien résultat et le focus natif final. Les PNG et rapports sont conservés dans les diagnostics tvOS, y compris en cas d’échec. Ce test ne contient ni flux IPTV ni lecture YouTube et n’injecte pas une fausse navigation de télécommande.

`scripts/test-keychain-interaction.sh` vérifie le pont de compatibilité Mac sans accéder aux identifiants. `scripts/check-keychain-platform.sh` type-vérifie le code réel avec les SDK iOS/tvOS et les avertissements traités comme erreurs. tvOS utilise le petit pont C vers la constante publique de refus d’interaction ; iOS utilise LAContext. La dépréciation est isolée à la fonction de compatibilité, jamais masquée sur tout le projet.

Les tests du cœur couvrent aussi le dock (ordre enregistré, agrandissement sans chevauchement et sans saut, navigation selon le bord), l’historique que parcourt Retour jusqu’à l’accueil, les zones de l’écran (chacune atteignable depuis chaque autre, pour chaque bord du dock), la navigation du bureau entre colonne, grille et actions, et la détection de la langue des films et des séries dans les étiquettes de titre et de catégorie.

La couverture du cœur vérifie les 249 codes ISO de pays/territoires, leurs drapeaux et leurs noms français/anglais, puis construit un catalogue mixte et filtre séparément chacun des 249 pays. France et Espagne servent uniquement de cas de navigation native ; la détection n’est pas limitée à ces pays.

Les scénarios tvOS couvrent le bureau porté sur Apple TV : accueil, télévision, films, fiches en verre, listes d’un titre, rayon des saisons, commandes de lecture d’un direct et d’un film, langues, réglages pendant un flux, bandeau d’une chaîne en direct puis en ouverture, liste de zapping, réglages, accueil sans source, formulaire d’une source — qui doit tenir en plein écran sans défilement, son bouton d’envoi dans la zone sûre —, recherches, France, Espagne, pays dans la colonne et restauration du catalogue : vingt et une captures au total. Huit parcours XCUIRemote passent par le vrai moteur de focus : chaque zone de l’écran par les flèches seules, Menu qui retrace les écrans comme le Précédent d’un navigateur, les pays, la fiche d’un film avec ses listes et sa description, la fiche d’une série colonne par colonne, et les panneaux du lecteur sur une lecture simulée — les commandes se masquent comme pendant un flux, et les réglages puis les langues doivent garder la télécommande plus longtemps que ce délai. Ils vérifient le filtrage du modèle réel, la séparation des préférences par section et leur relecture par une nouvelle bibliothèque. Le scénario de restauration ouvre ContentView sans sélection injectée et exige le retour du focus natif sur la chaîne mémorisée. Il est exécuté trois fois, avec terminaison puis nouveau lancement du processus entre chaque passage ; chaque passage conserve les mêmes assertions et ses diagnostics. Les onze captures canoniques restent présentes.

Le contrôle des SDK exige son marqueur de réussite exact dans le journal. Son tableau d’arguments reste non vide sur toutes les plateformes pour être compatible avec le Bash livré sur macOS et `set -u` ; une erreur d’expansion ne peut plus laisser le contrôle iOS apparemment réussi.

Le banc Apple TV garde le Liquid Glass actif, comme l’application : ses contrôles de focus et de géométrie sont mesurés sur les panneaux de verre. Le rendu du verre sur appareil n’est pas mesuré ici.

Les dix parcours XCUIRemote disposent de trente minutes, compilation de leur cible comprise, et l’étape Apple TV de quarante-cinq : une machine hébergée lente a dépassé les dix minutes prévues pour quatre parcours.

Deux échecs de ces bancs ne se voient que sur les machines hébergées et ont été corrigés dans les bancs eux-mêmes : sous tvOS 26, l’identifiant du champ de recherche nomme aussi l’icône voisine, et le parcours interroge désormais le champ ; dans une fenêtre au premier plan, le premier focus natif arrive après l’ouverture et écrasait le résultat de touches envoyées trop tôt, que le banc Mac attend maintenant.

Le build 35 ajoute à cette même copie temporaire un bundle XCUITest tvOS. `XCUIRemote` envoie les directions, Valider et Menu au simulateur ; les tests attendent le focus réellement exposé par UIKit. Ils couvrent le passage France → Espagne, la réouverture et la fermeture du sélecteur, les déplacements après restauration et les commandes de reconnexion après un échec de source. Un marqueur d’accessibilité non interactif, compilé uniquement dans la fixture, permet de comparer ce focus avec la sélection dessinée par ContentView. Le résultat `.xcresult` et ses captures sont conservés ; aucun target de test n’est ajouté aux projets livrés.


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
