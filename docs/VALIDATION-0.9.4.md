# Validation de FLUX IPTV 0.9.4 — build 42

La 0.9.4 apporte :
- le mode souris de la télécommande de l’Apple TV, choisi dans Réglages › Télécommande ou par Lecture/Pause maintenue ;
- Retour qui sort d’abord du contenu vers le bouton Retour de la barre ;
- Droite au bout d’une rangée de jaquettes qui passe à la rangée suivante ;
- la page Graphismes : Automatique selon l’appareil détecté, trois préréglages, chaque réglage à part ;
- le repère du panneau actif, liseré et reflet ;
- le petit plan de l’écran à la place de « Zone suivante » ;
- la loupe du dock en cinq tailles et l’allure de l’icône sélectionnée ;
- trois thèmes de dock illustrés : Néon 90, Verre nocturne, Art déco ;
- l’aperçu des chaînes après une seconde, Apple TV comprise ;
- la préparation de l’App Store ([APP-STORE.md](APP-STORE.md)).

Pour le reste, les validations de la 0.9.3 ([VALIDATION-0.9.3.md](VALIDATION-0.9.3.md)) et des versions précédentes valent toujours, avec leurs limites.

Les vérifications ont été faites le 27 novembre 2026 :
- sur un Mac Apple Silicon, macOS 27.2.1, Xcode 27.2 ;
- sur l’état final des sources.

**Le résultat de GitHub Actions sur le commit livré reste la référence.** Il joue les parcours de la télécommande sous tvOS 26.5, la version la plus proche des Apple TV en tvOS 26.6.1. Le banc local, lui, tourne sous tvOS 27.2.

## Exécuté

| Vérification | Résultat |
|---|---|
| Tests du cœur (`swift test`) | 200 tests, aucun échec. |
| Banc Apple TV (`scripts/test-tvos-catalog-ui.sh`), simulateur Apple TV 1080p sous tvOS 27.2 | 33 écrans : focus natif sur le contrôle attendu, captures non vides. 22 parcours XCUIRemote sur 22. |
| Banc Mac (`FLUX_CATALOG_UI_BACKGROUND=1 scripts/test-catalog-ui.sh`) | 55 captures hors écran et 27 parcours de touches sur 27 : 25 au passage ordinaire, 2 en mode galerie (`FLUX_CATALOG_UI_GALLERY=1`). La fin « PARTIAL » est attendue en local : les scénarios du champ de recherche demandent la fenêtre au premier plan et restent à la CI. |
| Compilation macOS, iOS Simulator, tvOS Simulator et tvOS ARM64 Release (`scripts/build-platforms.sh`) | Quatre « BUILD SUCCEEDED », aucun avertissement du code. |
| Variante App Store pour tvOS : vérification de types avec `FLUX_APP_STORE`, sans YouTubeKit | Aucune erreur. |

Le premier passage complet du banc Apple TV a donné 16 parcours sur 22. Les six échecs ont été corrigés, puis les parcours en cause rejoués, enfin tout le banc :
- la loupe du dock, trois parcours ;
- Lecture/Pause maintenue ;
- le pointeur ;
- une barre reconstruite au premier appui, parce que la partie active n’était connue qu’à ce moment-là.

Le détail est plus bas.

Après ces bancs, deux textes ont changé, vus sur les captures du Mac :
- sur l’écran TV, l’aperçu désactivé renvoie à Réglages › Graphismes, et non plus à Interface ;
- la description de Fluide est raccourcie : elle était coupée sur sa carte.

Les deux sont revérifiés :
- vérification de types macOS et tvOS ;
- `swift test` : 200 tests, aucun échec ;
- captures `settings-graphics.png` et `keys-dock.png` refaites.

Les quatre compilations n’ont pas été relancées pour ces deux chaînes de texte.

## GitHub Actions sur le commit livré (`3889170`)

Le commit a été poussé sur `main` et sur `work/three-rooms-0.9.0`, ce qui a lancé deux exécutions.

| Travail | `main` (45923098645) | branche (45923098956) |
|---|---|---|
| tvOS Simulator, tvOS 26.5 : 33 écrans et 22 parcours à la télécommande | Réussi | Réussi |
| tvOS ARM64 Release | Réussi | Réussi |
| iOS Simulator | Réussi | Réussi |
| macOS : compilation et bancs | Échec : la machine hébergée a perdu le contact avec le serveur pendant la compilation | Réussi, toutes étapes |
| Tests du cœur sous Linux, Swift 6.2.1 | Échec | Échec |

Les tests du cœur ont échoué pour deux raisons :
- `RemotePointer.swift` importait CoreGraphics, qui n’existe pas sous Linux ;
- il utilisait `CGVector`, absent de Foundation sous Linux.

Le commit suivant corrige les deux :
- l’import est gardé par `canImport`, comme dans les autres fichiers du cœur ;
- `FluxPointerMotion.step` prend `dx` et `dy` en nombres. Le calcul est le même.

