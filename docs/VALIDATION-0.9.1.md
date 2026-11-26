# Validation de FLUX IPTV 0.9.1 — build 39

La 0.9.1 ouvre les Réglages au clavier du Mac, que seule la télécommande d’une Apple TV parcourait, et donne au clavier la touche O. Le reste est celui de la 0.9.0 : sa validation, dans [VALIDATION-0.9.0.md](VALIDATION-0.9.0.md), vaut toujours, avec ses limites.

Les vérifications ci-dessous ont été faites le 26 novembre 2026 sur un Mac Apple Silicon, macOS 27.2, Xcode 27.2, sur l’état final des sources. **Le résultat de GitHub Actions sur le commit livré reste la référence** : il compile avec Xcode 26.3 sur un Mac Intel et joue les parcours sous tvOS 26.5, la version la plus proche des Apple TV en tvOS 26.6.1.

## Exécuté

| Vérification | Résultat |
|---|---|
| `swift test` | 177 tests du cœur réussis ; le cœur n’a pas changé |
| `scripts/check-state-declarations.sh` | aucune erreur |
| `scripts/generate-xcodeproj.py` | les deux projets générés sont à jour, en 0.9.1 build 39 |
| Compilations | macOS, iOS Simulator, tvOS Simulator et tvOS appareil |
| `scripts/test-catalog-ui.sh` en mode local, avec la galerie | 60 captures de la vraie interface du Mac ; les seize parcours de touches aboutissent, dont les quatre des Réglages |
| `scripts/test-tvos-catalog-ui.sh` | trente et un scénarios natifs et dix-huit parcours XCUIRemote réussis sous tvOS 27.2, dont celui des réglages pendant un flux, qui traverse leurs pages : le code partagé des Réglages a changé |

## Le clavier du Mac dans les Réglages

Demande du 26 novembre : « la version macOS c’est parfait sauf le contrôle clavier, qui merde aux endroits où la télécommande merde dans la version tvOS ». Sur Mac, une fois dans Réglages, les flèches ne quittaient jamais la barre du bas : les pages ne se parcouraient qu’au pointeur.

- Chaque contrôle d’une page annonce sa place à l’écran. **Haut** et **Bas** vont à la ligne la plus proche, puis au contrôle le mieux aligné ; **Gauche** et **Droite** restent sur la ligne. Depuis la colonne, **Droite** entre dans la page et **Gauche** y revient sur la page en cours, comme à la télécommande ; parcourir la colonne affiche chaque page. **Entrée** fait ce que fait un clic. Un contrôle désactivé est sauté. Le contrôle atteint est cerclé de blanc, comme sous la télécommande.
- Au-delà de la dernière ligne vers le dock, la sélection revient à l’icône Réglages. **Tab** passe de la colonne à la page, puis au dock ; **⌘ + flèche** va droit à la colonne, à la page ou au dock.
- Le champ d’un nouveau dossier et celui d’un nom à changer prennent le curseur à leur ouverture ; **Échap** les ferme et rend la sélection au bouton qui les a ouverts.
- La télécommande virtuelle se choisit entre deux touches, comme les autres choix, au lieu d’un menu du système. « Apparence par défaut » et les profils du vidéoclub ont l’allure des autres touches, sur Mac comme sur Apple TV.
- **O** ouvre « Favoris, listes et dock » pour le titre sélectionné, comme OK maintenu sur une télécommande, et les réglages pendant la lecture.

Quatre parcours du banc Mac jouent ces touches par le même traitement que le clavier, et échouent si la sélection n’arrive pas où elle doit :

| Touches | Sélection attendue |
|---|---|
| Réglages › Interface, depuis le dock : Haut, Droite, OK | « Afficher les décors », coupé |
| Réglages › Interface : Haut, Bas, Bas, Droite | le premier choix de « Saut avant / arrière », la page Vidéo affichée |
| Réglages › Dock : Haut, Droite, Droite, Bas, OK | un thème du dock, appliqué |
| Réglages › Interface : Haut, puis Bas sept fois | l’icône Réglages du dock |

Leurs captures montrent la sélection cerclée de blanc, la page Vidéo affichée par la colonne, et le thème « Couleurs » choisi puis porté par le dock. Les douze parcours de la 0.9.0 passent toujours.

## Non vérifié

- **Clavier réel du Mac** : aucune touche pressée — ni les flèches dans les Réglages, ni Tab, ni ⌘ + flèche, ni O. Le banc passe par le traitement des touches, pas par le clavier.
- **Les deux champs** d’un nouveau dossier et d’un nom à changer : le curseur à l’ouverture et Échap n’ont pas été exercés.
- **Apple TV physique** : rien, comme pour la 0.9.0.

## Limites connues

- Sur Mac, le curseur du volume, dans Réglages › Audio et sous-titres, se règle au pointeur ; Sourdine est au clavier.
- Le formulaire d’une source garde sur Mac les champs du système, hors des flèches.
- La sélection du clavier et le survol du pointeur restent distincts dans les Réglages : le pointeur ne déplace pas la sélection.
- Les autres limites de la 0.9.0 demeurent.
