# Feuille de route FLUX IPTV

## Intégré dans les sources 0.9.0 — build 38

Le Mac reçoit une interface de bureau. Apple TV, iPhone et iPad conservent la disposition de la 0.8.9, avec le filtre par langue disponible dans le cœur et le Liquid Glass activable sur Apple TV.

- **Accueil** : l’application s’ouvre sur les six destinations — TV, Films, Séries, Recherche, Favoris, Réglages — en grand dock au milieu de la fenêtre. Le nom, l’effectif et le décor suivent la destination pointée. Retour revient à l’écran précédent, écran après écran, jusqu’à cet accueil.
- **Dock** : hors de l’accueil il se range sous la colonne de navigation, avec les mêmes icônes et le même thème. Il se place aussi en bas, en haut, ou en colonne à gauche ou à droite ; les icônes grossissent sous le pointeur comme dans le Dock du système, se réordonnent par glissement ou depuis Réglages › Dock, et cinq thèmes changent la plaque et les icônes.
- **Zones** pour le clavier et la télécommande : depuis une liste, Retour encadre le haut, la colonne, le contenu, l’aperçu et le dock ; les flèches choisissent, OK entre, Retour une seconde fois revient à l’écran précédent. Tab change de zone. Retour, Accueil, la recherche, Actualiser et les pages se sélectionnent comme le reste.
- **Colonne de navigation** commune aux trois espaces : Retour et Accueil, tout le catalogue, les listes, À reprendre pour les films, les catégories avec leurs effectifs et un filtre. Plus aucune feuille pour les catégories, les pays, les listes, les sources ou les réglages.
- **Télévision** en trois colonnes : catégories, chaînes en une seule liste, puis l’aperçu avec ce que la liste sait de la chaîne. La ligne sous le pointeur grossit et devient la sélection, l’aperçu démarre après une seconde, un clic ouvre la chaîne.
- **Zapping** : pendant un direct, la liste des chaînes se pose à gauche de l’image sans arrêter la lecture ; elle change de chaîne et de catégorie. Sur Mac et iPad.
- **Films et séries filtrés par langue**, sur le modèle du pays des chaînes : la langue est lue dans l’étiquette du titre (`FR - …`, `4K-EN - …`) puis dans celle de sa catégorie (`FRANCE SÉRIES`). Ce qui ne porte aucune étiquette reste accessible sous « Langue non identifiée ».
- **Fiche d’un film** : panneau de verre posé sur le catalogue flouté, boîtier à gauche, puis titre, repères, commandes, synopsis et crédits fournis. Le boîtier quitte le rayon et vient se placer dans la fiche.
- **Fiche d’une série** : saisons sous le boîtier, épisodes en liste de haut en bas, puis le visuel et la description de l’épisode sélectionné.
- **Favoris** : destination du dock qui réunit les listes des trois types, avec création, renommage et suppression sur place.
- **Réglages** : écran de la fenêtre, avec les sources (ajout, modification, suppression sans feuille) et le dock. Pendant la lecture, ce sont deux panneaux de verre sur l’image.
- Messages de la bibliothèque et choix des listes d’un titre dessinés dans la fenêtre.
- **Apple TV** : le formulaire d’une source occupe tout l’écran, type à gauche, champs et boutons à droite, sans rien à faire défiler.

## Conservé de la 0.8.9

- Filtre des chaînes par pays pour les 249 codes ISO, catégories non identifiées conservées.
- Mémoire de navigation par source et par section ; une section rouverte depuis l’accueil retrouve sa catégorie et sa chaîne, sans démarrer la lecture.
- Apple TV : grandes entrées, catégories horizontales, grandes vignettes 16:9, focus natif qualifié par les parcours XCUIRemote.
- Trois espaces et six ambiances par espace, 18 fonds précalculés.
- Aperçu TV unique et muet ; favoris avec choix des listes ; commandes de lecture compactes à masquage automatique.

## Demandes ouvertes (David, 25 novembre 2026)

