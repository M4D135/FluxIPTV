# Historique antérieur à la version 0.8.2

Ces notes décrivent les versions anciennes. Le README à la racine fait foi pour la navigation actuelle. Les résultats de validation historiques ne valent pas validation de la version 0.8.2.

# FLUX IPTV 0.8.1 — Grille complète et pochettes 3D plein écran

Correctif de la régression 0.8.0. **Néo Vidéoclub 90 et Apple Cinema ont le même parcours** : grille de tout le catalogue, puis sélection d’un film ou d’une série pour ouvrir le boîtier en plein écran dans la fenêtre. Aucun mode de navigation à choisir. Les concepts restent deux styles visuels distincts dans Réglages > Interface.

- « Toutes » efface recherche, catégorie, liste de favoris et filtre « À reprendre ». « Catalogue complet » a le même comportement. Un changement d’onglet repart du catalogue complet, sans supprimer les favoris ni l’historique. Les favoris et les reprises restent des filtres facultatifs.
- La grille paginée (24 à 120 cartes) reste visible, assombrie et inactive, derrière l'inspection. Trois boîtiers procéduraux au maximum dans une seule surface SceneKit/Metal : jaquette centrale entière (environ 90 % de la hauteur de la scène sur un grand écran), voisine précédente et suivante plus petites en retrait. À la première/dernière entrée, le voisin inexistant n'est pas inventé. Les lumières ont été réduites pour limiter la surexposition des couvertures.
- Clic/OK sur une carte pour l'agrandir, glissement pour la tourner, gauche/droite pour changer de titre même au-delà de la page de grille. L’ordre de consultation est celui de la grille lors de l'ouverture, même si un filtre est actualisé. Clic dans le vide ou bouton Reposer pour revenir à la grille ; les contrôles flottants restent hors de l'affiche. La page et le focus de retour sont recalculés.
- Le bandeau des commandes est compact ; les liens et réglages d'épisodes complémentaires apparaissent au verso. Sur Mac, ⌘⇧F permet de basculer le plein écran natif de la fenêtre ; la vue de la pochette couvre déjà le contenu de l'application. Sur tvOS, elle remplit le panneau TV. Les télécommandes virtuelles et le geste à deux doigts sont conservés.
- Aucun changement du moteur de lecture ou du stockage des identifiants. L'application Mac ne lie toujours pas VLCKit.

Validation locale : 69 tests Swift réussis, dont trois nouveaux tests de périmètre de filtrage, voisins entre pages et cadrage. Contrôle syntaxique des trois cibles et des déclarations SwiftUI. Ce sont des vérifications Linux du cœur et de la syntaxe, pas un build Xcode ni une capture réelle de l'interface. La fluidité, les transitions et le focus doivent être validés sur Mac et Apple TV. Archive de sources avec installateur Mac, pas un binaire précompilé.

Les sections historiques ci-dessous décrivent les anciennes versions ; leur mode carrousel permanent est remplacé par le parcours ci-dessus.

---

# FLUX IPTV 0.8.0 — Deux concepts cinéma (candidat)

Cette livraison reprend la base 0.7.5. **Réglages > Interface > Concept films et séries** : sélectionnez Néo Vidéoclub 90 ou Apple Cinema. Le choix est persistant et indépendant des six thèmes existants. Le salon TV et la lecture gardent leurs réglages et leur fonctionnement.

