# Validation de FLUX IPTV 0.9.0 — build 38

La 0.9.0 donne au Mac et à l’Apple TV la même interface de bureau : accueil, dock en bas au centre, colonne de navigation, télévision en trois colonnes, fiches et listes d’un titre en verre, commandes de lecture et langues, liste de zapping, réglages en verre appliqués dès qu’ils sont choisis, filtre par langue pour les films et les séries. Retour y est le Précédent d’un navigateur ; au clavier du Mac il montre d’abord la boussole des zones. iPhone et iPad conservent la disposition de la 0.8.9. Ce rapport distingue ce qui a été exécuté de ce qui ne l’a pas été.

Les vérifications ci-dessous ont été faites les 25 et 26 novembre 2026 sur un Mac Apple Silicon, macOS 27.2, Xcode 27.2 (Swift 6.4.2), sur l’état final des sources. **Le résultat de GitHub Actions sur le commit livré reste la référence** : le workflow compile avec Xcode 26.3 sur un Mac Intel et teste le cœur sous Linux avec Swift 6.2.

## Exécuté

| Vérification | Résultat |
|---|---|
| `swift test` | 160 tests du cœur réussis, dont 23 nouveaux |
| `scripts/check-state-declarations.sh` | aucune erreur |
| `scripts/rooms/verify_rooms.py` | 18 décors vérifiés, inchangés |
| `scripts/generate-xcodeproj.py` | les deux projets générés sont à jour |
| Compilations | macOS, iOS Simulator, tvOS Simulator et tvOS appareil |
| `scripts/test-catalog-ui.sh` en mode local, avec la galerie | 34 captures de la vraie interface du Mac ; les cinq parcours de touches aboutissent |
| `scripts/test-tvos-catalog-ui.sh` | vingt et un scénarios natifs, trois démarrages à froid et huit parcours XCUIRemote réussis |
| Application réelle sur le Mac, source Xtream enregistrée | voir « Essai réel » |

### Tests du cœur ajoutés

- **Dock** : ordre enregistré (entrées inconnues ou répétées écartées, nouvelles destinations ajoutées), déplacement d’une icône, identifiants de focus ; agrandissement nul sans pointeur, maximal sous lui, cellules jamais superposées et sans saut sur un balayage complet ; navigation entre le dock et l’écran pour chaque bord.
- **Historique de Retour** : comme dans un navigateur, les écrans se dépilent dans l’ordre où ils ont été ouverts, jusqu’à l’accueil ; un écran ouvert deux fois compte deux étapes ; revoir l’écran déjà affiché n’en ajoute pas ; un long va-et-vient oublie ses plus vieilles étapes et finit quand même à l’accueil ; quitter un écran jamais enregistré ramène au précédent.
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
| Dans le lecteur : Droite trois fois, OK, Bas, Retour | la touche Langues, son panneau ouvert sur l’audio en cours puis refermé |

Les commandes de lecture d’un direct et d’un film, les langues, les réglages du lecteur et la liste de zapping sont capturés au-dessus d’un décor qui tient lieu d’image. Le banc ne lit aucun flux : le contrôleur de lecture n’y reçoit que l’état publié d’un média qui joue — titre, position, pistes — sans ouvrir de connexion ni démarrer de moteur.

Ces captures ont été prises fenêtres hors écran, sans prendre le premier plan. **Les trois scénarios de focus de recherche, qui exigent la fenêtre active, n’ont pas été exécutés sur cette version.**

### Banc Apple TV

Le banc a été exécuté sur l’état final des sources, dans un simulateur qu’il crée (tvOS 27.2, Apple TV 4K à 1080p), avec le Liquid Glass actif comme dans l’application.

Vingt et un scénarios lancent l’application sur un écran et exigent que le focus natif soit sur le contrôle attendu, mesuré dans la fenêtre : l’accueil, la télévision, les films, la fiche d’un film, les listes d’un titre, le rayon des saisons, la saison 12 et son épisode 15, les commandes de lecture d’un direct et d’un film, les langues, les réglages pendant un flux, la liste de zapping, les réglages, l’accueil sans source, le formulaire d’une source, deux recherches, la France, l’Espagne, les pays dans la colonne et la restauration d’une chaîne. Le formulaire d’une source doit tenir dans la zone sûre de l’écran, hors de toute vue défilante.

Huit parcours passent par XCUIRemote, donc par le vrai moteur de focus :

