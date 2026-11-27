# Validation de FLUX IPTV 0.9.5 — build 43

La 0.9.5 étend le mode souris de l’Apple TV :
- aux Réglages : la colonne des pages, dont la page suit le pointeur, et chaque touche du contenu ; une page plus longue que l’écran défile quand le pointeur pousse son bord ;
- aux panneaux : « Favoris, listes et dock », les messages, les réglages pendant la lecture, Audio et sous-titres ;
- au studio d’apparence, qui couvre l’écran avec son propre pointeur ;
- aux fiches, où le clic restait sans effet en 0.9.4.

Rien ne change sur le Mac ni sur l’iPhone. Pour le reste, les validations de la 0.9.4 ([VALIDATION-0.9.4.md](VALIDATION-0.9.4.md)) et des versions précédentes valent toujours, avec leurs limites.

Les vérifications ont été faites le 27 novembre 2026 :
- sur un Mac Apple Silicon, macOS 27.2.1, Xcode 27.2 ;
- sur l’état final des sources.

**Le résultat de GitHub Actions sur le commit livré reste la référence.** Il joue les parcours de la télécommande sous tvOS 26.5, la version la plus proche des Apple TV en tvOS 26.6.1. Le banc local, lui, tourne sous tvOS 27.2.

## Exécuté

| Vérification | Résultat |
|---|---|
| Tests du cœur (`swift test`) | 202 tests, aucun échec. Deux sont nouveaux : la place de la commande sélectionnée, et la page que le pointeur pousse. |
| Banc Apple TV (`scripts/test-tvos-catalog-ui.sh`), simulateur Apple TV 1080p sous tvOS 27.2 | 33 écrans : focus natif sur le contrôle attendu, captures non vides. 25 parcours XCUIRemote sur 25, dont les trois nouveaux du pointeur. |
| Banc Mac (`FLUX_CATALOG_UI_BACKGROUND=1 scripts/test-catalog-ui.sh`) | 55 captures hors écran et 25 parcours de touches sur 25. La fin « PARTIAL » est attendue en local : les scénarios du champ de recherche demandent la fenêtre au premier plan et restent à la CI. Les deux parcours du mode galerie n’ont pas été rejoués : la 0.9.5 ne change rien au Mac. |
| Compilation macOS, iOS Simulator, tvOS Simulator et tvOS ARM64 Release (`scripts/build-platforms.sh`) | Quatre « BUILD SUCCEEDED », aucun avertissement du code. |
| Variante App Store pour tvOS : vérification de types avec `FLUX_APP_STORE`, sans YouTubeKit | Aucune erreur. |

Le premier lancement des parcours du pointeur s’est arrêté à leur compilation : un attribut en double dans le fichier des parcours. Une fois corrigé, quatre parcours sur cinq passaient. Sur la page Graphismes, l’interrupteur visé était tout entier sous le bord de la page, et le pointeur ne savait pas faire défiler une page : il ne pouvait pas l’atteindre. La poussée de page vient de là. Le parcours rejoué seul, puis tout le banc, passent.

## Ce qui a changé dans le pointeur

En 0.9.4, le pointeur savait qu’un contrôle avait la sélection quand l’écran principal le lui disait. Une fiche, un panneau et les Réglages tiennent leur propre sélection, que l’écran principal ignore : le pointeur croyait la sélection ailleurs, et retenait le clic. Désormais, il compare la place du contrôle sélectionné avec celle du contrôle qu’il survole. Les tests du cœur vérifient cette comparaison :
- un contrôle sélectionné, un peu agrandi, reste le même ;
- une ligne qu’une liste ne montre qu’en partie aussi ;
- la ligne d’en dessous, le panneau autour et un bouton à l’intérieur, non.

Une colonne qui ramène la sélection sur sa ligne choisie laisse passer le pointeur. C’est le cas de la colonne des Réglages et de celles des saisons et des épisodes : la page ou la saison suit alors le pointeur, comme elle suit les flèches.

Une ligne qu’une liste a fait défiler hors de vue n’est plus visée. Le pointeur ne voit que sa partie visible, dans une liste verticale comme dans un rayon horizontal du studio.