- **Néo Vidéoclub 90** : rayonnages et arches procéduraux, trois pochettes disposées symétriquement, commandes centrales flottantes et accents rétro.
- **Apple Cinema** : fond du film si disponible, composition éditoriale asymétrique sur écran large, titre/synopsis à gauche, trois boîtiers à droite, décor abstrait léger. Sur écran étroit, la composition devient verticale.
- Films et séries : le carrousel permanent remplace l'ancien choix galerie/grille. Trois maillages seulement dans un SCNView, accès direct au voisin précédent/suivant et aux favoris. Prendre une pochette agrandit la scène et autorise rotation et consultation. Son recto conserve la jaquette entière ; le verso montre les informations et, pour les séries, les cartes d'épisodes. Les boutons sont hors du recto/verso, dans un bandeau. Un clic vide referme la pochette. Les contrôles de la pochette incluent navigation, lecture, rotation, favoris et liens disponibles.
- Navigation : souris/trackpad, clavier, télécommande virtuelle ou commandes tvOS. La surface 3D de navigation est retirée pendant l'inspection puis recréée au retour ; les trois objets de l'inspection partagent un seul SCNView. Pas de décor 3D actif pendant la lecture. Les proportions et géométries sont pilotées par `ClubInterfaceProfile`, prévu pour accueillir d'autres concepts.
- FERRO : les nouveaux décors exploitent le sous-ensemble de génération géométrique porté en Swift, documenté dans `docs/FERRO-CINEMA.md`. Ce n'est pas une intégration du runtime FERRO complet. La 3D des boîtiers est rendue par SceneKit/Metal ; les décors sont des images calculées à partir de maillages procéduraux. Les jaquettes restent celles du fournisseur IPTV.

Installation : fermer l'ancienne application, décompresser puis lancer `Installer Flux IPTV.command` sur Mac. Le projet Xcode contient trois cibles ; cette archive contient les sources, pas un binaire Apple précompilé. Aucun changement des identifiants d'application ou de la politique de stockage des sources.

Validation : 66 tests du cœur Swift réussis sur Linux, dont les trois tests des concepts (persistance, voisins bornés et géométrie déterministe). Analyse syntaxique Swift par cible et contrôle des déclarations @State. **Xcode, rendu réel, hit tests et télécommande physique sur matériel Apple non vérifiés.** Les maquettes générées précédemment étaient des références de design, pas des captures de cette build. La conformité visuelle doit être évaluée après compilation.

---

# FLUX IPTV 0.7.5 — Correctif de compilation SwiftUI

Trois déclarations `@State` groupées dans `CasePresentation.swift` sont désormais six déclarations indépendantes. Xcode 26 refuse les déclarations groupées avec la macro `@State` ; elles empêchaient la compilation de la 0.7.4. Aucun changement de logique du geste à deux doigts, du pavé V1/V2, de la lecture, ni du stockage des sources. L’installateur utilise un répertoire de compilation distinct pour la version 0.7.5.

Validation locale : 63 tests du cœur Swift réussis ; garde SwiftSyntax vérifiée sur les versions 0.7.4 (3 déclarations rejetées) et 0.7.5 (52 fichiers, 0 erreur) ; analyse syntaxique sur les trois cibles. La compilation complète Xcode et les gestes réels doivent être confirmés sur matériel Apple.

# FLUX IPTV 0.7.4 — Pavé virtuel et trackpad Mac

Survolez la zone tactile de la télécommande virtuelle noire (V1) ou aluminium avec le pointeur, puis glissez à deux doigts sur le trackpad sans cliquer. Dans le catalogue, un geste directionnel déplace le focus une fois, sans sélectionner. Dans la pochette ouverte, le mouvement horizontal tourne le boîtier et le vertical l'incline, avec stabilisation au relâchement. Un indicateur cyan confirme le geste reçu. Les boutons de la télécommande et le clic au centre restent inchangés. Le défilement ailleurs dans la fenêtre conserve son comportement normal.

Validation : 63 tests du cœur Swift réussis, syntaxe des sources contrôlée pour les trois cibles Apple. Le comportement réel des événements AppKit et la compilation Xcode restent à vérifier sur Mac.

# FLUX IPTV 0.7.3 — Rotation tactile des pochettes

Candidat source Mac, iOS, tvOS, avec installateur. Ouvrir une pochette, puis glisser **deux doigts sans clic** sur le trackpad du Mac. Horizontal : tourner la boîte ; vertical : incliner. Au relâchement d’un mouvement horizontal, la boîte s’oriente vers le recto ou le verso. La rotation à la souris (clic-glissé), le clic sur les commandes imprimées, les flèches et les commandes vidéo sont conservés. Le pavé des télécommandes virtuelles peut désormais faire tourner le boîtier en glissant. Le port tvOS dispose d'un reconnaisseur de pan sur la Siri Remote, à qualifier sur appareil. La rotation ne s'exécute que quand la pochette est ouverte ; les événements précis provenant du trackpad sont consommés dans sa surface et ne pilotent pas les rayons. La scène se met à jour directement pendant le geste, puis s'arrête au repos. La fin du geste ignore le défilement inertiel natif pour éviter une double rotation. Le sens suit le défilement configuré par macOS.

