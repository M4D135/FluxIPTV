# FLUX IPTV 0.9.0 — build 38 — Bureau Mac : dock, colonnes et panneaux de verre

Application native SwiftUI pour macOS, iOS et tvOS.

**La 0.9.0 donne au Mac et à l’Apple TV la même interface de bureau.** L’application s’ouvre sur un accueil où le dock occupe le milieu de l’écran ; il se range ensuite en bas, au centre, comme le Dock de macOS, sous les colonnes qui accompagnent les trois espaces. La télévision se lit en trois colonnes, les fiches flottent en verre sur le catalogue flouté, et plus aucune feuille ne recouvre la fenêtre : catégories, pays, langues, listes, sources et réglages sont dessinés dans l’interface, y compris pendant la lecture. Les films et les séries se filtrent par langue, comme les chaînes par pays. Le dock garde ce que l’on y range, comme celui d’un Mac : des raccourcis vers une chaîne, un film, une série, une saison ou un épisode, dans des sections que l’on nomme, la vidéo en cours, les derniers titres regardés, et des listes de favoris en dossiers qui s’ouvrent en éventail.

iPhone et iPad conservent la disposition de la 0.8.9. Sur Apple TV, les effets complets — Liquid Glass à partir de tvOS 26, flou derrière une fiche, focus animé — sont actifs au départ sur l’Apple TV 4K de 2ᵉ génération et les suivantes ; l’Apple TV HD et la première Apple TV 4K commencent avec les surfaces sombres et le focus immédiat, et un réglage permet de changer.

## Le bureau, sur Mac et sur Apple TV

Les deux plateformes partagent les mêmes écrans, **aux mêmes proportions**. Le bureau est dessiné pour les 1920 × 1080 points d’un téléviseur regardé depuis un canapé ; la fenêtre du Mac montre ce bureau-là à sa propre taille : mêmes marges autour de l’image, même colonne, mêmes jaquettes, mêmes touches, mêmes tailles de texte rapportées à l’écran. Ce que l’on voit sur le Mac est ce que la télévision affichera. Sur Apple TV la télécommande remplace le pointeur — l’icône sélectionnée du dock est celle qui grossit — et **Menu** tient lieu de Retour. Sur le Mac, ce dont seul un pointeur a besoin n’apparaît que sous lui : l’étoile et les options d’une jaquette, par exemple.

### Accueil

L’application s’ouvre sur l’accueil : TV, Films, Séries, Recherche, Favoris et Réglages forment un grand dock au milieu de la fenêtre, sur le décor adouci de l’espace. Le nom de la destination pointée s’affiche au-dessus avec son effectif — chaînes, films, séries, listes — et le décor devient celui de cet espace. Un clic, ou **Entrée**, ouvre la destination ; une section s’ouvre là où elle a été laissée.

**Retour** est le bouton Précédent d’un navigateur : il referme d’abord ce qui est ouvert dans l’écran — une fiche, une liste, un panneau —, puis revient à l’écran précédent, écran après écran, dans l’ordre exact où ils ont été ouverts, jusqu’à l’accueil. Chaque écran se retrouve sur le titre qui y était sélectionné. À gauche du dock, un bouton porte le nom de l’écran où Retour ramène, et une maison ramène directement à l’accueil.

**Maintenu, Retour mène droit à l’accueil**, d’où que l’on soit : **Échap** maintenue au clavier, ou le bouton Retour du dock maintenu sous le pointeur — sous **OK** sur Apple TV. Le bouton Menu d’une télécommande maintenu appartient à tvOS, qui affiche alors son propre accueil : c’est donc le bouton du dock que l’on maintient.

### Une seule logique au clavier et à la télécommande

- **Les flèches** vont au contrôle voisin.
- **OK** valide ; une destination s’ouvre avec la sélection dans son contenu, sur le titre laissé la fois précédente.
- **Retour** revient en arrière.

Au-dessus du catalogue, une seule ligne : le nom de ce qui est affiché et ce qu’il contient, la recherche, les pages d’un catalogue de films ou de séries et Actualiser. Les jaquettes et les chaînes commencent juste dessous. **Page suivante** et **Page précédente** gardent la sélection, pour tourner les pages d’affilée ; **Bas** entre dans la page par son haut. Dans une colonne étroite la ligne perd d’abord son sous-titre, puis se replie sur deux.

Sur Apple TV, **Menu** est ce Retour et ne fait rien d’autre. Chaque colonne de l’écran répond comme un tout à la flèche qui pointe vers elle : depuis la liste, **Gauche** mène à la colonne de navigation, **Droite** à Regarder et Favoris, **Haut** à la recherche, **Bas** au dock, où que la télécommande se trouve dans la liste. La colonne s’ouvre sur la ligne de ce qui est affiché — toutes les chaînes, une liste, une catégorie — et non sur celle qui se trouve à la hauteur d’où l’on vient ; **Droite** en ressort sur le titre que l’on venait de quitter.