- **Les flèches seules** : depuis la liste des chaînes, Haut mène au champ de recherche, Gauche à la colonne, Droite à Regarder, Bas de là au dock, que les flèches parcourent jusqu’au bouton Retour, et Haut ramène dans l’écran.
- **Menu comme le Précédent d’un navigateur** : de l’accueil, la télévision s’ouvre avec la télécommande sur sa première chaîne ; puis les films, par le dock, sur leur premier titre ; puis la télévision de nouveau. Menu, depuis l’intérieur de la liste, revient aux films sur le titre laissé, sans panneau intermédiaire ; Menu encore, à la télévision ouverte en premier ; Menu enfin, à l’accueil.
- **Lecteur pendant un flux**, sur une lecture simulée dont les commandes se masquent comme en vrai : elles se retirent, OK les rappelle sur Pause ; Réglages ouvre ses panneaux sur la page Vidéo, qui garde la télécommande sept secondes, plus que le délai de masquage ; Bas affiche la page Réseau, Droite entre dans son contenu, Gauche revient sur elle ; Menu referme les panneaux sur la touche Réglages. Langues s’ouvre sur l’audio en cours, un autre choix s’applique, le panneau garde lui aussi la télécommande sept secondes, Menu le referme sur sa touche ; Menu quitte enfin la lecture pour la liste d’où elle est partie.
- **Pays** : de la liste à la colonne, ouverture des pays sur celui en cours, passage de la France à l’Espagne, réouverture, annulation par Menu, puis Menu qui revient aussitôt à l’accueil et sortie de l’application.
- **Fiche d’un film** : OK sur une jaquette ouvre le panneau de verre sur sa commande de lecture ; les bouts de la rangée de commandes retiennent la télécommande, Bas ne sort pas vers le dock ni vers le catalogue, Haut atteint la croix ; Favoris ouvre les listes sur la première, Menu les referme sans rien enregistrer, puis le choix d’une liste et Enregistrer marquent le titre, la télécommande revenant chaque fois sur Favoris ; Description complète s’ouvre et Menu en revient ; Menu referme la fiche et rend le focus à la jaquette.
- **Fiche d’une série** : depuis la commande de lecture, Gauche entre dans les épisodes sur l’épisode 15 sélectionné et non sur la ligne la plus proche ; Gauche encore entre dans les saisons sur la saison 12 sans rien changer ; Haut passe à la saison 11, dont les épisodes remplacent aussitôt la liste ; Droite mène à son premier épisode puis aux commandes ; Menu revient au rayon, sur la saison 11.
- **Chaîne restaurée** : la chaîne mémorisée perd puis retrouve le focus.
- **Source en erreur** : le bouton de reconnexion suit la télécommande.

Ces parcours ont fait apparaître quatre défauts corrigés avant le portage du lecteur : depuis la première icône du dock, Gauche partait dans la liste au lieu du bouton Retour ; la sonde de mesure du banc, placée entre un bouton et son focus, empêchait d’entrer dans la liste des pays ; à l’ouverture d’une fiche depuis le catalogue, le focus restait sur la jaquette devenue inactive, le panneau encore invisible ne pouvant pas le prendre ; et Menu ne refermait pas les listes d’un titre.

Les parcours du lecteur et de Menu en ont montré cinq autres, tous corrigés. **Pendant un flux, les réglages ne répondaient plus au bout de trois secondes** : les commandes se masquaient sous eux, et la zone invisible qui les rappelle reprenait la télécommande, dont les flèches changeaient alors de chaîne derrière les panneaux. **Un réglage n’était appliqué que par un bouton Enregistrer**, et fermer le panneau le perdait. Depuis la liste des pages, Droite n’entrait dans une page que si un contrôle se trouvait à la hauteur de la ligne. De même, Regarder et Favoris, à côté de l’aperçu d’une chaîne, n’étaient atteints depuis la liste que par hasard d’alignement, et l’image de l’aperçu prenait le focus sans le montrer. Enfin, **en ouvrant une section depuis l’accueil, le dock était dessiné sélectionné alors que la télécommande se trouvait sur le bouton Pays**.

Le nouveau scénario du rayon des saisons a montré deux choses que l’œil ne voyait pas. Ses jaquettes, calculées pour la largeur du catalogue, occupaient 53 % de la hauteur de l’écran : le rayon reprend maintenant celles du catalogue, sept par rangée. Et son défilement, qui touchait le bord de la zone sûre, s’étendait dessous : le moteur de focus plaçait les jaquettes à une marge de l’endroit où elles sont dessinées. Deux points de retrait le gardent dans la zone sûre, et la mesure coïncide avec le dessin.

### Captures Mac comparées

Les captures Mac d’avant et d’après le portage des fiches ont été comparées pixel à pixel, hors bandeau de l’heure : la fiche d’un film, la télévision, les films, les favoris et les réglages sont identiques. Seul change le rayon des saisons, dont la rangée du bas se fond au lieu d’être coupée.

