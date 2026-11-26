# FLUX IPTV 0.9.0 — build 38 — Bureau Mac : dock, colonnes et panneaux de verre

Application native SwiftUI pour macOS, iOS et tvOS.

**La 0.9.0 donne au Mac et à l’Apple TV la même interface de bureau.** L’application s’ouvre sur un accueil où le dock occupe le milieu de l’écran ; il se range ensuite en bas, au centre, comme le Dock de macOS, sous les colonnes qui accompagnent les trois espaces. La télévision se lit en trois colonnes, les fiches flottent en verre sur le catalogue flouté, et plus aucune feuille ne recouvre la fenêtre : catégories, pays, langues, listes, sources et réglages sont dessinés dans l’interface, y compris pendant la lecture. Les films et les séries se filtrent par langue, comme les chaînes par pays.

iPhone et iPad conservent la disposition de la 0.8.9. Sur Apple TV, le Liquid Glass est actif par défaut à partir de tvOS 26, avec un réglage pour revenir aux surfaces sombres plus légères.

## Le bureau, sur Mac et sur Apple TV

Les deux plateformes partagent les mêmes écrans. Sur Apple TV les tailles sont celles d’un écran regardé depuis un canapé, la télécommande remplace le pointeur — l’icône sélectionnée du dock est celle qui grossit — et **Menu** tient lieu de Retour.

### Accueil

L’application s’ouvre sur l’accueil : TV, Films, Séries, Recherche, Favoris et Réglages forment un grand dock au milieu de la fenêtre, sur le décor adouci de l’espace. Le nom de la destination pointée s’affiche au-dessus avec son effectif — chaînes, films, séries, listes — et le décor devient celui de cet espace. Un clic, ou **Entrée**, ouvre la destination ; une section s’ouvre là où elle a été laissée.

**Retour** revient à l’écran précédent, écran après écran, jusqu’à l’accueil : la fiche se referme, puis la section laisse la place à celle qui la précédait. Un écran déjà visité ne revient qu’une fois, si bien que Retour ne tourne jamais en rond. À gauche du dock, un bouton porte le nom de l’écran où Retour ramène, et une maison ramène directement à l’accueil.

### Une seule logique au clavier et à la télécommande

- **Les flèches** vont au contrôle voisin.
- **OK** valide.
- **Retour** affiche la boussole des zones ; **une flèche** saute alors directement dans la zone voisine ; **Retour** une seconde fois revient à l’écran précédent.

Sous une longue liste, les flèches seules n’atteignent ni les commandes du haut ni le dock : c’est le rôle de la boussole. Elle encadre les zones de l’écran — **Haut** (recherche, actualiser, pages), **Colonne**, **Contenu**, **Aperçu** pour la télévision, **Dock** (avec Retour et Accueil) — et écrit où mène chaque flèche et où ramène Retour. Depuis le contenu, chaque zone est à deux pressions. La sélection arrive sur la catégorie, la chaîne ou la destination en cours ; **OK** referme la boussole sans rien changer. Depuis le dock, Retour revient directement.

Sur Mac, **Tab** et **⇧Tab** entrent dans la zone suivante ou précédente sans la boussole, et Réglages › Interface permet de la supprimer : Retour revient alors tout de suite à l’écran précédent.

### Dock

Hors de l’accueil, le dock se tient en bas de l’écran, au centre, comme le Dock de macOS, avec les mêmes icônes et le même thème que sur l’accueil. Rien de sa bande n’est perdu : Retour et Accueil sont à sa gauche, la date et l’heure à sa droite, et les colonnes s’arrêtent nettement au-dessus de lui. Les icônes grossissent sous le pointeur comme dans le Dock du système : celle qui est survolée vient en avant, ses voisines suivent, et le point sous le pointeur ne bouge pas. Un trait marque la destination affichée.

- **Emplacement** : en bas au centre (par défaut), sous la colonne de navigation, en haut, ou en colonne à gauche ou à droite. Sous la colonne, le dock est compact et les autres colonnes descendent jusqu’au bord ; Retour et Accueil passent alors en tête de colonne.
- **Thèmes** : Verre, Couleurs, Fumé, Néon et Sans fond.
- **Ordre** : glisser une icône dans le dock, ou utiliser les flèches de Réglages › Dock.
- Un clic secondaire sur le dock donne l’emplacement, le thème et l’agrandissement.

### Colonne de navigation