Validation 0.7.3 : 61 tests du cœur Swift réussis (7 nouveaux tests de rotation), analyse syntaxique des 34 fichiers Swift pour macOS, iOS et tvOS, projet Xcode régénéré, syntaxe du script d’installation contrôlée. Le geste et le rendu sur les appareils Apple ne sont pas testés ici : compiler et vérifier le suivi du doigt, la libération du geste et le focus sur Mac et Apple TV. Aucun changement au moteur de lecture ni au stockage des sources dans ce lot.

# FLUX IPTV 0.7.2 — Videoclub 3D, matières HD et grands catalogues

**Candidat source pour macOS, iOS et tvOS**. Lancer `Installer Flux IPTV.command` sur Mac, puis utiliser l’app installée. Le numéro visible dans FLUX doit être 0.7.2. Pas de binaire précompilé ni de compilation Xcode dans cet environnement.

## Pochettes physiques plein écran

- Plus de panneau latéral de détails : le recto, le verso et la tranche sont des textures de l'objet 3D. Le clic est détecté par intersection avec le maillage et coordonnées UV. Le verso contient synopsis, distribution, réalisateur, liens Wikipédia/Allociné, bande-annonce si disponible. Les séries affichent leurs saisons et quatre cartes d'épisodes numérotées par page, avec miniatures du fournisseur (sinon jaquette de la série ou symbole). Les liens externes restent des recherches ; les bandes-annonces directes utilisent AVPlayer seul, en remplacement temporaire de la surface 3D.
- La pochette occupe la fenêtre et garde son orientation en passant aux titres voisins. Animation de prise/repose, rotation libre souris/tactile. Gauche/droite : titre voisin ; haut/bas : focus sur les actions imprimées ; clic central : action ou retourner ; lecture/pause : lire ou ouvrir les épisodes ; MENU : revenir à la fiche ou reposer. Action imprimée 360° (ou options du pavé virtuel) : rotation avec les quatre directions, clic pour quitter ce mode. ⌘⇧F : basculer le plein écran natif Mac depuis une pochette. Focus tvOS et hit-testing Apple à valider sur appareil.
- Réglages > Interface > Matières et pochettes 3D : Éco (640 × 960, 30 i/s ciblées), HD équilibré (1024 × 1536, 60 i/s ciblées), Cinéma HD+ (1536 × 2304, 60 i/s ciblées). Le rendu utilise SceneKit/Metal, pas un navigateur ni une rotation d'image plane. Maillage fermé de 360 triangles en HD (216 en Éco) : coins et chanfreins arrondis, jointure et tranche imprimée, normales lisses. PBR, couche de vernis, rugosité, carte de microrelief déterministe 128², éclairage à trois sources, probe de réflexion générée 256 × 128 et ombre douce précalculée. MSAA 2× seulement sous un budget de pixels. Pas de ray tracing, d'ombres dynamiques ni de post-traitement plein écran. Les affiches et miniatures sont des images du fournisseur et non procédurales ; leur netteté réelle dépend de la source. Les textures générées sont du texte et des matières calculés, pas des assets importés.
- Un seul boîtier en vraie 3D. Les textures sont calculées hors de l'acteur principal, sur modification seulement ; le focus est un quad indépendant. La boucle de scène est arrêtée après la transition/manipulation. La galerie cachée ne dessine pas pendant l'inspection ; la surface 3D est démontée à la lecture.

## Fluidité et authentification