Ce commit ne change rien à l’application sur Mac, iPhone ni Apple TV. Le dossier `FluxIPTV-0.9.4` livré reste valable.

## Ce que les bancs vérifient de nouveau

- **Retour depuis une liste.** Le parcours « Menu retrace les écrans » passe maintenant par la barre : depuis la liste des chaînes, puis depuis les films, Menu donne d’abord la télécommande au bouton Retour de la barre, et seulement le Menu suivant change d’écran, jusqu’à l’accueil.
- **Lecture/Pause maintenue.** Un parcours maintient la touche 1,2 s : le mode passe à Souris, une bulle le dit, la chaîne garde la sélection. Maintenue de nouveau, la touche revient au mode Classique, où Bas passe à la chaîne suivante. Le premier passage du banc a montré que la touche maintenue faisait aussi passer à la partie suivante de l’écran : un appui de Lecture/Pause attend désormais que la touche remonte, et un appui long le supprime.
- **Le pointeur.** Un simulateur n’a pas de pavé tactile : sous le banc seulement, l’application promène elle-même le pointeur sur le contenu, puis sur la barre. Le parcours exige que les chaînes et les icônes du dock survolées prennent la sélection, que la sélection finale soit celle de la chaîne sous le pointeur, puis qu’un clic l’ouvre et que le pointeur s’efface sur l’image. Le premier passage a montré que tvOS refuse les demandes de sélection faites par UIKit aux contrôles de SwiftUI (43 demandes, aucune acceptée) : chaque contrôle donne maintenant sa place au pointeur, qui le sélectionne comme l’écran le fait lui-même.
- **La loupe du dock.** Plus forte en 0.9.4, elle faisait grandir le cadre des icônes : Gauche depuis une icône agrandie partait dans la liste au-dessus, et Haut ne trouvait plus la rangée du dessus de l’accueil. Sur Apple TV, l’icône est maintenant agrandie à l’intérieur de son bouton, qui garde sa taille. Les parcours du dock, de Retour et des deux rangées de l’accueil le vérifient.
- **Les pages Graphismes et Télécommande**, capturées sur Apple TV comme sur le Mac (page Clavier).
- **Le préréglage Fluide au clavier du Mac**, désormais dans Réglages › Graphismes : la tuile Automatique d’abord, Fluide ensuite. OK sur Fluide doit couper le verre, les mouvements et les fonds, et lâcher Automatique, dans ce que l’application enregistre.
- **Retour au clavier du Mac** : un Retour depuis la grille des films mène au bouton Retour, un second à l’accueil ; avec « Quitter l’écran », un seul Retour mène à l’accueil.
- **Les tests du cœur** couvrent la lecture de gauche à droite et de haut en bas dans une grille, les choix de Retour, de la loupe et du repère, leurs migrations depuis la 0.9.3, l’appareil détecté et son préréglage, le délai de l’aperçu, et le mouvement du pointeur.

## Non vérifié

- **Apple TV physique** : rien de la 0.9.4.
  - Le mode souris n’a jamais suivi un vrai pouce. La vitesse, l’inertie et les bords du pavé sont à essayer sur la télécommande.
  - Lecture/Pause maintenue : sous XCUIRemote, la touche maintenue ne fait que changer de mode. Sur la vraie télécommande, ce reste à voir, comme le léger retard d’un appui court, qui attend que la touche remonte.
  - Automatique n’a pas été vu choisir Fluide sur l’Apple TV « Chambre », ni Équilibré sur la « Séjour ».
  - Le reflet du panneau actif n’a pas été vu sur une Apple TV HD.
- **tvOS 26** : seul le banc hébergé, sous tvOS 26.5, joue les parcours dans cette version.
- **La variante App Store** : seule sa vérification de types a été faite, avec `FLUX_APP_STORE` et sans YouTubeKit. Elle n’a été ni archivée ni envoyée à App Store Connect.
- **Pointeur réel sur le Mac** : la loupe plus forte sous le pointeur.

## Limites connues

- En mode souris, le pointeur sélectionne les contrôles du catalogue, de la colonne, de la barre, du dock, des fiches et des saisons. Les lignes des Réglages, les panneaux à part (source, « Favoris, listes et dock », réglages pendant la lecture) et le studio ne donnent pas leur place au pointeur : il n’y est pas vérifié, les flèches y vont. Tant que la sélection n’a pas rejoint le contrôle sous le pointeur, un clic ne fait rien, plutôt que d’appuyer sur le contrôle qui la garde ailleurs.
- L’icône « Boutique » des trois packs illustrés n’est pas encore montrée : la boutique n’existe pas.
- Dans les thèmes illustrés, seules la plaque et les six destinations sont dessinées : les raccourcis et les dossiers gardent leur dessin habituel.
- Celles de la 0.9.3 et des versions précédentes demeurent.