Une page des Réglages plus longue que l’écran défile sous le pointeur. En 0.9.4, une liste défilait quand le pointeur atteignait la ligne coupée par son bord : cette ligne prenait la sélection, et la liste la montrait. Une page des Réglages a des titres et des explications entre ses touches. La touche suivante pouvait donc rester tout entière sous le bord, hors d’atteinte du pointeur. Désormais, poussé contre le bas ou le haut de la page, le pointeur s’arrête à ce bord, et la page avance du reste du geste. Au bout de la page, il continue, vers la barre ou le haut de l’écran. Tant que la page bouge, un clic ne fait rien, et le pointeur cherche ce qu’il survole une fois la page arrêtée. Les tests du cœur vérifient ce partage du geste :
- poussé contre le bord, le pointeur s’y arrête, et la page avance de ce qui dépasse ;
- près du bout de la page, il continue avec le reste ;
- au bout, il sort ;
- à l’intérieur de la page, ou en y entrant par la barre, seul le pointeur bouge.

Le studio et tout panneau qui couvre l’écran ont leur propre pointeur, au-dessus de celui des écrans : chacun ne vise que ses contrôles. Dans le studio, le pointeur pose le curseur, un clic choisit, et un glissement ne déplace plus le curseur. Les flèches le déplacent toujours, et le pointeur les suit.

## Ce que les bancs vérifient de nouveau

Un simulateur n’a pas de pavé tactile : sous le banc seulement, l’application déplace elle-même le pointeur, contrôle par contrôle, et attend que chacun prenne la sélection. Un clic de XCUIRemote appuie ensuite sur ce que le pointeur survole.

- **La fiche et ses listes.** Sur la fiche d’un film, le pointeur passe sur Lecture, puis se pose sur la touche des listes ; un clic ouvre « Favoris, listes et dock ». Dans le panneau, il passe sur « Créer une nouvelle liste », se pose sur la première liste, et un clic la coche.
- **Les Réglages et le studio.** Sur la page Graphismes, le pointeur passe sur un préréglage. Il descend ensuite jusqu’au bas de la page et le pousse, jusqu’à montrer un interrupteur que la page cachait, puis s’y pose. Il entre ensuite dans la colonne sur Interface, dont la page s’affiche, puis se pose sur la touche du studio du dock. Un clic ouvre le studio. Là, il passe sur un écran, se pose sur un thème, et un clic le choisit. Menu referme le studio, et les Réglages retrouvent le pointeur.
- **Les langues sur l’image.** Pendant la lecture d’un film, le panneau Audio et sous-titres rend la main au pointeur. Le pointeur passe sur une piste audio, se pose sur un sous-titre, et un clic le choisit.

## Non vérifié

- **Apple TV physique** : rien de la 0.9.5, ni du mode souris de la 0.9.4. Le pointeur n’a jamais suivi un vrai pouce.
- **Un glissement dans le studio** : XCUIRemote n’a pas de pavé tactile. Qu’un glissement n’y déplace que le pointeur reste à voir sur la télécommande ; les flèches, elles, sont jouées.
- **Les messages et les réglages pendant la lecture** : ils ont leurs cibles pour le pointeur, mais aucun parcours ne les pointe. Le parcours des messages, à la télécommande classique, passe toujours.
- **tvOS 26** : seul le banc hébergé, sous tvOS 26.5, joue les parcours dans cette version.

## Limites connues

- Seules les pages des Réglages défilent sous la poussée du pointeur. Ailleurs, une liste défile comme en 0.9.4, par la ligne que le pointeur atteint à son bord.
- Dans une page longue des Réglages, le pointeur ne sort par le bas qu’au bout de la page. Menu mène plus vite à la barre ; la colonne y descend aussi.
- Le formulaire d’une source garde la télécommande classique : le pointeur s’y efface, et un glissement va d’un champ au suivant. Le formulaire se referme par la présentation du système, qu’un pointeur à lui ne laisserait plus passer.
- Toute autre feuille du système ouverte par-dessus l’écran garde aussi la télécommande classique : le pointeur s’efface tant qu’elle est ouverte.
- Celles de la 0.9.4 et des versions précédentes demeurent.
