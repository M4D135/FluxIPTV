# Validation de FLUX IPTV 0.9.2 — build 40

La 0.9.2 répare le dock de l’Apple TV en tvOS 26. Le reste est celui de la 0.9.1 : sa validation, dans [VALIDATION-0.9.1.md](VALIDATION-0.9.1.md), et celle de la 0.9.0, dans [VALIDATION-0.9.0.md](VALIDATION-0.9.0.md), valent toujours, avec leurs limites.

Les vérifications ci-dessous ont été faites le 26 novembre 2026 sur un Mac Apple Silicon, macOS 27.2.1, Xcode 27.2, sur l’état final des sources. **Le résultat de GitHub Actions sur le commit livré reste la référence**, ici plus que jamais : il joue les parcours de la télécommande sous tvOS 26.5, la version la plus proche des Apple TV en tvOS 26.6.1, et le défaut corrigé ne se produisait pas sous tvOS 27.2.

## Le défaut

Signalé le 26 novembre sur Apple TV : « la barre dock ne fonctionne pas sur appletv, j’ai que le son mais reste sur icône tv », puis « pas d’effet changement de taille sur appletv ».

Depuis `e56f4dd` (0.9.0), le dock d’une télévision dessinait sa sélection et son agrandissement d’après le focus du système, lu dans la liaison de focus que possède la fenêtre. tvOS 27 redessine le dock quand cette liaison change ; tvOS 26, d’après ce qu’on voyait sur l’Apple TV, ne le fait pas. La sélection avançait bien dans la barre — d’où le son —, mais le dock restait dessiné comme avant, sur l’icône de l’écran, et ne grossissait pas. Les parcours de la télécommande ne vérifiaient que le focus du système, jamais ce que le dock dessine.

## La correction

- Chaque icône du dock, et chaque titre d’un dossier ouvert, signale elle-même au dock qu’elle a la télécommande, comme le font déjà les jaquettes, les chaînes et les touches. Le dock dessine sa sélection et grossit autour d’elle d’après ces signaux, quelle que soit la version de tvOS. L’écran derrière lui n’est toujours pas reconstruit à chaque appui.
- Le panneau audio et sous-titres du lecteur lisait la même liaison. Chaque ligne y lit maintenant son propre focus.
- Sur Mac, rien ne change : le dock et ce panneau suivent la sélection du clavier comme avant.

## Exécuté

| Vérification | Résultat |
|---|---|
| `scripts/generate-xcodeproj.py` | les deux projets générés sont à jour, en 0.9.2 build 40 |
| Compilations | macOS, iOS Simulator, tvOS Simulator et tvOS appareil |
| `scripts/test-tvos-catalog-ui.sh` | réussi : 31 scénarios et 19 parcours XCUIRemote, dont le nouveau, sous tvOS 27.2, Apple TV 4K (4e génération) en 1080p |
| `scripts/test-catalog-ui.sh` en mode local, avec la galerie | non rejoué : sur Mac, le dock et le panneau du lecteur suivent toujours la sélection du clavier et dessinent la même chose qu’en 0.9.1. Ce banc est passé dans l’exécution hébergée de la 0.9.1, et celle de la 0.9.2 le rejoue |
| Banc de la session YouTube | ses sources se compilent de nouveau seules (voir plus bas) |
| `swift test` | non rejoué : le cœur (`Sources/FluxIPTVCore`) n’a pas changé depuis la 0.9.1, dont les tests du cœur sont passés dans l’exécution hébergée |

## Le parcours ajouté

Un dix-neuvième parcours XCUIRemote, « le dock dessiné là où est la télécommande », compare à chaque appui l’icône qui a le focus du système et ce que le dock dessine. Le banc de l’application expose ce que le dock dessine ; l’application elle-même n’expose rien.

- Dans les films, la télécommande descend dans le dock. Elle va jusqu’à Films, puis fait Droite, Droite, Gauche, Gauche, Gauche. Après chaque appui, le dock doit dessiner sélectionnée et agrandie l’icône qui a le focus. Remontée dans le catalogue, plus rien du dock n’est dessiné sélectionné ni agrandi.
- Sur l’accueil, même contrôle le long de la grande barre.
- Dans un dossier du dock ouvert sur son premier titre, l’icône du dossier reste agrandie pendant qu’on parcourt ses titres.

Sous tvOS 27.2, le défaut ne se produisait pas : ce parcours n’y montre que le bon fonctionnement de la correction. C’est l’exécution hébergée, sous tvOS 26.5, qui dit si le dock suit la télécommande en tvOS 26.

## La CI de la 0.9.1

Le travail macOS de l’exécution hébergée de `326b953` (0.9.1) a échoué à l’étape de la session YouTube. Ce banc compile seul un petit nombre de sources, dont `GlassStyle.swift`, qui lit depuis la 0.9.1 une valeur d’environnement déclarée dans `SettingsControls.swift`. La valeur est maintenant déclarée dans `GlassStyle.swift`, à côté des styles qui la lisent, et ces sources se compilent de nouveau seules. Les compilations des quatre plateformes, elles, avaient réussi.

## Non vérifié

- **Apple TV physique** : rien. Le comportement de tvOS 26 est déduit de ce que l’Apple TV montrait et du code ; le parcours hébergé sous tvOS 26.5 le vérifie, pas un appareil.
- **Le panneau audio et sous-titres sous tvOS 26** : aucun parcours ne compare ce qu’il dessine au focus du système. Ses lignes lisent maintenant leur focus comme le reste de l’écran.

## Limites connues

- Celles de la 0.9.1 et de la 0.9.0 demeurent.
