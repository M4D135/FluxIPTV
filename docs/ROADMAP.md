# Feuille de route FLUX IPTV

## Intégré dans les sources 0.9.0 — build 38

Le Mac et l’Apple TV reçoivent la même interface de bureau. iPhone et iPad conservent la disposition de la 0.8.9.

- **Accueil** : l’application s’ouvre sur les six destinations — TV, Films, Séries, Recherche, Favoris, Réglages — en grand dock au milieu de la fenêtre. Le nom, l’effectif et le décor suivent la destination pointée. Retour revient à l’écran précédent comme le Précédent d’un navigateur : écran après écran, dans l’ordre où ils ont été ouverts, jusqu’à cet accueil.
- **Dock** : hors de l’accueil il se tient en bas au centre, comme le Dock de macOS, avec les mêmes icônes et le même thème ; Retour et Accueil sont à sa gauche, l’heure à sa droite. Il se place aussi sous la colonne de navigation, en haut, ou en colonne à gauche ou à droite ; les icônes grossissent sous le pointeur — ou sous la télécommande —, se réordonnent par glissement ou depuis Réglages › Dock, et cinq thèmes changent la plaque et les icônes.
- **Une seule logique au clavier et à la télécommande** : les flèches vont au contrôle voisin, OK valide, Retour revient en arrière. Une destination s’ouvre avec la sélection dans son contenu. Sur Apple TV chaque colonne répond comme un tout à la flèche qui pointe vers elle. Sur Mac, dont les flèches suivent des rangées, Retour montre d’abord la **boussole des zones** — haut, colonne, contenu, aperçu, dock —, une flèche saute dans la zone voisine et Tab change de zone.
- **Colonne de navigation** commune aux trois espaces : tout le catalogue, les listes, À reprendre pour les films, les catégories avec leurs effectifs et un filtre. Plus aucune feuille pour les catégories, les pays, les listes, les sources ou les réglages.
- **Télévision** en trois colonnes : catégories, chaînes en une seule liste, puis l’aperçu avec ce que la liste sait de la chaîne. La ligne sous le pointeur grossit et devient la sélection, l’aperçu démarre après une seconde, un clic ouvre la chaîne.
- **Zapping** : pendant un direct, la liste des chaînes se pose à gauche de l’image sans arrêter la lecture ; elle change de chaîne et de catégorie. Sur Mac, iPad et Apple TV.
- **Films et séries filtrés par langue**, sur le modèle du pays des chaînes : la langue est lue dans l’étiquette du titre (`FR - …`, `4K-EN - …`) puis dans celle de sa catégorie (`FRANCE SÉRIES`). Ce qui ne porte aucune étiquette reste accessible sous « Langue non identifiée ».
- **Fiche d’un film**, sur Mac et sur Apple TV : panneau de verre posé sur le catalogue flouté, boîtier à gauche, puis titre, repères, commandes, synopsis et crédits fournis. Le boîtier quitte le rayon et vient se placer dans la fiche.
- **Fiche d’une série** : saisons sous le boîtier, épisodes en liste de haut en bas, puis le visuel et la description de l’épisode sélectionné. À la télécommande, chaque colonne s’ouvre sur ce qui y est sélectionné.
- **Favoris** : destination du dock qui réunit les listes des trois types, avec création, renommage et suppression sur place.
- **Réglages** : écran de la fenêtre, avec les sources (ajout, modification, suppression sans feuille) et le dock. Pendant la lecture, ce sont deux panneaux de verre sur l’image, sur Mac comme sur Apple TV. Un réglage est enregistré dès qu’il est choisi ; ceux que le moteur lit à l’ouverture d’un flux proposent de le relancer.
- **Lecture** : l’image jusqu’aux bords de l’écran ; Retour, le titre et l’heure en haut ; en bas une barre de verre dont chaque touche porte son nom — Chaînes, Précédente, Pause, Suivante, puis Favori, Langues et Réglages ; −15 s et +15 s sous la ligne du temps pour un film. **Langues** choisit l’audio et les sous-titres, appliqués aussitôt, avec le moteur Apple comme avec VLC.
- Messages de la bibliothèque et choix des listes d’un titre dessinés dans la fenêtre, au-dessus de l’écran ou de la fiche passés au flou ; sur Apple TV, Menu les referme.
- **Apple TV** : le bureau du Mac — accueil, dock, colonnes, pays et langues dans la colonne, réglages dans l’écran, lecture, zapping — avec des tailles lues depuis un canapé et le Liquid Glass actif par défaut. Menu est le Précédent d’un navigateur. Le formulaire d’une source occupe tout l’écran, type à gauche, champs et boutons à droite, sans rien à faire défiler.

## Conservé de la 0.8.9

- Filtre des chaînes par pays pour les 249 codes ISO, catégories non identifiées conservées.
- Mémoire de navigation par source et par section ; une section rouverte depuis l’accueil retrouve sa catégorie et sa chaîne, sans démarrer la lecture.
- Apple TV : grandes entrées, catégories horizontales, grandes vignettes 16:9, focus natif qualifié par les parcours XCUIRemote.
- Trois espaces et six ambiances par espace, 18 fonds précalculés.
- Aperçu TV unique et muet ; favoris avec choix des listes ; commandes de lecture compactes à masquage automatique.

