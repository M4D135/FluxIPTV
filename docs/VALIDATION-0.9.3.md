# Validation de FLUX IPTV 0.9.3 — build 41

La 0.9.3 apporte :
- le studio d’apparence ;
- les fonds et les thèmes du dock écran par écran ;
- trois préréglages de qualité ;
- la traversée des bords de l’écran ;
- l’ordre des zones dans le sens des aiguilles d’une montre ;
- l’icône de l’application ;
- le retrait des dix-huit anciens décors, avec leurs enseignes « FLUX », et de deux fonds dessinés : le hall d’entrée des Films et le vidéoclub des Séries ;
- la bulle de la colonne des Réglages, que la colonne coupait sur les côtés sur Apple TV.

Pour le reste, les validations de la 0.9.2 ([VALIDATION-0.9.2.md](VALIDATION-0.9.2.md)), de la 0.9.1 et de la 0.9.0 valent toujours, avec leurs limites.

Les vérifications ont été faites le 26 novembre 2026 :
- sur un Mac Apple Silicon, macOS 27.2.1, Xcode 27.2 ;
- sur l’état final des sources.

**Le résultat de GitHub Actions sur le commit livré reste la référence.** Il joue les parcours de la télécommande sous tvOS 26.5, la version la plus proche des Apple TV en tvOS 26.6.1. Le banc local, lui, tourne sous tvOS 27.2.

## Exécuté

| Vérification | Résultat |
|---|---|
| `scripts/generate-xcodeproj.py` | les deux projets générés sont à jour, en 0.9.3 build 41, avec 69 sources partagées |
| `swift test` | 190 tests, aucun échec |
| Vérification de types Mac et tvOS | les sources de l’application et celles des deux bancs, sans erreur |
| `scripts/test-catalog-ui.sh` | captures complètes après le retrait des décors : 162 images. Après la correction de la colonne, huit scénarios repris : accueil, Films, Séries, studio (fonds et vitrine), Réglages au clavier. Tous les contrôles réussis. Le banc local finit en « PARTIAL », comme toujours hors fenêtre au premier plan : les scénarios de recherche au clavier ne s’y jouent pas. |
| `scripts/test-tvos-catalog-ui.sh` | sous tvOS 27.2, après la correction de la colonne : 31 scénarios natifs réussis, focus mesuré là où il est attendu ; 20 parcours XCUIRemote réussis, aucun échec. La capture des Réglages montre le contour de la ligne sous la télécommande entier sur ses quatre côtés. |
| Compilations | `scripts/build-platforms.sh` en Release : macOS, iOS, tvOS simulateur et tvOS appareil réussis, après la correction de la colonne. |

## Ce que les bancs vérifient de nouveau

- **Le préréglage Fluide.** Au clavier, dans Réglages › Interface, OK sur Fluide doit couper le verre, les mouvements et les fonds dans ce que l’application enregistre. Jusque-là, le banc Mac imposait ses propres réglages par le domaine des arguments, qui passe avant ce que l’application écrit : le préréglage ne pouvait s’y appliquer, et la page affichait « Personnalisé ». Pour ce scénario seul, les réglages du banc ne font plus que tenir lieu de valeurs enregistrées.
- **Les fonds livrés.** Avant toute capture, le banc Mac vérifie que les seize fonds dessinés sont dans l’application, en 3840 × 2160. Il vérifiait jusque-là trois des anciens décors.
- **Le studio d’apparence**, sur le Mac :
  - sa vitrine, avec les images de la boutique derrière les onglets ;
  - le rayon des fonds ;
  - le rayon du dock, sur un thème d’aujourd’hui et sur Phosphore ;
  - la ligne du curseur ramenée en haut du panneau, sans que la rangée précédente dépasse.
- **Aucune touche morte au bord de l’écran.** Un vingtième parcours XCUIRemote fait chaque appui après une pause :
  - Gauche depuis la colonne de la télévision mène au bouton Retour ;
  - Gauche encore mène à Réglages, la barre faisant le tour ;
  - Droite revient à Retour ;
  - Bas mène au champ de recherche ;
  - Haut mène à l’icône TV, puis dans l’écran ;
  - Droite au bout de la rangée ramène à l’icône TV.

  Sur Apple TV, tvOS n’envoie à aucun contrôle un appui vers le bord. Quatre bandes invisibles le long des bords, armées 0,45 s après le dernier déplacement, reçoivent cet appui et le donnent au contrôle que le bord désigne.
- **Sur le Mac**, des scénarios jouent les mêmes bords au clavier, une touche après une pause.

## Non vérifié

- **Apple TV physique** : rien de la 0.9.3.
  - Les bords n’ont été franchis que dans le simulateur. Sur l’appareil, il faut voir si la sélection clignote quand un appui vers le bord revient où il était.
  - Les fonds 4K et le studio n’ont pas été vus sur une Apple TV HD.
  - Le préréglage Fluide n’a pas été essayé sur l’Apple TV « Chambre ».
- **tvOS 26** : seul le banc hébergé, sous tvOS 26.5, joue les parcours dans cette version.
- **Le studio à la télécommande** : aucun parcours XCUIRemote ne le parcourt encore. Il est vérifié au clavier du Mac, qui suit les mêmes touches.
- **Pointeur réel sur le Mac** : le survol qui essaie un fond et le clic qui le garde.

## Limites connues

- Les icônes du dock ne changent pas encore de jeu d’images : les packs viendront avec les images que David fournira.
- La boutique n’existe pas encore : tout est « Inclus ».
- Celles de la 0.9.2, de la 0.9.1 et de la 0.9.0 demeurent.