Chaque espace a la même colonne à gauche : tout le catalogue, les listes de favoris, « À reprendre » pour les films, puis les catégories avec leur effectif et un champ pour les filtrer. Un second clic sur la catégorie sélectionnée revient à tout le catalogue. Le bouton du haut ouvre, dans la colonne elle-même, le pays des chaînes ou la langue des films et des séries.

### Télévision

Trois colonnes : les catégories, les chaînes, puis l’aperçu avec les informations de la chaîne dessous. Les chaînes forment une seule liste, de haut en bas ; l’aperçu prend toute la largeur restante. La ligne sous le pointeur grossit et devient la sélection ; l’aperçu démarre après une seconde, sans le son ; un clic sur la ligne ou sur l’image ouvre la chaîne en plein écran. Au toucher, un premier appui sélectionne et un second ouvre.

Les informations sont celles de la liste : catégorie, pays reconnu, source et position. Aucun programme ni horaire n’est inventé ; l’EPG reste à venir.

### Films et séries par langue

La langue est lue dans l’étiquette qui précède le titre (`FR - Titre`, `4K-EN - Titre`), puis dans celle de sa catégorie (`FRANCE SÉRIES`, `ENGLISH MOVIES`). Les étiquettes de qualité et de marque (`4K`, `AMZ`) sont ignorées. Une étiquette portée par moins de trois titres est considérée comme un morceau de titre. Les titres sans étiquette restent accessibles sous **Langue non identifiée**, et le choix est mémorisé par source et par espace.

### Fiches

La fiche d’un film est un panneau de verre posé sur le catalogue, qui reste visible et flouté derrière. Le boîtier quitte le rayon, se tourne et vient se placer à gauche ; à droite, le titre, l’année, la durée, la note et les genres fournis, les commandes, le synopsis et les crédits. Fermer la fiche renvoie le boîtier à sa place.

La fiche d’une série reprend le principe de la télévision : les saisons sous le boîtier, les épisodes en liste de haut en bas, puis le visuel et la description de l’épisode sélectionné. L’épisode sous le pointeur grossit ; un clic le lit. Changer de saison se fait sans quitter la fiche.

Sur Apple TV ce sont les mêmes panneaux, le dock restant dessous. La fiche garde la télécommande : rien de ce qui est sous elle ne prend le focus, **Menu** la referme et rend la sélection à la jaquette. Dans une série, **Gauche** et **Droite** passent des saisons aux épisodes puis aux commandes, et chaque colonne s’ouvre sur ce qui y est sélectionné ; parcourir les saisons affiche aussitôt leurs épisodes. Rien ne défilant sous une télécommande, le synopsis montre les lignes qui tiennent et **Description complète** donne le texte entier, en verre lui aussi.

**Favoris et listes** d’un titre s’ouvre au-dessus de l’écran ou de la fiche, qui passent au flou : les listes, la création d’une liste, puis Lire, Annuler et Enregistrer. **Menu** le referme sans rien enregistrer et la télécommande retrouve le bouton d’où elle venait.

### Favoris, réglages et sources

**Favoris** réunit les listes des trois types de contenu dans la colonne de navigation ; une liste se crée, se renomme et se supprime sur place.

**Réglages** est un écran de la fenêtre. Il contient les **sources** : chaque source est une carte avec son type, ses effectifs et ses commandes, et le formulaire d’ajout ou de modification s’ouvre dans la page. La télécommande virtuelle s’affiche depuis Réglages › Interface.

### Clavier

Les flèches déplacent la sélection entre la colonne, la grille, l’aperçu et le dock, et parcourent le dock de l’accueil ; **Entrée** valide, **Échap** montre la boussole des zones puis revient à l’écran précédent jusqu’à l’accueil, **Tab** change de zone, **Espace** ouvre l’élément sélectionné, **⌘F** place le curseur dans la recherche et **⌘⇧F** bascule le lecteur en plein écran. Les réglages se parcourent encore au pointeur.

## Trois espaces, six thèmes chacun

| Contenu | Espace | Présentation |
|---|---|---|
| Films | Cinéma | Hall, salle, fauteuils, éclairage de séance |
| Séries | Vidéoclub | Rayons de séries, puis saisons et épisodes |
| Direct | Salon TV | Canapé, meuble TV, lumières domestiques |

Les six thèmes restent disponibles : Néo 80–90, Cinéma de minuit, Salon 70, Palace Art déco, Scandinave et Futur néon. Dans **Réglages → Interface**, chacun des trois espaces possède son propre choix.