Au clavier du Mac comme à la télécommande, Retour revient directement en arrière. **Tab** et **⇧Tab** passent d’une zone de l’écran à l’autre. Réglages › Interface permet de faire d’abord afficher par Retour la boussole des zones : elle encadre **Haut** (recherche, actualiser, pages), **Colonne**, **Contenu**, **Aperçu** pour la télévision et **Dock**, et écrit où mène chaque flèche ; une flèche saute dans la zone voisine, **OK** la referme, Retour une seconde fois revient à l’écran précédent.

### Dock

Hors de l’accueil, le dock se tient en bas de l’écran, au centre, comme le Dock de macOS, avec les mêmes icônes et le même thème que sur l’accueil. Rien de sa bande n’est perdu : Retour et Accueil sont à sa gauche, la date et l’heure à sa droite, et les colonnes s’arrêtent nettement au-dessus de lui. Les icônes grossissent sous le pointeur comme dans le Dock du système : celle qui est survolée vient en avant, ses voisines suivent, et le point sous le pointeur ne bouge pas. Un trait marque la destination affichée.

- **Emplacement** : en bas au centre (par défaut), sous la colonne de navigation, en haut, ou en colonne à gauche ou à droite. Sous la colonne, le dock est compact et les autres colonnes descendent jusqu’au bord ; Retour et Accueil passent alors en tête de colonne.
- **Thèmes** : Verre, Couleurs, Fumé, Néon et Sans fond.
- **Ordre** : glisser une icône dans le dock, ou utiliser les flèches de Réglages › Dock.
- Un clic secondaire sur le dock donne l’emplacement, le thème et l’agrandissement.

### Ce que l’on garde dans le dock

Après ses six destinations, le dock tient ce que l’on y range, chaque partie séparée de la suivante par un trait, comme les parties du Dock d’un Mac :

- **Des raccourcis** vers une chaîne, un film, une série, une de ses saisons ou un de ses épisodes. L’icône est l’image du titre ; une pastille dit la saison ou l’épisode (S3, S12·E15). Une chaîne se lance, un film ouvre sa fiche, une série son rayon de saisons, une saison ou un épisode la fiche de la série ouverte dessus.
- **Des sections nommées.** « Favoris, listes et dock » — l’étoile d’un titre, ou un appui long sur lui — liste sous les listes de favoris les sections du dock : on coche celles qui gardent le titre, on en crée une en la nommant, exactement comme une liste. Depuis une série, on choisit d’y ranger la série, la saison affichée ou l’épisode choisi.
- **La vidéo en cours** : le film ou l’épisode laissé en route, avec sa progression ; un appui reprend la lecture. Puis **les derniers titres regardés**, trois au plus, que l’on peut garder d’un appui long. Réglages › Dock les masque.
- **Des dossiers.** Une liste de favoris se met dans le dock depuis son écran (« Dossier dans le dock »). Son icône montre ses premiers titres et leur nombre ; elle s’ouvre **en éventail** au-dessus du dock, ses titres l’un sur l’autre avec leur nom, et une dernière ligne ouvre la liste entière.

Le nom complet de l’icône pointée s’affiche au-dessus d’elle. Un appui long sur un raccourci — un clic secondaire sur Mac — rouvre ses listes pour le retirer ou le déplacer ; sur Mac on le fait aussi glisser dans sa section. Réglages › Dock renomme et supprime les sections.

Les icônes ne rapetissent jamais au point de ne plus se lire depuis un canapé : un dock bien rempli les réduit d’un cinquième au plus, cède la date puis le nom de l’écran précédent, retire d’abord les titres récents, et range enfin les raccourcis en trop dans un dossier **Autres**, à la suite des raccourcis. Rien de ce que l’on a gardé n’est perdu. Sous la colonne de navigation, le dock compact ne montre que ses destinations ; l’accueil montre tout.

Le dock ne retient que des identifiants du catalogue et des noms, comme les favoris : jamais une adresse de flux.

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

Les flèches déplacent la sélection entre la colonne, la grille, l’aperçu et le dock, et parcourent le dock de l’accueil ; **Entrée** valide, **Échap** revient à l’écran précédent jusqu’à l’accueil — maintenue, droit à l’accueil —, **Tab** change de zone, **Espace** ouvre l’élément sélectionné, **⌘F** place le curseur dans la recherche et **⌘⇧F** bascule le lecteur en plein écran. Les réglages se parcourent encore au pointeur.

## Trois espaces, six thèmes chacun

| Contenu | Espace | Présentation |
|---|---|---|
| Films | Cinéma | Hall, salle, fauteuils, éclairage de séance |
| Séries | Vidéoclub | Rayons de séries, puis saisons et épisodes |
| Direct | Salon TV | Canapé, meuble TV, lumières domestiques |

