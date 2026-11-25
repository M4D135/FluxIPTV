# Validation de FLUX IPTV 0.9.0 — build 38

La 0.9.0 donne au Mac et à l’Apple TV la même interface de bureau : accueil, dock en bas au centre, boussole des zones pour le clavier et la télécommande, colonne de navigation, télévision en trois colonnes, liste de zapping, réglages en verre, filtre par langue pour les films et les séries. iPhone et iPad conservent la disposition de la 0.8.9. Ce rapport distingue ce qui a été exécuté de ce qui ne l’a pas été.

Les vérifications ci-dessous ont été faites les 25 et 26 novembre 2026 sur un Mac Apple Silicon, macOS 27.2, Xcode 27.2 (Swift 6.4.2), sur l’état final des sources. **Le résultat de GitHub Actions sur le commit livré reste la référence** : le workflow compile avec Xcode 26.3 sur un Mac Intel et teste le cœur sous Linux avec Swift 6.2.

## Exécuté

| Vérification | Résultat |
|---|---|
| `swift test` | 158 tests du cœur réussis, dont 21 nouveaux |
| `scripts/check-state-declarations.sh` | aucune erreur |
| `scripts/rooms/verify_rooms.py` | 18 décors vérifiés, inchangés |
| `scripts/generate-xcodeproj.py` | les deux projets générés sont à jour |
| Compilations | macOS, iOS Simulator, tvOS Simulator et tvOS appareil |
| `scripts/test-catalog-ui.sh` en mode local, avec la galerie | 30 captures de la vraie interface du Mac ; les quatre parcours de touches aboutissent |
| `scripts/test-tvos-catalog-ui.sh` | quinze scénarios natifs, trois démarrages à froid et quatre parcours XCUIRemote réussis |
| Application réelle sur le Mac, source Xtream enregistrée | voir « Essai réel » |

### Tests du cœur ajoutés

- **Dock** : ordre enregistré (entrées inconnues ou répétées écartées, nouvelles destinations ajoutées), déplacement d’une icône, identifiants de focus ; agrandissement nul sans pointeur, maximal sous lui, cellules jamais superposées et sans saut sur un balayage complet ; navigation entre le dock et l’écran pour chaque bord.
- **Historique de Retour** : les écrans se dépilent jusqu’à l’accueil ; un écran rouvert passe en dernier, si bien que Retour ne boucle jamais ; quitter un écran jamais enregistré ramène quand même au précédent.
- **Zones** : pour chacun des cinq emplacements du dock et chaque combinaison de zones présentes, toute zone est atteignable depuis toute autre ; les voisinages suivent la disposition de l’écran ; Tab parcourt les zones dans l’ordre de lecture.
- **Navigation du bureau** : passages entre la colonne, la grille, les rangées du haut et les actions voisines de l’aperçu, y compris une dernière rangée incomplète, un catalogue vide, et le lien entre le haut de la colonne et les commandes placées au-dessus d’elle.
- **Langue des films et des séries** : étiquettes de titre et de catégorie reconnues, mots ordinaires et marques écartés, seuil de trois titres pour une étiquette comme pour une langue, filtrage du catalogue, validation de la langue mémorisée.

Un test existant affirmait que le pays ne filtre jamais les films ni les séries. Il vérifie désormais la règle voulue : chaque type a un filtre, le pays pour les chaînes et la langue pour les titres, et un code de pays mémorisé pour des films est abandonné.

### `swift test` sur Mac

Avec le SDK macOS 27.2, `import Foundation` ne fournit plus à lui seul les initialiseurs ni l’égalité de `CGRect`. Trois fichiers du cœur importent maintenant CoreGraphics quand il existe. La suite ne compilait pas sur ce Mac avant cette correction ; le workflow ne le voyait pas, ses tests du cœur tournant sous Linux.

### Captures Mac

Le banc dessine la vraie `ContentView` dans une fenêtre native avec un catalogue local : accueil, télévision, films, fiche film, rayon des saisons, fiche série, favoris, réglages des sources et du dock, réglages et liste de zapping posés sur le lecteur, boussole des zones ; puis, pour la galerie, les cinq thèmes du dock avec le pointeur sur une icône, les quatre autres emplacements, l’accueil avec le pointeur sur Films et sur Séries, et le filtre par langue. Les deux fiches satisfont le contrôle existant : un seul grand boîtier entièrement visible, la commande de lecture présente, aucun lecteur ni vue web.

Quatre scénarios envoient à l’écran les touches d’une télécommande par le même traitement que le clavier, et échouent si la sélection n’arrive pas où elle doit :

| Touches | Sélection attendue |
|---|---|
| Retour, Bas | la destination en cours, dans le dock |
| Retour, Haut, Droite | Actualiser |
| Retour, Bas, Gauche, Gauche | le bouton Retour, à gauche du dock |
| Retour, Retour | l’accueil |

Les réglages du lecteur et la liste de zapping sont capturés au-dessus d’un décor qui tient lieu d’image : le banc ne lit aucun flux, et la liste y est dessinée comme si la chaîne sélectionnée était à l’écran.

Ces captures ont été prises fenêtres hors écran, sans prendre le premier plan. **Les trois scénarios de focus de recherche, qui exigent la fenêtre active, n’ont pas été exécutés sur cette version.**