- Index par identifiant, catégorie et type, recherche différée hors UI, fenêtres de 64 éléments en galerie et 24 à 120 en grille. Navigation directe même entre pages, téléchargement/décodage des images limité à quatre tâches simultanées. Cache HD distinct (cible 16 Mio), miniatures (32 Mio), fonds (16 Mio) ; budgets NSCache indicatifs. Un benchmark synthétique vérifie l'index sur 60 000 entrées, pas le FPS de l'application sur matériel Apple.
- Les refus d'accès silencieux au Trousseau s'affichent dans l'interface, sans boîte de dialogue système automatique. Sources > Modifier : ressaisir les identifiants, ou récupérer volontairement depuis l'ancien Trousseau. Sur Mac, choisir éventuellement **Sur ce Mac, sans Trousseau** avant de vérifier/enregistrer. Cette option est explicite : secrets non chiffrés dans Application Support avec dossier 700, fichier 600 ; accessibles à un processus ayant les mêmes droits utilisateur. Le Trousseau demeure recommandé pour une signature stable. UUID des sources et favoris conservés. Aucun mot de passe dans le dépôt ni dans les préférences. La persistance entre changements d'identité de sandbox reste à valider sur Mac.
- VLC intégré reste désactivé sur Mac, suite au crash OpenGL signalé ; VLC externe reste accessible. Les cibles mobiles conservent leur intégration expérimentale.

## Vérification

54 tests XCTest du cœur passent sous Linux (dont index, picking UV, maillage, textures déterministes, stockage privé, formats). Analyse syntaxique des 33 sources Swift pour les trois cibles ; génération Xcode et syntaxe de l'installateur contrôlées. **Aucune compilation, capture de rendu, mesure de FPS, ni lecture réelle sur Apple n'a été réalisée ici.** Le réalisme visuel, la transition, l'orientation effective des textures et les contrôles Siri Remote nécessitent donc une validation sur appareil. SceneKit reste utilisé pour cette version afin de minimiser les modifications du pipeline déjà existant. Les sections suivantes documentent les versions historiques et leurs limites.

---

# FLUX IPTV 0.7.1 — Recto/verso, télécommande et accès cinéma

- Corrige les UV verticales du boîtier pour SceneKit/Metal (haut = 0, bas = 1), en préservant la symétrie horizontale du verso et le volume fermé. L'ancienne image n'est plus réutilisée lors du changement de film.
- Navigation tvOS : le boîtier est un contrôle focalisable ; clic pour passer en manipulation, gauche/droite pour changer de titre, haut/bas pour incliner, nouveau clic pour revenir aux commandes. Les autres boutons restent disponibles via le focus natif. Les télécommandes simulées et le clavier Mac conservent leurs actions. Le rayon recentre la pochette avant son retour.
- Allociné : recherche externe ciblée sur les fiches film/série via Google, sans URL de recherche Allociné non fiable ni API privée. Titres nettoyés des préfixes IPTV et suffixes saison/épisode, année si disponible. Wikipédia utilise le même titre normalisé. Les liens restent des recherches, pas une association automatique à une fiche vérifiée. Aucun identifiant IPTV n'est envoyé par cette recherche ; seul le titre et l'année sont transmis.
- Trousseau : les opérations automatiques sont non interactives, avec restauration du réglage d'interaction du processus sous macOS. En cas de refus, ouvrir Sources > Modifier > Déverrouiller le Trousseau. L'autorisation interactive est volontaire. Les secrets ne sont ni copiés en clair ni supprimés lors de la mise à jour. Les sources M3U distantes deviennent modifiables en conservant leur UUID. Une autorisation explicite peut encore être nécessaire après un changement de signature.
- Le correctif précédent désactivant VLC intégré sur Mac reste en place.

Validation : 41 tests du cœur Swift sous Linux ; contrôle syntaxique des sources. Pas de validation Xcode, SceneKit, Trousseau ou Siri Remote physique sur Apple. Sources avec installateur Mac, pas de binaire précompilé.

---

# FLUX IPTV 0.7.0 — VIDÉOCLUB NÉO-RÉTRO (candidat)

Cette version remplace la 0.6.0. Dans la barre FLUX, le numéro **0.7** permet de vérifier la version ouverte. Dans Réglages, Interface, les thèmes du vidéoclub et du salon TV sont indépendants et mémorisés. Le thème par défaut est Néo 80–90.

## Deux univers