Les six thèmes restent disponibles : Néo 80–90, Cinéma de minuit, Salon 70, Palace Art déco, Scandinave et Futur néon. Dans **Réglages → Interface**, chacun des trois espaces possède son propre choix.

Les 18 fonds 4K sont fabriqués par un script Blender à partir de géométrie et de matériaux procéduraux originaux, puis précalculés en JPEG 3840 × 2160. Le script reproductible, le manifeste et la planche des décors sont dans `scripts/rooms/`. Aucun calcul de pièce 3D continu n’est exécuté dans l’application. Une refonte des trois univers est inscrite à la [feuille de route](docs/ROADMAP.md).

## Apple TV

L’Apple TV reprend le bureau du Mac : accueil, dock en bas au centre, colonne de navigation, télévision en trois colonnes avec l’aperçu, catalogue des films et des séries, rayon des saisons, fiches en verre, favoris, réglages et sources dans l’écran, commandes de lecture, langues et liste des chaînes sur l’image. Les pays et les langues se choisissent dans la colonne. **Menu** revient en arrière comme le Précédent d’un navigateur, et chaque destination s’ouvre avec la télécommande dans son contenu. Ce qui diffère du Mac : pas de boussole des zones, dont la télécommande n’a pas besoin, et le dock ne se réordonne pas à la télécommande ; son emplacement et son thème se règlent dans Réglages › Dock.

**Charger une liste** et **Modifier la source** occupent tout l’écran : le type de source à gauche, les champs et les deux boutons à droite, visibles d’un coup, sans défilement.

### Fluidité à la télécommande

Un appui de la télécommande ne reconstruit que ce qu’il concerne. L’écran garde son état en un seul endroit, et tout changement de cet état le reconstruisait en entier : avec le catalogue d’un abonnement réel — 58 093 films, 24 665 chaînes — un seul appui reconstruisait l’écran cinq fois, dont 89 jaquettes, 50 boutons et 40 lignes de la colonne. Désormais :

- chaque jaquette, chaque chaîne, chaque ligne de la colonne, la ligne du haut et la barre du bas disent de quoi elles sont dessinées, et sont laissées telles quelles tant que rien de cela ne change ;
- le focus est celui du système, que chaque contrôle lit lui-même : un appui redessine les deux contrôles concernés, et ce qui est dessiné comme sélectionné est toujours là où est la télécommande ;
- la fenêtre possède le focus du système et prévient l’écran qu’il a bougé, au lieu que l’écran soit reconstruit à chaque déplacement ;
- l’aperçu d’une chaîne n’est plus observé par l’écran entier, seulement par son image et sa touche de son.

Mesuré dans le simulateur, à la télécommande, un appui reconstruit l’écran une fois, sans aucune jaquette ; un parcours du banc le vérifie à chaque exécution. Les chiffres sont dans `docs/VALIDATION-0.9.0.md`.

Ce qui a le focus grossit et **suit le pouce posé sur la télécommande** : la jaquette, la chaîne ou l’icône du dock s’incline du côté où le pouce glisse et revient quand il se lève, comme les tuiles du système. Seul le calque bouge, rien n’est redessiné. L’effet de survol du système (`hoverEffect`) a été essayé et écarté : il redessine la tuile à chaque image, ce qui coûtait à lui seul plus que tout le reste d’un appui.

Une demande de focus faite avant que le contrôle puisse la recevoir est refusée par le système, d’autant plus souvent que l’appareil est lent, et se lit pourtant comme accordée. Les contrôles du lecteur, l’image nue et les titres du catalogue disent eux-mêmes quand ils ont la télécommande : la demande est répétée jusque-là, au retour d’une fiche, d’une série, d’un message ou d’un flux.

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

Sur Apple TV, **Réglages → Interface → Effets complets** réunit ce qui coûte à afficher : le verre natif des panneaux et des commandes à partir de tvOS 26, le flou de ce qui passe derrière une fiche, un message ou les réglages, et l’animation du focus. Le réglage est actif au départ sur l’Apple TV 4K de 2ᵉ génération et les suivantes, dont la puce est celle que le système demande pour son propre verre. Il est coupé au départ sur l’Apple TV HD et sur la première Apple TV 4K : les panneaux y sont des surfaces sombres, ce qui est derrière une fiche est assombri au lieu d’être flouté, et le focus se pose d’un coup. Le modèle est lu sur l’appareil ; le choix reste modifiable. La fluidité sur un appareil physique reste à mesurer.

Le délai de l’aperçu des chaînes se règle sur 1, 3, 5 ou 10 secondes : une seconde par défaut au pointeur, trois sur Apple TV où la télécommande traverse beaucoup de vignettes.

## Lecture et commandes flottantes

