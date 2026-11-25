# Validation de FLUX IPTV 0.9.0 — build 38

La 0.9.0 donne au Mac une interface de bureau : accueil, dock, zones pour le clavier et la télécommande, colonne de navigation, télévision en trois colonnes, liste de zapping, fiches et réglages en verre, filtre par langue pour les films et les séries. Apple TV, iPhone et iPad conservent la disposition de la 0.8.9 ; sur Apple TV, le formulaire d’une source occupe désormais tout l’écran. Ce rapport distingue ce qui a été exécuté de ce qui ne l’a pas été.

Les vérifications ci-dessous ont été faites le 25 novembre 2026 sur un Mac Apple Silicon, macOS 27.2, Xcode 27.2 (Swift 6.4.2), sur l’état final des sources. **Aucune exécution GitHub Actions ne correspond encore à cette version** : le workflow compile avec Xcode 26.3 sur un Mac Intel et teste le cœur sous Linux avec Swift 6.2. Son résultat sur le commit livré reste la référence.

## Exécuté

| Vérification | Résultat |
|---|---|
| `swift test` | 158 tests du cœur réussis, dont 21 nouveaux |
| `scripts/check-state-declarations.sh` | aucune erreur |
| `scripts/rooms/verify_rooms.py` | 18 décors vérifiés, inchangés |
| `scripts/generate-xcodeproj.py` | les deux projets générés sont à jour |
| Compilations | macOS, iOS Simulator, tvOS Simulator et tvOS appareil |
| `scripts/test-catalog-ui.sh` en mode local, avec la galerie | 30 captures de la vraie interface, lues auprès du serveur de fenêtres ; les quatre parcours de touches aboutissent |
| `scripts/test-tvos-catalog-ui.sh` | douze scénarios natifs, trois démarrages à froid et trois parcours XCUIRemote réussis |
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

Le banc dessine la vraie `ContentView` dans une fenêtre native avec un catalogue local : accueil, télévision, films, fiche film, rayon des saisons, fiche série, favoris, réglages des sources et du dock, réglages et liste de zapping posés sur le lecteur, zones de l’écran ; puis, pour la galerie, les cinq thèmes du dock avec le pointeur sur une icône, les quatre autres emplacements, l’accueil avec le pointeur sur Films et sur Séries, et le filtre par langue. Les deux fiches satisfont le contrôle existant : un seul grand boîtier entièrement visible, la commande de lecture présente, aucun lecteur ni vue web.

Quatre scénarios envoient à l’écran les touches d’une télécommande par le même traitement que le clavier, et échouent si la sélection n’arrive pas où elle doit :

| Touches | Sélection attendue |
|---|---|
| Retour, Gauche, Bas, OK | la destination en cours, dans le dock |
| Retour, Haut, OK, Droite | Actualiser |
| Retour, Haut, OK, Gauche | Accueil |
| Retour, Retour | l’accueil |

Les réglages du lecteur et la liste de zapping sont capturés au-dessus d’un décor qui tient lieu d’image : le banc ne lit aucun flux, et la liste y est dessinée comme si la chaîne sélectionnée était à l’écran.

Ces captures ont été prises fenêtres hors écran, sans prendre le premier plan. **Les trois scénarios de focus de recherche, qui exigent la fenêtre active, n’ont pas été exécutés sur cette version.**

### Banc Apple TV

Le banc a été exécuté sur l’état final des sources, dans son propre simulateur (tvOS 27.2, Apple TV 4K à 1080p). Il désactive le Liquid Glass dans ses préférences : ses contrôles ont été qualifiés sur les surfaces sombres, et le verre ne change aucune disposition.

Un douzième scénario ouvre le formulaire « Charger une liste ». Il exige que le focus natif soit sur le champ Serveur, entièrement visible, que le bouton d’envoi — le dernier contrôle du formulaire — tienne dans la zone sûre de l’écran, et qu’aucune vue défilante ne le contienne. La feuille de la 0.8.9 coupait ce formulaire et le faisait défiler.

### Essai réel

L’application signée localement a été lancée avec la source Xtream déjà enregistrée, sans saisie d’identifiants, puis pilotée par des clics en arrière-plan. **Cet essai a porté sur un état antérieur à l’unification des icônes, aux réglages en verre du lecteur et aux zones.**

- l’application s’ouvre sur l’accueil, qui affiche les 24 665 chaînes de la source ;
- un clic sur TV ouvre la télévision sur la catégorie et la chaîne laissées à la session précédente ;
- un clic sur la chaîne sélectionnée l’ouvre et l’image du direct s’affiche ; au retour, l’aperçu de la chaîne démarre dans le grand cadre ;
- le filtre par langue trouve l’anglais, l’espagnol, le français et l’italien dans 58 110 films, et 9 989 titres sans étiquette ; « Français » retient 14 190 films ;
- la fiche d’un film et la fiche d’une série affichent les jaquettes, les repères, le synopsis et les crédits du fournisseur ;
- Réglages › Sources présente la source avec ses effectifs.

Cet essai avait fait apparaître une langue portée par deux titres seulement, lue à tort dans un mot. Une langue présente sur moins de trois titres n’est plus proposée.

## Non vérifié

- **Liste de zapping** : dessinée dans le banc, jamais ouverte sur un direct ; ni le changement de chaîne ni celui de catégorie n’ont été exercés. L’essai réel s’est arrêté quand l’application a été reprise en main.
- **Réglages en verre pendant la lecture** : capturés sur un décor, pas sur une vidéo.
- **Clavier réel** : Tab entre les zones, et Échap dans la fenêtre. Les scénarios du banc passent par le traitement des touches, pas par le clavier.
- **Animations** : l’accueil qui se replie vers le dock, le changement de décor sous le pointeur, le boîtier entre le rayon et la fiche. Seuls leurs états de départ et d’arrivée sont capturés.
- **Pointeur réel** : l’agrandissement du dock pendant le mouvement, le glissement d’une icône et la sélection d’une chaîne au simple survol. Les captures montrent l’état agrandi obtenu en plaçant le pointeur par programme.
- **Liquid Glass sur Apple TV** : compilé, jamais affiché sur un appareil ; sa fluidité n’est pas mesurée.
- **Formulaire d’une source sur une Apple TV physique** : vérifié dans le simulateur à 1080p, pas sur un téléviseur ni avec une vraie télécommande ; la saisie et l’envoi n’ont pas été exercés.
- **iPhone et iPad** : compilation seulement, liste de zapping comprise.
- **Lecture** au-delà d’une chaîne et d’un aperçu : pas d’essai de film, d’épisode, de reprise ni de réseau dégradé.
- **Ajout ou modification d’une source** par le formulaire dessiné dans Réglages.
- **Installateur Mac**.

## Limites connues

- Les réglages se parcourent au pointeur ; les flèches ne les traversent pas sur Mac et ils n’ont pas de zones.
- Le rayon des saisons n’a pas de zones : Retour y ramène directement au catalogue.
- Depuis une liste, Retour demande deux pressions pour changer d’écran, la première montrant les zones ; Réglages › Interface supprime cette étape.
- La liste de zapping et l’accueil n’existent pas sur Apple TV. Les autres panneaux d’Apple TV — sources, listes, catégories, réglages — restent des feuilles.
- La recherche porte sur la section en cours, pas sur les trois catalogues.
- Les informations de la chaîne sélectionnée se limitent à ce que fournit la liste ; aucun programme n’est affiché tant que l’EPG n’existe pas.
- La langue d’un pays plurilingue est celle que le système tient pour la plus probable : une étiquette `BE` donne le néerlandais, `CH` l’allemand.