Les 18 fonds 4K sont fabriqués par un script Blender à partir de géométrie et de matériaux procéduraux originaux, puis précalculés en JPEG 3840 × 2160. Le script reproductible, le manifeste et la planche des décors sont dans `scripts/rooms/`. Aucun calcul de pièce 3D continu n’est exécuté dans l’application. Une refonte des trois univers est inscrite à la [feuille de route](docs/ROADMAP.md).

## Apple TV

L’Apple TV reprend le bureau du Mac : accueil, dock en bas au centre, colonne de navigation, télévision en trois colonnes avec l’aperçu, catalogue des films et des séries, rayon des saisons, fiches en verre, favoris, réglages et sources dans l’écran, liste des chaînes sur l’image pendant un direct. Les pays et les langues se choisissent dans la colonne. Ce qui diffère encore du Mac : le dock ne se réordonne pas à la télécommande ; son emplacement et son thème se règlent dans Réglages › Dock.

**Charger une liste** et **Modifier la source** occupent tout l’écran : le type de source à gauche, les champs et les deux boutons à droite, visibles d’un coup, sans défilement.

## iPhone et iPad

La disposition de la 0.8.9 est conservée : bandeau TV, Films, Séries et Recherche, fiches plein écran, feuilles pour les catégories, les pays, les listes et les sources. Le tableau ci-dessous décrit cette disposition.

| Écran | Commande | Résultat |
|---|---|---|
| Catalogue | Directions | Déplacer la sélection |
| Film | Valider | Ouvrir sa fiche plein écran |
| Série | Valider | Ouvrir le rayon de ses saisons |
| Saison | Valider | Afficher la fiche et les épisodes |
| Fiche | Directions, puis Valider | Lecture, description complète, favoris ou retour |
| Fiche | Lecture/Pause | Lire le film ou l’épisode sélectionné |
| Épisodes | Gauche / Droite, puis Valider | Choisir et lire l’épisode |
| Fiche | Retour / Menu | Retrouver la sélection dans le catalogue ou le rayon |
| Chaînes TV | Rester sur une vignette | Démarrer l’aperçu après le délai choisi |
| Chaînes TV | Valider | Regarder la chaîne en plein écran |
| Catalogue | Appui long | Ouvrir les favoris et listes |

Sur Apple TV, **Réglages → Interface → Liquid Glass** applique le verre natif aux panneaux et aux commandes à partir de tvOS 26 ; il est actif par défaut. Le désactiver rétablit les surfaces sombres sans flou, plus légères à afficher. Sa fluidité sur un appareil physique reste à mesurer.

Le délai de l’aperçu des chaînes se règle sur 1, 3, 5 ou 10 secondes : une seconde par défaut au pointeur, trois sur Apple TV où la télécommande traverse beaucoup de vignettes.

## Lecture et commandes flottantes

La vidéo occupe la fenêtre entière ; le dock et la navigation sont retirés de cette vue. Les commandes de lecture se limitent à un panneau centré de largeur bornée, avec une petite capsule supérieure pour Retour, le titre et Plein écran. Afficher les commandes ne redimensionne pas l’image.

Le panneau se masque après trois secondes de lecture sans interaction ; pointeur, toucher, clavier et télécommande le rappellent. Pause, chargement, erreur, déplacement du curseur ou VoiceOver le maintiennent visible.

### Zapper sans quitter l’image

Pendant une chaîne en direct, la liste des chaînes vient se poser à gauche de l’image, en verre, sans arrêter la lecture : bord gauche de la fenêtre au pointeur, bouton **Liste des chaînes** des commandes, ou **←** quand les commandes sont masquées — sur Mac, iPad et Apple TV. **↑ ↓** choisissent, **Entrée** change de chaîne, **← →** passent à la catégorie voisine, **Échap** referme. La liste s’ouvre sur la chaîne regardée et se retire seule après douze secondes sans geste. Sans la liste, **↑** et **↓** zappent toujours directement.

### Réglages pendant la lecture

Sur Mac et sur Apple TV, les réglages demandés depuis le lecteur sont deux panneaux de verre posés sur l’image, qui continue de jouer derrière : Interface, Vidéo, Réseau, Audio et sous-titres, Bibliothèque et Diagnostic. La croix, **Échap**, **Menu** ou un clic à côté les referment. Sur iPhone et iPad, ils restent une feuille.

## Ce qui reste à faire pour le clavier du Mac

Les pages des Réglages se parcourent encore au pointeur : les flèches ne les traversent pas sur Mac, alors que la télécommande les atteint sur Apple TV. Les boutons d’une jaquette (étoile, options) se déclenchent au pointeur ou par un appui long.

## Installer

L’archive contient les sources et l’installateur Mac, pas un binaire Apple précompilé.