- Films et séries : rayonnages procéduraux, galerie de jaquettes et fond du contenu sélectionné. Un clic ouvre une pochette volumétrique. Glissez pour la tourner sur deux axes, utilisez Retourner, Incliner et Recentrer, ou les boutons de la télécommande. Précédent/Suivant conserve l’orientation. Reposer ferme la fiche avec une transition vers le rayon. Le bouton Regarder/Épisodes lance ensuite le contenu. Épisodes : miniatures du fournisseur ou de la série en secours, Sxx Exx lorsque les numéros existent, titre, synopsis disponible et progression.
- TV : décor de salon distinct, grand écran, zapping, bandeau avec logo, nom, position dans le catalogue filtré et catégorie. Le bandeau s'efface après 3,6 secondes. Le guide EPG n'est pas encore intégré ; aucun programme horaire n'est inventé.
- Six thèmes : Néo 80–90, Cinéma de minuit, Salon 70, Palace Art déco, Scandinave et Futur néon. Les recettes changent la géométrie, la palette et les accents. La pochette est un maillage fermé de 60 triangles (recto, verso et tranche chanfreinée) rendu par SceneKit/Metal. Une seule surface 3D interactive existe à la fois. Les décors sont des projections statiques de volumes procéduraux, mises en cache ; ce n'est pas un moteur de déplacement libre dans un magasin. La vidéo n'a aucune boucle de rendu décorative ; en mode salon non plein écran un fond déjà mis en cache peut rester visible.
- Liquid Glass natif avec SDK et OS 26 compatibles, matériau système en secours. Respect des options d'accessibilité. Les thèmes gardent les réglages de sources et listes existants.

## Fiches cinéma

Lecture à la demande de get_vod_info et get_series_info Xtream, sans persistance des URL de lecture. Synopsis, année, durée, genre, note, acteurs, réalisateur et bande-annonce si le fournisseur les retourne. Les liens directs MP4/MOV/HLS s'ouvrent dans un lecteur séparé de bande-annonce. Les autres liens ouvrent le navigateur (QR sur tvOS). Wikipédia et Allociné : recherches externes explicites par titre et année, pas d'aspiration de leurs bases ni d'association automatique non vérifiée. Une véritable intégration de données externes et un EPG restent à développer.

## Correctif du plantage VLC sur Mac

Le plantage signalé dans vlc_gl_filter_ApplyOutputSize appartient au moteur VLC. Cette build **n'importe ni ne lie VLCKit sur macOS**. Le lecteur natif AVPlayer est seul actif. Si un flux échoue, le bouton « Ouvrir dans VLC externe » permet de le confier au lecteur VLC officiel installé par l'utilisateur. Cela évite de créer le décodeur problématique dans le processus FLUX, mais ne démontre pas la résolution de tous les freezes. Le transfert externe ne conserve pas le contrôle interne ni l'historique de la position dans VLC. Les cibles iOS/tvOS conservent l'intégration VLCKit expérimentale avec contrôle de taille de surface ; elles restent à qualifier sur appareils. Le projet partagé peut encore résoudre le paquet SPM pour les autres cibles.

## Installation et validation

Fermer toute ancienne instance et Xcode, décompresser puis lancer `Installer Flux IPTV.command`. Le script compile sur le Mac, contrôle la signature et l'absence de liaison VLCKit, vérifie le démarrage, restaure l'ancienne app si le lancement échoue. Le numéro de version et les nouvelles pages doivent être visibles dans l'application installée. Les identifiants du Trousseau sont conservés. Une autorisation initiale peut subsister en cas de changement de signature.

37 tests du cœur Swift sur Linux, comprenant la géométrie fermée, les six thèmes et deux décors, la projection et les métadonnées. Analyse syntaxique des sources pour macOS, iOS, tvOS. Pas de compilation Xcode ni validation de rendu ou de lecture sur Apple effectuées dans cet environnement. Il s'agit d'un candidat source avec installateur Mac, pas d'un binaire précompilé. Les sections suivantes sont historiques : les instructions VLC Mac et la sélection à deux clics y sont remplacées par celles ci-dessus.

---

# FLUX IPTV 0.6.0 — CINÉMA 3D (candidat)

Refonte native partagée macOS / iOS / tvOS : galerie horizontale 3D pour films et séries, grille TV ou grille classique en option, espace de prévisualisation, fond d’écran du média sélectionné (panoramique Xtream si disponible, sinon jaquette), Liquid Glass Apple activé par défaut sur OS/SDK 26 compatibles et matériau système sur versions antérieures.