## Demandes ouvertes (David, 25 novembre 2026)

1. **Trois univers nettement distincts.** Non commencé. Le vidéoclub ne convient pas aux séries : les films sont une sortie (cinéma, vidéoclub), les séries et la télévision se regardent à la maison. Au moins trois décors 3D par espace, réalisés avec FERRO ou Blender selon le meilleur rendu. Piste proposée, à valider : Films = la sortie du soir ; Séries = le marathon de nuit, lumière tamisée ; TV = le direct, salon de jour.
2. **Animations 3D de transition** à chaque sélection. Fait pour le boîtier entre le rayon et la fiche, et pour l’accueil qui se replie vers le dock ; à étendre aux autres sélections et aux autres plateformes.
3. **Télécommandes et clavier : tous les boutons, le moins de pressions possible.** Fait pour la télécommande sur Apple TV : le moteur de focus atteint chaque contrôle par les flèches seules, chaque colonne répondant comme un tout, et Menu revient en arrière ; huit parcours XCUIRemote le vérifient. Restent : sur Mac, les pages des Réglages et les boutons des jaquettes, que les flèches ne parcourent pas encore ; les gestes du pavé tactile ; la détection de la télécommande ou son choix dans les réglages. L’historique de Retour, le modèle des zones et la navigation du bureau sont dans le cœur, sans dépendance à SwiftUI, pour un portage.
4. **Lecture sans coupure.** Commencé par l’interface : commandes de lecture refaites, langues des deux moteurs, réglages appliqués dès qu’ils sont choisis. Non commencé : tampon qui télécharge le plus possible ce qui est regardé ; réglages complets du traitement et de la correction du flux, avec des valeurs par défaut soignées.
5. **Liquid Glass partout.** Sur Mac et sur Apple TV, plus aucune feuille dans le bureau : les réglages du lecteur sont en verre. À qualifier sur une Apple TV physique. Sur iPhone et iPad, les feuilles du système demeurent.
6. **La même interface sur Apple TV que sur Mac.** Fait pour l’accueil, le dock, les colonnes, le rayon des saisons, les fiches, les listes d’un titre, les réglages, les favoris et le zapping. L’iPad reste à porter.
7. **Mesures sur l’Apple TV « Chambre ».** Non commencé : journal des temps de réaction et des délais d’ouverture, pour optimiser par itérations.
8. **Android TV** : application distincte, le code SwiftUI ne s’y exécutant pas ; le modèle de commande du cœur sert de référence.
9. **Choix des maquettes** : les captures des écrans sont produites par le banc ; la sélection reste à faire.
10. **Dock personnalisable.** À préciser : en plus de Favoris et de Réglages, déjà dans le dock, pouvoir y épingler des listes ou des chaînes favorites.

## Qualification automatisée

- GitHub Actions compile macOS, iOS Simulator, tvOS Simulator et tvOS ARM64 Release, exécute les tests du cœur et vérifie les 18 fonds et les deux projets générés.
- Les tests du cœur couvrent le dock (ordre, agrandissement, navigation selon le bord), l’historique de Retour, les zones (chacune atteignable depuis chaque autre, pour chaque bord du dock), la navigation du bureau entre colonne, grille, commandes du haut et actions, et la détection des langues.
- Le banc Mac capture la vraie interface dans une fenêtre native : accueil, télévision, films, fiche film, rayon des saisons, fiche série, favoris, réglages des sources et du dock, commandes de lecture d’un direct et d’un film, langues, réglages et liste de zapping posés sur le lecteur, boussole des zones. Quatre scénarios y envoient les touches d’une télécommande et vérifient où la sélection arrive.
- Le banc Apple TV lance vingt et un écrans dans son simulateur et exige le focus natif sur le contrôle attendu, puis huit parcours XCUIRemote : chaque zone par les flèches seules, Menu qui retrace les écrans jusqu’à l’accueil, les pays dans la colonne, la fiche d’un film avec ses listes et sa description, la fiche d’une série colonne par colonne, les panneaux du lecteur pendant un flux, la chaîne restaurée, la source en erreur.

## Validation restant à faire sur Apple

- Apple TV physique : la nouvelle interface sur un téléviseur, avec une vraie télécommande, fluidité du verre comprise.
- Pointeur réel sur le Mac : agrandissement du dock, glissement des icônes, sélection des chaînes au survol.
- Clavier réel sur le Mac : Tab entre les zones, et les animations de l’accueil.
- Liste de zapping, commandes de lecture et réglages en verre sur un vrai direct.
- Pistes audio et sous-titres lus par VLC, et « Relancer le flux », sur un vrai flux.
- Lecture réelle au-delà d’une chaîne : reprise d’un film, épisodes, réseau dégradé.
- Siri Remote physique, catalogue volumineux, réseau lent ou coupé.
- Installateur Mac et distribution sur appareils.

## Développements ultérieurs

- EPG/XMLTV et programmes présent/suivant, qui donneront une vraie description à la chaîne sélectionnée.
- Rayon « À reprendre » sur l’accueil.
- Agrégation de reprise des épisodes dans la carte d’un coffret.
- Qualification des cibles mobiles.
- Distribution signée, icônes et préparation d’une livraison App Store.

Le détail de validation de chaque version reste dans son rapport ; une tâche implémentée n’est pas assimilée à une qualification sur appareil.