1. Sur Mac, quitter l’ancienne app et arrêter le lancement depuis Xcode.
2. Décompresser, puis ouvrir **Installer Flux IPTV.command**. L’installateur compile sur ce Mac et vérifie le démarrage ; cette vérification ne remplace pas un essai de lecture.
3. Vérifier **FLUX 0.9.0 · build 38** en bas de la colonne de Réglages.

Prérequis de déploiement : macOS 14, iOS 17 ou tvOS 17. Installer Xcode complet pour compiler ; le verre natif demande la version 26 des systèmes, les versions antérieures reçoivent un matériau translucide. Sur iPhone/iPad ou Apple TV, ouvrir `FluxIPTV.xcodeproj`, choisir **FluxIPTViOS** ou **FluxIPTVTV**, puis renseigner l’équipe de signature pour un appareil physique.

Le Mac garde AVPlayer natif ; le bouton VLC externe reste disponible pour les formats incompatibles. Les identifiants d’application et les préférences existantes sont conservés. Lire `LISEZ-MOI INSTALLATION.txt` pour les détails de signature et de Trousseau.

## Ouvrir le projet Apple TV

Ouvrir **`FluxIPTV-AppleTV.xcodeproj`**, ou lancer **`Ouvrir Flux IPTV Apple TV.command`**. Le projet dédié contient uniquement la cible et le schéma **FluxIPTVTV**. Choisir ensuite une destination Apple TV et exécuter avec ⌘R. Le schéma lance par défaut la configuration Release optimisée, sans débogueur.

« Mismatched platform » avec le schéma **FluxIPTV / My Mac** signifie que la destination ne correspond pas au schéma actif. Les détails sont dans [LISEZ-MOI APPLE TV.txt](<LISEZ-MOI APPLE TV.txt>) et la [documentation Apple](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

## Validation

Le périmètre vérifié pour cette version est dans [docs/VALIDATION-0.9.0.md](docs/VALIDATION-0.9.0.md), avec ce qui ne l’a pas été. Les tests unitaires du cœur ne démontrent ni la compilation des frameworks Apple, ni la fluidité réelle, ni la lecture des flux du fournisseur. Les résultats des versions précédentes ne valident pas la nouvelle interface du Mac.

## GitHub Actions et pack complet

Le dépôt complet est [M4D135/FluxIPTV](https://github.com/M4D135/FluxIPTV). Le workflow [Swift / Apple platforms](https://github.com/M4D135/FluxIPTV/actions/workflows/ci.yml) se lance à chaque push sur `main`, sur les branches `work/three-rooms-*`, lors des pull requests ou à la demande.

Actions exécute les tests du cœur, vérifie les 18 décors et les deux projets générés, puis compile séparément macOS, iOS Simulator, tvOS Simulator et tvOS ARM64 pour appareil. Un job indépendant prépare le pack complet des sources du commit exécuté, avec son empreinte SHA-256. Voir [docs/CI.md](docs/CI.md).

### Vérifications locales

```bash
swift test
bash scripts/check-state-declarations.sh
python3 scripts/rooms/verify_rooms.py
bash scripts/test-live-preview.sh
bash scripts/test-tvos-catalog-ui.sh
bash scripts/test-native-youtube.sh --live
bash scripts/test-youtube-session.sh
bash scripts/test-keychain-interaction.sh
bash scripts/check-keychain-platform.sh tvOS
bash scripts/check-keychain-platform.sh iOS
bash scripts/test-catalog-ui.sh
bash scripts/build-platforms.sh macOS
bash scripts/build-platforms.sh iOS
bash scripts/build-platforms.sh tvOS
bash scripts/build-platforms.sh tvOS-device
```

`scripts/test-catalog-ui.sh` ouvre de vraies fenêtres et prend le premier plan. Pour regarder l’interface sans quitter son travail, `FLUX_CATALOG_UI_BACKGROUND=1` garde les fenêtres hors écran et n’exécute que les captures ; `FLUX_CATALOG_UI_GALLERY=1` ajoute les thèmes et les emplacements du dock, l’accueil avec le pointeur sur Films puis sur Séries et le filtre par langue ; `FLUX_CATALOG_UI_SIZE=1728x1050` choisit la taille de la fenêtre. Quatre scénarios envoient à l’écran les touches d’une télécommande et vérifient où la sélection arrive.

Les versions précédentes sont conservées dans [docs/HISTORIQUE.md](docs/HISTORIQUE.md). Leurs anciennes commandes et résultats de tests ne décrivent pas la version actuelle.