- Sélection Mac/iOS : un premier clic choisit la jaquette et affiche le fond ; un second clic ou « Regarder » lance le média. Le focus et le clic tvOS restent natifs. Les flèches, télécommandes virtuelles et navigation souris/clavier sont conservées.
- Trois décors 3D (Orbites, Prismes, Horizon) calculés en Swift à partir de maillages de tubes issus d'une adaptation du module de géométrie de FERRO. Désactivables et indépendants du lecteur. Voir [provenance et budget](docs/FERRO-CINEMA.md).
- Six pages de configuration : Interface, Vidéo, Réseau, Audio et sous-titres, Bibliothèque, Diagnostic. Apparence immédiate ; réglages du flux appliqués explicitement. Les pistes VLC restent à compléter.
- Mode de récupération si une tentative VLC précédente n'a pas été terminée proprement : priorité exclusive au moteur Apple jusqu'à réactivation explicite de VLC via Diagnostic. Une fermeture forcée peut déclencher ce mode. L'ouverture du support vidéo VLC attend la présence d'une fenêtre. Ce sont des protections, pas une preuve que la cause d'un crash réel est résolue.
- Aucun mot de passe ni URL de lecture ajouté au stockage. Le bundle Mac et les clés des sources/favoris/historique sont conservés.

**Validation :** 33 tests unitaires Swift sous Linux, syntaxe vérifiée pour les trois cibles. Les tests de géométrie contrôlent les normales, le déterminisme, la projection, le budget et les entrées invalides. Le SDK Xcode, le rendu Liquid Glass, le lecteur et les crashs sur Mac réel ne peuvent pas être validés ici. Archive de sources avec installateur, non binaire compilé.

# FLUX IPTV 0.5.0 — Master (candidat)

- Reprise des films et épisodes, historique local limité à 1000 entrées sans URL ni identifiants. Progression visible, filtre films à reprendre, recommencer par menu contextuel.
- Actualisation de la source sans effacer le catalogue en cas d’échec, conservation des recherches.
- 29 tests du cœur Swift réussis ; compilation et lecture Apple non vérifiées.

# FLUX IPTV 0.4.1 — Réglages de lecture

## Nouveautés

Profils réseau rapide, équilibré et stable ; moteur automatique/Apple/VLC, cache, délai d’ouverture, reconnexion limitée du direct, décodage matériel VLC, limite indicative du débit adaptatif Apple, saut vidéo et sélection des pistes Apple. Préférences locales persistantes. Enregistrer sans couper la lecture ou appliquer et relancer. Les pistes VLC ne sont pas encore sélectionnables. Les films et séries ne redémarrent pas automatiquement. 27 tests du cœur Swift passent ; compilation Xcode et tests réels à effectuer.

# FLUX IPTV 0.4.0 — Grand écran

Lecteur IPTV natif SwiftUI pour Mac. Cette version sert aussi de base de portage pour iPhone, iPad et Apple TV : **les trois cibles Xcode compilent les mêmes sources**, sans dupliquer le moteur, les listes, les formulaires ni le catalogue.

## 0.4.0 — Présentation TV légère et ergonomie Mac

- Grandes cartes et affiches, fond statique, barre d'accès vitrée sobre, recherche et catégories sélectionnables, favoris et options accessibles directement sur les cartes. Le style léger est activé par défaut. Sur Mac/iOS, le menu de présentation permet d'activer les effets Liquid Glass natifs lorsque le SDK et le système les prennent en charge. Pas de flou derrière la vidéo, pas d'animation continue ni d'image d'arrière-plan en lecture.
- Télécommandes simulées noire (pavé tactile) et aluminium (clickpad) dessinées en SwiftUI : ouverture facultative à côté du catalogue, modèle mémorisé, zones cliquables, glisser et appui prolongé. Les fonctions Siri, Home et Power simulées correspondent uniquement aux actions internes de FLUX. Sur Apple TV, le système gère les touches réservées et le focus matériel.
- Navigation souris/trackpad, clavier et boutons directs : pas de recentrage automatique des cartes au clic ; recentrage réservé à la navigation par télécommande/clavier. En lecture, transport compact, volume, sourdine et commandes de sortie du plein écran accessibles sans télécommande.
- Miniatures réseau décodées hors du thread principal, côté 512 px maximum, cache mémoire limité à 32 Mio (limite indicative NSCache), aucune image stockée dans un cache disque par ce chargeur. Les affiches ne sont pas chargées en arrière-plan du lecteur. Les publications répétitives des valeurs vidéo identiques sont réduites.
- Installateur Mac : build Debug autonome (comme le schéma Xcode déjà lancé), chemins de chargement contrôlés, signature vérifiée, test de survie du processus, restauration du bundle précédent en cas d'échec du lancement. Ce contrôle ne remplace pas un test de lecture réelle. Un certificat stable reste préférable pour le Trousseau.