1. **Trois univers nettement distincts.** Non commencé. Le vidéoclub ne convient pas aux séries : les films sont une sortie (cinéma, vidéoclub), les séries et la télévision se regardent à la maison. Au moins trois décors 3D par espace, réalisés avec FERRO ou Blender selon le meilleur rendu. Piste proposée, à valider : Films = la sortie du soir ; Séries = le marathon de nuit, lumière tamisée ; TV = le direct, salon de jour.
2. **Animations 3D de transition** à chaque sélection. Fait pour le boîtier entre le rayon et la fiche, et pour l’accueil qui se replie vers le dock ; à étendre aux autres sélections et aux autres plateformes.
3. **Télécommandes.** Commencé : le modèle des zones, l’historique de Retour et la navigation du bureau sont dans le cœur, sans dépendance à SwiftUI, donc réutilisables sur Apple TV et pour un portage. Restent les gestes du pavé tactile, la détection de la télécommande ou son choix dans les réglages, et les réglages eux-mêmes, que les flèches ne parcourent pas encore.
4. **Lecture sans coupure.** Non commencé. Tampon qui télécharge le plus possible ce qui est regardé ; réglages complets du cache, du traitement et de la correction du flux, avec des valeurs par défaut soignées et des libellés compréhensibles.
5. **Liquid Glass partout.** Sur Mac, plus aucune feuille : les réglages du lecteur sont en verre. Sur Apple TV, activable et à qualifier sur appareil. Sur iPhone et iPad, les feuilles du système demeurent.
6. **Interface de bureau sur Apple TV et iPad** : accueil, dock, zones, colonnes, panneaux et liste de zapping, une fois la présentation Mac validée. Sur Apple TV, les panneaux des sources, des listes, des catégories et des réglages sont encore des feuilles ; seul le formulaire d’une source est en plein écran.
7. **Mesures sur l’Apple TV « Chambre ».** Non commencé : journal des temps de réaction et des délais d’ouverture, pour optimiser par itérations.
8. **Android TV** : application distincte, le code SwiftUI ne s’y exécutant pas ; le modèle de commande du cœur sert de référence.
9. **Choix des maquettes** : les captures des écrans sont produites par le banc ; la sélection reste à faire.

## Qualification automatisée

- GitHub Actions compile macOS, iOS Simulator, tvOS Simulator et tvOS ARM64 Release, exécute les tests du cœur et vérifie les 18 fonds et les deux projets générés.
- Les tests du cœur couvrent le dock (ordre, agrandissement, navigation selon le bord), l’historique de Retour, les zones (chacune atteignable depuis chaque autre, pour chaque bord du dock), la navigation du bureau entre colonne, grille, commandes du haut et actions, et la détection des langues.
- Le banc Mac capture la vraie interface dans une fenêtre native : accueil, télévision, films, fiche film, rayon des saisons, fiche série, favoris, réglages des sources et du dock, réglages et liste de zapping posés sur le lecteur, zones. Quatre scénarios y envoient les touches d’une télécommande et vérifient où la sélection arrive.
- Les contrôles Apple TV de la 0.8.9 restent en place, avec un douzième rapport natif pour le formulaire d’une source en plein écran : douze rapports, trois démarrages à froid, trois parcours XCUIRemote.

## Validation restant à faire sur Apple

- Pointeur réel sur le Mac : agrandissement du dock, glissement des icônes, sélection des chaînes au survol.
- Clavier réel sur le Mac : Tab entre les zones, et les animations de l’accueil.
- Liste de zapping et réglages en verre sur un vrai direct.
- Lecture réelle au-delà d’une chaîne : reprise d’un film, épisodes, réseau dégradé.
- Liquid Glass sur une Apple TV physique, fluidité comprise.
- Siri Remote physique, catalogue volumineux, réseau lent ou coupé.
- Installateur Mac et distribution sur appareils.

## Développements ultérieurs

- EPG/XMLTV et programmes présent/suivant, qui donneront une vraie description à la chaîne sélectionnée.
- Rayon « À reprendre » sur l’accueil.
- Agrégation de reprise des épisodes dans la carte d’un coffret.
- Sélection des pistes VLC et qualification des cibles mobiles.
- Distribution signée, icônes et préparation d’une livraison App Store.

Le détail de validation de chaque version reste dans son rapport ; une tâche implémentée n’est pas assimilée à une qualification sur appareil.