### Banc Apple TV

Le banc a été exécuté sur l’état final des sources, dans un simulateur qu’il crée (tvOS 27.2, Apple TV 4K à 1080p), avec le Liquid Glass actif comme dans l’application.

Quinze scénarios lancent l’application sur un écran et exigent que le focus natif soit sur le contrôle attendu, mesuré dans la fenêtre : l’accueil, la télévision, les films, la fiche d’un film, la saison 12 et son épisode 15, la liste de zapping, les réglages, l’accueil sans source, le formulaire d’une source, deux recherches, la France, l’Espagne, les pays dans la colonne et la restauration d’une chaîne. Le formulaire d’une source doit tenir dans la zone sûre de l’écran, hors de toute vue défilante.

Quatre parcours passent par XCUIRemote, donc par le vrai moteur de focus :

- **Boussole** : depuis la liste des chaînes, Menu puis Haut mène au champ de recherche ; Menu puis Bas, à la chaîne sélectionnée ; Menu puis Gauche, à la colonne ; Menu puis OK ne change rien ; Menu puis Bas, au dock, que les flèches parcourent jusqu’au bouton Retour.
- **Pays** : de la liste à la colonne, ouverture des pays sur celui en cours, passage de la France à l’Espagne, réouverture, annulation par Menu, puis Menu jusqu’à l’accueil et sortie de l’application.
- **Chaîne restaurée** : la chaîne mémorisée perd puis retrouve le focus.
- **Source en erreur** : le bouton de reconnexion suit la télécommande.

Ces parcours ont fait apparaître deux défauts corrigés : depuis la première icône du dock, Gauche partait dans la liste au lieu du bouton Retour ; et la sonde de mesure du banc, placée entre un bouton et son focus, empêchait d’entrer dans la liste des pays.

### Essai réel

L’application signée localement a été lancée sur le Mac avec la source Xtream déjà enregistrée, sans saisie d’identifiants, puis pilotée par des clics en arrière-plan. **Cet essai a porté sur un état antérieur au dock en bas, à la boussole, aux réglages en verre du lecteur et au portage sur Apple TV.**

- l’application s’ouvre sur l’accueil, qui affiche les 24 665 chaînes de la source ;
- un clic sur TV ouvre la télévision sur la catégorie et la chaîne laissées à la session précédente ;
- un clic sur la chaîne sélectionnée l’ouvre et l’image du direct s’affiche ; au retour, l’aperçu de la chaîne démarre dans le grand cadre ;
- le filtre par langue trouve l’anglais, l’espagnol, le français et l’italien dans 58 110 films, et 9 989 titres sans étiquette ; « Français » retient 14 190 films ;
- la fiche d’un film et la fiche d’une série affichent les jaquettes, les repères, le synopsis et les crédits du fournisseur ;
- Réglages › Sources présente la source avec ses effectifs.

## Non vérifié

- **Apple TV physique** : rien de cette interface n’a été affiché sur un téléviseur ni piloté par une vraie télécommande. Le simulateur ne dit rien de la fluidité, du verre sur une Apple TV HD, ni de la lecture.
- **Liste de zapping** : dessinée dans les deux bancs, jamais ouverte sur un direct ; ni le changement de chaîne ni celui de catégorie n’ont été exercés.
- **Réglages en verre pendant la lecture** : capturés sur un décor, pas sur une vidéo.
- **Clavier réel du Mac** : Tab entre les zones, et Échap dans la fenêtre. Les scénarios du banc passent par le traitement des touches, pas par le clavier.
- **Animations** : l’accueil qui se replie vers le dock, le changement de décor sous le pointeur, le boîtier entre le rayon et la fiche. Seuls leurs états de départ et d’arrivée sont capturés.
- **Pointeur réel** : l’agrandissement du dock pendant le mouvement, le glissement d’une icône et la sélection d’une chaîne au simple survol.
- **iPhone et iPad** : compilation seulement.
- **Lecture** au-delà d’une chaîne et d’un aperçu : pas d’essai de film, d’épisode, de reprise ni de réseau dégradé.
- **Ajout ou modification d’une source** : le formulaire est affiché, la saisie et l’envoi ne sont pas exercés.
- **Installateur Mac**.

## Limites connues

- Sur Mac, les pages des Réglages se parcourent au pointeur : les flèches ne les traversent pas. Sur Apple TV, la télécommande les atteint.
- Sur Apple TV, la fiche d’un film ou d’une série est encore la fiche plein écran de la 0.8.9, pas le panneau de verre du Mac.
- Le rayon des saisons n’a pas de boussole : Retour y ramène directement au catalogue.
- Depuis une liste, Retour demande deux pressions pour changer d’écran, la première montrant la boussole ; sur Mac, Réglages › Interface supprime cette étape.
- La recherche porte sur la section en cours, pas sur les trois catalogues.
- Le dock ne se réordonne pas à la télécommande.
- Les informations de la chaîne sélectionnée se limitent à ce que fournit la liste ; aucun programme n’est affiché tant que l’EPG n’existe pas.
- La langue d’un pays plurilingue est celle que le système tient pour la plus probable : une étiquette `BE` donne le néerlandais, `CH` l’allemand.
