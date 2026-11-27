# Validation de FLUX IPTV 0.9.6 — build 44

La 0.9.6 rend les flèches au mode souris de l’Apple TV. En 0.9.4 et en 0.9.5, une flèche de la télécommande ne déplaçait plus la sélection quand le pointeur était la télécommande.

Rien ne change sur le Mac ni sur l’iPhone. Pour le reste, les validations de la 0.9.5 ([VALIDATION-0.9.5.md](VALIDATION-0.9.5.md)) et des versions précédentes valent toujours, avec leurs limites.

Les vérifications ont été faites le 27 novembre 2026 :
- sur un Mac Apple Silicon, macOS 27.2.1, Xcode 27.2 ;
- sur l’état final des sources.

**Le résultat de GitHub Actions sur le commit livré reste la référence.** Il joue les parcours de la télécommande sous tvOS 26.5, la version la plus proche des Apple TV en tvOS 26.6.1. Le banc local, lui, tourne sous tvOS 27.2.

## Exécuté

| Vérification | Résultat |
|---|---|
| Tests du cœur (`swift test`) | 202 tests, aucun échec. Le cœur ne change pas. |
| Banc Apple TV (`scripts/test-tvos-catalog-ui.sh`), simulateur Apple TV 1080p sous tvOS 27.2 | 33 écrans : focus natif sur le contrôle attendu, captures non vides. 27 parcours XCUIRemote sur 27, dont les deux nouveaux du pointeur, en 17 min 36 s. Le parcours du studio joue désormais une flèche en mode souris. |
| Compilation macOS, iOS Simulator, tvOS Simulator et tvOS ARM64 Release (`scripts/build-platforms.sh`) | Quatre « BUILD SUCCEEDED », aucun avertissement du code. Les quatre applications portent 0.9.6 (44). |
| Variante App Store pour tvOS : vérification de types avec `FLUX_APP_STORE`, sans YouTubeKit | Aucune erreur. |

Au premier lancement des deux nouveaux parcours, aucun ne passait. Celui des réglages attendait la sélection sur Vidéo, alors que le pointeur l’avait déjà menée sur Réseau : le parcours attend désormais l’ouverture des réglages, puis lit le chemin du pointeur. Celui des messages a montré le défaut des flèches. Une fois le pointeur corrigé, les sept parcours du pointeur passent, puis tout le banc.

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

- **Apple TV physique** : rien de la 0.9.6, ni du mode souris des versions précédentes. Le pointeur n’a jamais suivi un vrai pouce. Sur la télécommande, un appui sur un bord du pavé tactile passe par le même chemin qu’une flèche de XCUIRemote ; ce n’est pas vérifié sur l’appareil.
- **Un glissement** : XCUIRemote n’a pas de pavé tactile. Qu’un glissement ne déplace que le pointeur, dans les écrans comme dans le studio, reste à voir sur la télécommande.
- **Une flèche maintenue** : sa répétition, en mode souris, n’est pas jouée.
- **tvOS 26** : seul le banc hébergé, sous tvOS 26.5, joue les parcours dans cette version.

## Limites connues

Celles de la 0.9.5 et des versions précédentes demeurent.