L’image occupe tout l’écran — sur Apple TV jusqu’aux bords du téléviseur —, sans dock ni navigation. Ce qui s’écrit par-dessus tient en deux endroits. En haut : **Retour**, le titre, et dessous « En direct », le numéro et la catégorie d’une chaîne, ou l’année, la durée et le genre d’un film ; à droite, l’heure. En bas : une barre de verre, sur le modèle du dock, dont chaque touche porte son nom.

| Direct | Film ou épisode | Toujours |
|---|---|---|
| Chaînes · Précédente · Pause · Suivante | −15 s · Pause · +15 s, sous la ligne du temps | Favori · Langues · Réglages |

La touche sous la télécommande, le clavier ou le pointeur devient blanche et grossit. **Favori** ajoute ou retire le titre des favoris d’une pression. Afficher les commandes ne redimensionne pas l’image.

Les commandes se retirent seules — après trois secondes au pointeur, cinq sur Apple TV — et tout geste les rappelle ; pause, chargement, erreur ou VoiceOver les maintiennent. Sur Apple TV, commandes masquées : **OK** les rappelle, **Haut** et **Bas** changent de chaîne, **Gauche** ouvre la liste des chaînes ou recule dans un film, **Droite** avance, **Lecture/Pause** suspend, **Menu** revient à l’écran d’où la lecture est partie.

### Le bandeau d’une chaîne

Une chaîne s’ouvre comme sur un téléviseur : son image, nue, et au pied de l’écran un bandeau de verre — son numéro, son logo, son nom sur une ligne entière, sa catégorie, l’heure et le rappel des touches. Le bandeau se retire après quatre secondes. **Haut** et **Bas** (**↑ ↓** au clavier) changent de chaîne sous ce seul bandeau : les commandes ne reviennent pas, et la pression suivante continue. Tant que le flux s’ouvre, le bandeau le dit à la place de « En direct » et reste affiché ; une chaîne qui ne répond pas y est marquée indisponible, et l’on passe à la suivante sans rien fermer. **OK**, un clic ou le pointeur rappellent les commandes, où le détail d’une erreur et **Réessayer** attendent. Un film ou un épisode s’ouvre, lui, sous ses commandes.

### Langues

**Langues** remplace la barre par un panneau à deux colonnes : les pistes audio à gauche, les sous-titres à droite, avec « Désactivés ». Le choix s’applique aussitôt, quel que soit le moteur — Apple ou VLC. Retour referme le panneau et la sélection revient sur la touche Langues.

### Zapper sans quitter l’image

Pendant une chaîne en direct, la liste des chaînes vient se poser à gauche de l’image, en verre, sans arrêter la lecture : bord gauche de la fenêtre au pointeur, touche **Chaînes** des commandes, ou **←** quand les commandes sont masquées — sur Mac, iPad et Apple TV. Elle prend la place des commandes. **↑ ↓** choisissent, sans limite : la liste tourne sa page toutes les soixante chaînes. **Entrée** ou **OK** change de chaîne, la liste restant ouverte pour continuer ; sur Apple TV, **Lecture/Pause** fait de même. **← →** passent à la catégorie voisine, **Échap**, **Menu** ou un clic à côté referme : les commandes reviennent sur la touche Chaînes si elle avait ouvert la liste, sinon l’image reste nue. La liste s’ouvre sur la chaîne regardée et se retire seule après douze secondes sans geste, deux secondes après que le pointeur l’a quittée. Sans la liste, **↑** et **↓** zappent toujours directement, sous le bandeau de la chaîne, et **Suivante** garde la sélection pour continuer. Les noms longs d’une liste de lecture y tiennent entiers : la liste est plus large, et un nom rétrécit avant d’être coupé.

### Réglages pendant la lecture

Sur Mac et sur Apple TV, **Réglages** pose deux panneaux de verre sur l’image, qui continue de jouer derrière : Interface, Vidéo, Réseau, Audio et sous-titres, Bibliothèque et Diagnostic. Tant qu’ils sont ouverts, les commandes attendent dessous et rien ne les masque. La croix, **Échap**, **Menu** ou un clic à côté les referment, et la sélection revient sur la touche Réglages. Sur iPhone et iPad, ils restent une feuille.

Un réglage est enregistré dès qu’il est choisi : il n’y a pas de bouton Enregistrer à ne pas manquer. Ceux que le moteur lit à l’ouverture d’un flux — moteur, décodage, cache, délais — s’appliquent au flux suivant ; pendant une lecture, une ligne le dit et propose **Relancer le flux**.

Sur Apple TV, parcourir la liste des pages affiche chacune aussitôt, **Droite** entre dans la page et **Gauche** revient sur la page en cours. Les choix sont des touches du bureau, lisibles et jamais coupées, avec leur nom au-dessus.

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