## Nouveautés

- Interface inspirée de l'application TV : grandes cartes, affiches des films/séries, logos TV, navigation, catégories, recherche, focus contrasté et commandes flottantes. Liquid Glass facultatif sur macOS/iOS 26 avec Xcode 26 ; dégradés statiques pour le mode léger et tvOS.
- **Deux moteurs intégrés** : AVPlayer et VideoLAN VLCKit. HLS privilégie Apple ; MKV/TS/AVI privilégient VLC. Bascule automatique en cas d'échec d'ouverture, délai d'essai limité, choix manuel du moteur et réessai. Les épisodes Xtream utilisent leur extension déclarée et les URL `direct_source` autorisées en secours. En cas d'extension absente, une variante MKV est essayée. Aucun accès aux identifiants pendant un changement de contenu.
- Chaînes, films, séries, saisons/épisodes, listes personnalisées indépendantes et migration des favoris 0.1/0.2. Navigation dans les saisons et passage à l'épisode précédent/suivant, y compris entre saisons.
- Télécommande virtuelle tactile Mac/iOS : glisser, clic, maintien, boutons directionnels, MENU, accueil interne, recherche, lecture/pause, volume local, muet, zapping et navigation vidéo ±15 secondes, plein écran et options.
- Utilisation des contrôleurs détectés par GameController sur Mac/iOS, et clavier (flèches, Entrée, Échap, espace). La télécommande Apple TV physique est traitée par le moteur de focus tvOS ; les fonctions système (bouton TV/Home, Siri, volume) restent sous contrôle du système.
- Réglage Xtream conservé, saisie et validation avant persistance, collage d'un lien, édition. Import M3U distant partout, local sur Mac/iOS. Les mots de passe et URL M3U sont conservés dans le Trousseau ; cache de session uniquement en RAM.

## Lancer sur Mac

1. Décompresser l'archive ou cloner le dépôt.
2. Ouvrir `FluxIPTV.xcodeproj`.
3. Sélectionner **FluxIPTV** et **My Mac**. Attendre la résolution Swift Package Manager du paquet officiel VLCKit (Internet nécessaire au premier build).
4. Appuyer sur ⌘R. Pour l'accès au Trousseau, garder une identité de signature stable entre les compilations.
5. Ouvrir Sources pour ajouter/modifier les accès existants. Choisir Télécommande pour afficher le pavé de test.

Prérequis : macOS 14+, Xcode 16+ ; Xcode 26+ recommandé pour les API de Liquid Glass. Le paquet VideoLAN est épinglé sur la révision `7f98c70f9f0c11fbdf828220890bd6280361ae99`, un build de développement 4.0 du 9 novembre 2026 dont le manifeste déclare macOS/iOS/tvOS. Il ne s'agit pas d'une validation des binaires sur ces trois appareils.

## Préparer iOS et Apple TV

| Schéma | Destination | Déploiement minimum |
|---|---|---|
| FluxIPTV | My Mac | macOS 14 |
| FluxIPTViOS | iPhone/iPad Simulator ou appareil | iOS 17 |
| FluxIPTVTV | Apple TV Simulator ou appareil | tvOS 17 |

