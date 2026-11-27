# Validation de FLUX IPTV 0.9.6 — build 44

La 0.9.6 rend les flèches au mode souris de l’Apple TV. En 0.9.4 et en 0.9.5, une flèche de la télécommande ne déplaçait plus la sélection quand le pointeur était la télécommande.

Rien ne change sur le Mac ni sur l’iPhone. Pour le reste, les validations de la 0.9.5 ([VALIDATION-0.9.5.md](VALIDATION-0.9.5.md)) et des versions précédentes valent toujours, avec leurs limites.

Les vérifications ont été faites le 27 novembre 2026 :
- sur un Mac Apple Silicon, macOS 27.2.1, Xcode 27.2 ;
- sur l’état final des sources.

**Le résultat de GitHub Actions sur le commit livré reste la référence.** Il joue les parcours de la télécommande sous tvOS 26.5, la version la plus proche des Apple TV en tvOS 26.6.1. Le banc local, lui, tourne sous tvOS 27.2. Les mêmes parcours ont ensuite été joués sur une vraie Apple TV en tvOS 26.6.1 (voir « Sur une vraie Apple TV »).

## Exécuté

| Vérification | Résultat |
|---|---|
| Tests du cœur (`swift test`) | 202 tests, aucun échec. Le cœur ne change pas. |
| Banc Apple TV (`scripts/test-tvos-catalog-ui.sh`), simulateur Apple TV 1080p sous tvOS 27.2 | 33 écrans : focus natif sur le contrôle attendu, captures non vides. 27 parcours XCUIRemote sur 27, dont les deux nouveaux du pointeur, en 17 min 36 s. Le parcours du studio joue désormais une flèche en mode souris. |
| Apple TV 4K (1re génération), tvOS 26.6.1, téléviseur en 1080p | L’application livrée, en Release, installée et lancée : elle tourne. Puis le banc de la télécommande, compilé en Release pour l’appareil : 27 parcours XCUIRemote sur 27, en 21 minutes. |
| Compilation macOS, iOS Simulator, tvOS Simulator et tvOS ARM64 Release (`scripts/build-platforms.sh`) | Quatre « BUILD SUCCEEDED », aucun avertissement du code. Les quatre applications portent 0.9.6 (44). |
| Variante App Store pour tvOS : vérification de types avec `FLUX_APP_STORE`, sans YouTubeKit | Aucune erreur. |
| Banc Mac avec la galerie (`FLUX_CATALOG_UI_BACKGROUND=1 FLUX_CATALOG_UI_GALLERY=1 scripts/test-catalog-ui.sh`) | 88 captures hors écran, galerie comprise, et 27 parcours de touches sur 27, dont les deux du mode galerie, en sept minutes. La fin « PARTIAL » est attendue en local : les scénarios du champ de recherche demandent la fenêtre au premier plan et restent à la CI. La galerie n’avait pas été rejouée pour la 0.9.5. |

Au premier lancement des deux nouveaux parcours, aucun ne passait. Celui des réglages attendait la sélection sur Vidéo, alors que le pointeur l’avait déjà menée sur Réseau : le parcours attend désormais l’ouverture des réglages, puis lit le chemin du pointeur. Celui des messages a montré le défaut des flèches. Une fois le pointeur corrigé, les sept parcours du pointeur passent, puis tout le banc.

La CI de la 0.9.5 (`e5e24fb`) a échoué deux fois sans faute de l’application ; le détail est dans [VALIDATION-0.9.5.md](VALIDATION-0.9.5.md). La 0.9.6 accorde vingt minutes aux captures du Mac. Le parcours des zones d’une longue page appuie désormais sur Bas un à un, jusqu’à ce que le film du milieu ait la sélection.

## GitHub Actions sur le commit poussé (`75e3d4f`)

`75e3d4f` porte l’application de `80ce327`, d’où vient le dossier livré, avec les bancs et la documentation de la 0.9.6. Il a été poussé sur `main` et sur `work/three-rooms-0.9.0`, ce qui a lancé deux exécutions.

| Travail | `main` (45961939061) | branche (45961939108) |
|---|---|---|
| tvOS Simulator, tvOS 26.5 : 33 écrans et 27 parcours à la télécommande | Réussi à la relance ; la première tentative a été annulée à la limite de 110 minutes du travail, pendant les parcours | Réussi |
| tvOS ARM64 Release | Réussi | Compilation réussie ; le dépôt de l’application a expiré côté GitHub |
| iOS Simulator | Réussi | Réussi |
| macOS : compilation et bancs | Réussi, captures en 7 minutes | Réussi, captures en 9 minutes |
| Tests du cœur sous Linux | Réussi : 202 tests | Réussi |

Chaque travail réussit au moins d’un côté, et aucun échec ne vient de l’application. Sur la branche, les 27 parcours ont pris 40 minutes, compilation comprise. La machine de `main` était environ deux fois et demie plus lente : 19 minutes pour les écrans, contre 7 sur la branche. Ses parcours tournaient encore quand le travail a atteint sa limite. Relancé, le travail Apple TV de `main` réussit : 33 écrans en 9 minutes, puis 27 parcours en 42 minutes. Les six travaux passent donc sur `main`.