La même comparaison a été refaite après la refonte du lecteur : hors des écrans de lecture, toutes les captures du Mac sont identiques à celles du commit précédent, réglages compris.

### GitHub Actions

Le premier envoi du portage sur Apple TV (`1e609c7`) a échoué sur deux étapes des machines hébergées, qui utilisent tvOS 26.5 et un Mac Intel sous macOS 26. Les deux causes étaient dans les bancs et y sont corrigées. Sous tvOS 26.5 le parcours de la boussole interrogeait l’icône de la recherche, qui porte le même identifiant que le champ : le champ avait bien le focus, comme le montrent la capture et l’arbre d’accessibilité de l’échec. Sur le Mac hébergé, la fenêtre reçoit son premier focus natif après son ouverture ; les deux touches du scénario étaient envoyées avant, et ce premier focus écrasait leur résultat. Le banc attend maintenant ce focus quand la fenêtre est au premier plan.

L’envoi suivant (`d51e0ac`) y a passé le Mac, les dix-sept scénarios et cinq parcours sur six, et a révélé un défaut de l’application que tvOS 27.2 ne montre pas : sous tvOS 26.5, annuler la liste des pays par Menu laissait le focus natif sur le filtre des catégories, voisin, alors que le bouton Pays était dessiné sélectionné. Ce bouton ne revient dans la colonne qu’avec la fermeture de la liste, et le focus lui était demandé trop tôt. Il lui est maintenant donné une fois le bouton revenu, comme après le choix d’un pays.

L’envoi de ce correctif (`9390c8e`) a passé cinq parcours, celui des pays compris, et a été interrompu pendant le sixième : la machine hébergée, plus lente ce jour-là, a mis plus que les dix minutes que le banc accordait aux parcours quand ils étaient quatre. Le banc leur accorde maintenant vingt minutes, et l’étape trente-cinq.

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
- **Lecteur sur un vrai flux** : les commandes, les langues et les réglages sont exercés sur une lecture simulée, pas sur une vidéo. Le choix d’une piste audio ou d’un sous-titre **par VLC** est écrit d’après l’interface de VLCKit et compile ; il n’a été essayé sur aucun flux. « Relancer le flux » non plus. L’image jusqu’aux bords du téléviseur n’a pas été vue sur un téléviseur.
- **Clavier réel du Mac** : Tab entre les zones, et Échap dans la fenêtre. Les scénarios du banc passent par le traitement des touches, pas par le clavier.
- **Animations** : l’accueil qui se replie vers le dock, le changement de décor sous le pointeur, le boîtier entre le rayon et la fiche. Seuls leurs états de départ et d’arrivée sont capturés.
- **Pointeur réel** : l’agrandissement du dock pendant le mouvement, le glissement d’une icône et la sélection d’une chaîne au simple survol.
- **iPhone et iPad** : compilation seulement.
- **Lecture** au-delà d’une chaîne et d’un aperçu : pas d’essai de film, d’épisode, de reprise ni de réseau dégradé.
- **Ajout ou modification d’une source** : le formulaire est affiché, la saisie et l’envoi ne sont pas exercés.
- **Installateur Mac**.

## Limites connues

- Sur Mac, les pages des Réglages se parcourent au pointeur : les flèches ne les traversent pas. Sur Apple TV, la télécommande les atteint.
- Sur Apple TV, rien ne défile sous la télécommande dans une fiche : le synopsis montre les lignes qui tiennent, le reste se lit dans Description complète.
- Le panneau des listes d’un titre garde sur Mac ses boutons du système ; sur Apple TV il a les tailles et les surbrillances du bureau.
- Le champ de recherche qui a le focus de la télécommande est dessiné clair par le système, dans son cadre de verre.
- Sur Mac, depuis une liste, Retour demande deux pressions pour changer d’écran, la première montrant la boussole ; Réglages › Interface supprime cette étape. Sur Apple TV il n’y a pas de boussole.
- Retour retrace les écrans, pas les catégories parcourues dans un écran : une pression quitte la section, qui se rouvrira sur la catégorie et le titre laissés.
- Pendant la lecture, Favori ajoute ou retire le titre des favoris d’une pression ; le choix parmi plusieurs listes reste dans la fiche et dans le catalogue.
- Les réglages que le moteur lit à l’ouverture d’un flux ne changent pas le flux en cours sans « Relancer le flux ».
- La recherche porte sur la section en cours, pas sur les trois catalogues.
- Le dock ne se réordonne pas à la télécommande.
- Les informations de la chaîne sélectionnée se limitent à ce que fournit la liste ; aucun programme n’est affiché tant que l’EPG n’existe pas.
- La langue d’un pays plurilingue est celle que le système tient pour la plus probable : une étiquette `BE` donne le néerlandais, `CH` l’allemand.