Sélectionner le schéma voulu dans Xcode. Pour un appareil physique, renseigner l'équipe de développement dans Signing & Capabilities. Les identifiants de bundle sont distincts pour iOS/tvOS ; le bundle Mac reste **com.m4d135.FluxIPTV** pour conserver les sources/favoris. Aucun transfert automatique d'identifiants entre appareils n'est implémenté. Saisie native tvOS et clavier de la télécommande iPhone ; pas d'import de fichier M3U local sur tvOS.

```bash
swift test                      # tests Foundation (possible sous Linux)
bash scripts/build-macos.sh      # compile macOS
bash scripts/build-platforms.sh  # compile Mac + simulateurs iOS/tvOS, sans signature
bash scripts/build-platforms.sh tvOS
```

## Télécommande de première génération

Sur Apple TV, glisser sur la surface tactile pour naviguer, presser pour sélectionner, maintenir sur une carte pour afficher le menu contextuel. MENU revient en arrière. Lecture/Pause commande le moteur vidéo. En plein écran, sélectionner Commandes pour afficher la barre ; gauche/droite permettent un saut de 15 s sur la vidéo à la demande ; haut/bas permettent de zapper en direct. Les touches TV/Home, microphone et volume sont réservées au système et aux équipements configurés. Les fonctions d'accueil, recherche et volume du pavé virtuel Mac correspondent à des actions **internes à FLUX**, pas à la simulation de Siri ou HDMI-CEC.

Sur Mac, le pavé virtuel et le clavier fonctionnent indépendamment de l'appairage d'une télécommande physique. Le bridge GameController reçoit les périphériques reconnus par macOS/iOS. L'ancien modèle Siri Remote peut nécessiter une intégration Bluetooth/logiciel spécifique au Mac ; sa détection physique n'a pas été testée. Le focus natif reste utilisé sur tvOS. Les feuilles de saisie et réglages utilisent les contrôles natifs Apple (clavier/souris sur Mac, focus sur Apple TV) plutôt que le pavé virtuel de l'écran principal.

## Validation et limites

- 24 tests XCTest du cœur passent sous Swift 6.2.1 / Linux, dont plans de lecture, URLs Xtream, listes, cache d'identifiants et navigation au pavé tactile. Analyse syntaxique Swift de tous les fichiers et vérification des références des trois cibles/schémas.
- **Pas de Xcode ni d'appareil Apple dans l'environnement de préparation.** La compilation SwiftUI et le chargement de la bibliothèque VLCKit épinglée, la lecture vidéo, le focus Siri Remote physique et le rendu Liquid Glass doivent être validés sous Xcode. Aucun essai sur un serveur IPTV privé n'a été effectué ; une erreur réseau, d'accès, de format ou de serveur peut encore empêcher la lecture d'un épisode.
- Le premier build récupère une dépendance binaire VLCKit externe. Vérifier la présence des slices simulateurs et les obligations de licence VideoLAN/LGPL avant de distribuer l'application. Ne pas qualifier cette version de release App Store.
- ATS HTTP reste permissif pour les sources fournies par l'utilisateur ; privilégier HTTPS. Aucun DRM contourné. Certaines variantes serveur et directives M3U propriétaires ne sont pas gérées.
- EPG, choix des pistes audio/sous-titres, lecture automatique de l'épisode suivant, synchronisation sécurisée interappareils et icônes de distribution restent à faire.

## Architecture

`Sources/FluxIPTVCore/` : modèles, Xtream/M3U, favoris, URLs, plan des lecteurs, focus/gestes indépendant de SwiftUI. `FluxIPTVMac/` : sources SwiftUI **communes** (le nom de dossier est conservé par compatibilité), adaptateurs vidéo NSView/UIView, bibliothèque, Trousseau, input, présentation vitrée légère et chargeur de miniatures. `scripts/generate-xcodeproj.py` : génération déterministe des trois cibles. `Tests/FluxIPTVCoreTests/` : tests Linux/Apple. Voir [docs/ROADMAP.md](docs/ROADMAP.md).

Utiliser uniquement les accès auxquels vous êtes autorisé. Aucun compte, fournisseur ni contenu n'est fourni. Ne jamais envoyer d'URL de média ou d'identifiants dans Git ou les journaux.

© 2026 M4D135. Tous droits réservés à ce stade.