## Sur une vraie Apple TV

Le 27 novembre au soir, l’application de `80ce327` a été compilée en Release, signée et installée sur une Apple TV 4K (1re génération) en tvOS 26.6.1, branchée sur un téléviseur 1080p. Une fois lancée, elle tournait toujours plus d’une minute après.

Le banc de la télécommande a ensuite été compilé pour cet appareil, depuis `75e3d4f` : la même application de démonstration et le même pilote XCUIRemote que sur le simulateur, mais en Release. Les 27 parcours passent en 21 minutes, dont les sept du pointeur. Les captures retenues par les parcours viennent de l’appareil, en 1920 × 1080. Celle où le pointeur passe sur une chaîne est identique à celle du simulateur, flèche comprise.

Un premier essai, compilé en Debug comme sur le simulateur, a échoué : l’application de démonstration plantait au lancement dans 26 parcours sur 27. Le rapport de plantage montre un débordement de la pile du fil principal, pendant que Swift construit le type de la page du bureau (`FluxScreen.deskPage`). En Debug, les vues SwiftUI gardent de grandes valeurs sur la pile. Or la pile du fil principal d’une Apple TV est bien plus petite que celle du Mac, dont se sert le simulateur. La Release n’est pas touchée : l’application livrée et le banc en Release tournent.

Après les parcours, les applications du banc ont été retirées de l’Apple TV ; seule FLUX 0.9.6 (44) y reste.

## Le défaut

En mode souris, un glissement sur le pavé ne déplace que le pointeur, et une flèche déplace toujours la sélection. tvOS ne dit pas d’où vient un déplacement de la sélection. Le pointeur le refuse donc, sauf pendant un court instant après l’appui d’une flèche. Il apprenait cet appui par une reconnaissance d’appui long, de durée nulle, qui ne commence qu’au tour suivant de la boucle des événements. tvOS avait alors déjà demandé si la sélection pouvait bouger, et le pointeur avait répondu non.

Le nouveau parcours des messages l’a montré : dans la liste des chaînes, en mode souris, Bas laissait la sélection sur la même chaîne.

Désormais, le pointeur apprend l’appui d’une flèche au moment où il arrive, avant tvOS. Il laisse passer la flèche tant qu’elle est enfoncée, puis 0,6 s. Il ne retient pas l’appui, qui continue vers les écrans. Le studio d’apparence, qui demande au pointeur si une flèche déplace son curseur, suit le même chemin.

## Ce que les bancs vérifient de nouveau

Un simulateur n’a pas de pavé tactile : sous le banc seulement, l’application déplace elle-même le pointeur, contrôle par contrôle, et attend que chacun prenne la sélection. Un clic de XCUIRemote appuie ensuite sur ce que le pointeur survole.

- **Les réglages sur l’image.** Pendant la lecture d’une chaîne, le pointeur attend : l’image garde le pouce. Les réglages, ouverts aux flèches, lui rendent la main. Il passe sur Réseau dans la colonne, dont la page s’affiche, revient sur Vidéo et se pose sur un interrupteur de la page ; un clic le change. Menu referme les réglages, et l’image reprend le pouce.
- **Les messages.** Après la lecture, Menu ramène au catalogue, où le pointeur est la télécommande. Bas passe à la chaîne suivante, qui ne peut pas s’afficher ; un clic lève son message au-dessus du catalogue. Le pointeur se pose sur OK. La chaîne sous le message lui reste hors d’atteinte. Un clic sur OK referme le message et rend la sélection à la chaîne.
- **Le studio.** Une fois un thème choisi au pointeur, Haut déplace le curseur du studio.

## Non vérifié

- **Un vrai pouce** : sur l’Apple TV 4K, les parcours passent avec XCUIRemote, mais personne n’a encore essayé le mode souris avec la télécommande. Sur la télécommande, un appui sur un bord du pavé tactile passe par le même chemin qu’une flèche de XCUIRemote ; ce n’est pas vérifié sur l’appareil.
- **Un glissement** : XCUIRemote n’a pas de pavé tactile. Qu’un glissement ne déplace que le pointeur, dans les écrans comme dans le studio, reste à voir sur la télécommande.
- **Une flèche maintenue** : sa répétition, en mode souris, n’est pas jouée.
- **L’Apple TV HD** (puce A8) : la 0.9.6 n’y a pas tourné.

## Limites connues

Celles de la 0.9.5 et des versions précédentes demeurent.

En Debug, l’application de démonstration ne tient pas sur une vraie Apple TV : sa pile déborde dès la page du bureau (voir « Sur une vraie Apple TV »). L’application passe par la même page ; elle n’a pas été essayée en Debug sur l’appareil. Le schéma `FluxIPTVTV` lance la Release, sans débogueur : « Run » dans Xcode n’est pas touché. Déboguer sur l’appareil demandera d’alléger le type de cette page.
