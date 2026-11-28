# FLUX IPTV 0.9.10 — build 51 — Bureau Mac : dock, colonnes et panneaux de verre

Application native SwiftUI pour macOS, iOS et tvOS.

**La 0.9.10 allège l’application.** À l’écran, deux choses changent sur l’Apple TV : l’aperçu d’une chaîne continue quand la sélection quitte la liste pour la colonne, la recherche ou le dock, comme sur le Mac, et une fiche apparaît et s’efface d’un seul fondu, sans que son boîtier reste à l’écran. Mesurée au simulateur Apple TV, elle dépense moitié moins de calcul pendant la lecture d’un film (−52 %) et près d’un tiers de moins pour descendre une longue liste de chaînes (−31 %) ; sur l’Apple TV 4K du salon, deux tiers de moins pendant un film (−66 %), et le banc y ouvre désormais la télévision, les listes et la grande grille, où celui de la 0.9.9 débordait la pile du fil principal : un appui qui mène d’un titre à un autre de la page ne redessine plus l’écran entier, et le temps qui passe pendant la lecture ne redessine plus que son bandeau. La mémoire baisse d’un quart sur les écrans des chaînes et des films. Le cœur commun lit une liste M3U de 92 000 entrées en 182 ms au lieu de 2,6 s, charge un catalogue Xtream de 92 000 titres en 0,5 s au lieu de 0,9, cherche dans tout le catalogue en 1 ms au lieu de 72, et son index pèse 7,5 Mo au lieu de 116. L’application de l’Apple TV passe de 89,0 à 61,1 Mo : ses fonds sont livrés à la taille où elle les décode (5,9 Mo au lieu de 14,5), son exécutable sans ses 19 Mo de symboles, et le lecteur des bandes-annonces, inutilisé depuis le build 33, part avec YouTubeKit. Release compile désormais l’application en module entier. Les mesures, les changements et l’audit des sources sont détaillés dans [docs/OPTIMISATION.md](docs/OPTIMISATION.md).

**La 0.9.9 rend la télécommande de l’Apple TV plus cohérente.** Au bout à droite d’un écran, Droite ne descend plus dans le dock : elle repart à gauche, à la même hauteur, comme une ligne de texte — sur la colonne, sinon sur le premier titre de la ligne. En mode souris, le pointeur devient au-dessus d’une liste (chaînes, grille des films et des séries, colonnes) un pointeur de défilement : il garde sa hauteur, le pouce fait défiler la liste sous lui vers le haut et le bas, il longe la ligne vers la gauche et la droite, et il sort de la liste en tirant au-delà d’un côté ; un coup de pouce lance la liste, un toucher l’arrête. Le pointeur offre six formes, six couleurs, six tailles, cinq vitesses et trois accélérations (Réglages › Télécommande › Pointeur), avec un aperçu. Le clic du pointeur sur « Classique », dans les Réglages, rend de nouveau la télécommande classique : en 0.9.8, il ne faisait rien, et seul Lecture/Pause maintenue y revenait. Une bulle dit chaque changement de mode.

**La 0.9.8 met la barre de l’accueil en bas, sur une seule rangée.** Comme sous les autres écrans, elle se tient au pied de la fenêtre, mais elle garde la grande taille de l’accueil ; ce qu’elle ne peut pas tenir va dans « Autres ». Le nom de ce qui est sélectionné reste à la hauteur où il se tenait. Un dossier qui s’ouvre a maintenant toute la place entre la barre et le haut de l’écran, sans atteindre le nom de l’application ni l’heure : en 0.9.7, ses titres, dessinés à la taille de l’accueil mais comptés à celle du dock des écrans, pouvaient monter jusque-là. **Le dock peut aussi se masquer sous les écrans** (Réglages › Dock › Emplacement) : chaque écran prend alors toute la fenêtre, Retour et Accueil passent en haut de la colonne, et l’accueil garde sa barre pour aller partout. Sur l’accueil, une destination sélectionnée — TV, Films, Séries… — montre le fond de son écran, même quand l’accueil a le sien : celui-ci reste derrière ce que l’on garde dans le dock. Sur Apple TV, l’aperçu d’une chaîne continue quand la sélection passe sur Regarder, Favoris ou le son, à côté de l’image : en 0.9.7, il s’arrêtait dès qu’elle quittait la ligne de la chaîne, et le bouton du son disparaissait avec lui. La 0.9.8 rétablit enfin la compilation pour iPhone et iPad, cassée en 0.9.7 par l’écran de la recherche.

**La 0.9.7 retire l’heure de la barre du bas.** Le plan de l’écran, qui allume la partie qui a la sélection à côté de la touche qui passe à la suivante, prend sa place dans le coin bas droite, aussi grand que l’était l’heure. L’heure reste sur l’accueil et pendant la lecture. Sur l’accueil, le nom de la destination sélectionnée et sa ligne se tiennent désormais au-dessus de l’icône que la loupe agrandit, quelle que soit la loupe : ils ne la touchent plus. Un titre gardé dans la barre n’y porte plus de bulle à son nom : elle recouvrait le grand nom, qui le dit déjà. Les 27 parcours de la télécommande de la 0.9.6 passent aussi sur une vraie Apple TV 4K, en tvOS 26.6.1 ; la 0.9.7 y est installée, sans que ses parcours y aient été rejoués.

**La recherche devient un écran à part, sur Mac et sur Apple TV.** La touche Recherche du dock ouvre son propre écran, avec son fond : le champ prend la télécommande, et la colonne dit où chercher — Chaînes, Films, Séries, avec ce que la recherche trouve dans chacun —, garde les six dernières recherches et l’efface. Une recherche qui ne trouve rien laisse la télécommande dans cette colonne. Retour revient à l’écran d’où l’on était parti, tel qu’il était. Une section ne garde plus de recherche : en 0.9.6, une recherche restée dans les Séries y revenait à chaque visite, avec le fond de Recherche et une liste filtrée. Sur une nouvelle installation, chaque écran prend le fond choisi sur l’Apple TV du séjour : Archives infinies pour l’accueil, Salon néon 90 pour la TV, Grande salle pour les Films, Coin binge-watching pour les Séries, Observatoire pour la Recherche et Studio aux boutons pour les Réglages. Un fond déjà choisi ne change pas.

**La 0.9.6 rend les flèches au mode souris.** En 0.9.4 et en 0.9.5, une flèche de la télécommande ne déplaçait plus la sélection en mode souris. Le pointeur apprenait trop tard qu’une flèche était enfoncée : tvOS avait déjà refusé le déplacement, comme pour un glissement. Il l’apprend désormais au moment de l’appui ; la sélection avance, et le pointeur la suit. Un nouveau parcours du banc, qui pointe un message, a montré le défaut ; un autre pointe les réglages pendant la lecture.

**La 0.9.5 étend le mode souris à toute l’Apple TV.** Le pointeur sélectionne maintenant les Réglages : la colonne, dont la page suit le pointeur, et chaque touche du contenu. Poussé contre le bas d’une page plus longue que l’écran, il s’y arrête et la page défile. Il sélectionne aussi le panneau « Favoris, listes et dock », les messages, les réglages pendant la lecture et Audio et sous-titres, au-dessus de l’image. Le studio d’apparence a son propre pointeur : le curseur se pose où il s’arrête, et un clic choisit. Un glissement n’y déplace plus le curseur ; les flèches le déplacent toujours, et le pointeur les suit. Dans une fiche, un clic appuie de nouveau sur la commande survolée : en 0.9.4, il y restait sans effet. Seul le formulaire d’une source garde la télécommande classique ; le pointeur s’y efface.

**La 0.9.4 rend la télécommande intelligente.** Sur Apple TV, un **mode souris** fait suivre au pouce un pointeur sur le pavé tactile, et un clic appuie sur ce qu’il survole. On le choisit dans Réglages › Télécommande, ou l’on passe d’un mode à l’autre en maintenant **Lecture/Pause**. Dans une grille de films ou de séries, **Droite** au bout d’une rangée passe à la suivante, comme on lit une page. **Retour** sort d’abord du contenu vers le bouton Retour de la barre, d’où le dock et l’accueil sont à une flèche ; un second Retour change d’écran. Une page **Graphismes** règle l’affichage comme dans un jeu : **Automatique** choisit selon l’appareil détecté, chaque réglage reste à part. La partie de l’écran qui tient la télécommande se signale par un liseré, traversé d’un reflet quand on y entre, et un petit plan de l’écran remplace « Zone suivante ». La loupe du dock grossit davantage, sur cinq tailles, et l’icône sélectionnée prend un contour, un halo ou se soulève. Trois thèmes illustrés rejoignent le dock : Néon 90, Verre nocturne et Art déco. L’aperçu des chaînes démarre après une seconde, Apple TV comprise. L’application est préparée pour l’App Store ([docs/APP-STORE.md](docs/APP-STORE.md)). Une Apple TV de 3ᵉ génération n’installe aucune application : seule la recopie d’écran AirPlay d’un Mac, d’un iPhone ou d’un iPad peut y montrer Flux IPTV.

**La 0.9.3 ouvre le studio d’apparence.** Chaque écran — accueil, TV, Films, Séries, Recherche, Réglages — garde son fond et son thème de dock, ou suit ceux de tous les écrans. Il y a seize fonds dessinés et un diaporama réglé écran par écran ; les anciens décors, avec leurs enseignes « FLUX », sont retirés. De nouveaux fonds sont à dessiner ([docs/FONDS-A-DESSINER.md](docs/FONDS-A-DESSINER.md)). Le dock a quinze thèmes en quatre familles, du verre d’aujourd’hui aux pixels de 1977. Ce que le curseur pointe s’essaie aussitôt en plein écran, et OK le garde. Trois préréglages règlent l’affichage d’un coup, de **Fluide**, pour une Apple TV ancienne, à **Qualité**. Au bord de l’écran, aucune flèche ne reste sans effet. **Lecture/Pause** fait le tour des zones dans le sens des aiguilles d’une montre. L’application a maintenant son icône.

**La 0.9.2 répare le dock sur Apple TV** : en tvOS 26, la sélection avançait dans la barre — on l’entendait — mais le dock restait dessiné sur l’icône de l’écran, sans grossir. Il suit de nouveau la télécommande, et l’icône sélectionnée grossit avec ses voisines comme sous le pointeur d’un Mac.

**La 0.9.1 ouvre les Réglages au clavier du Mac** : ses flèches les parcourent comme la télécommande d’une Apple TV, et **O** ouvre « Favoris, listes et dock » pour le titre sélectionné.

**La 0.9.0 donne au Mac et à l’Apple TV la même interface de bureau.** L’application s’ouvre sur un accueil où le dock occupe le milieu de l’écran ; il se range ensuite en bas, au centre, comme le Dock de macOS, sous les colonnes qui accompagnent les trois espaces. La télévision se lit en trois colonnes, les fiches flottent en verre sur le catalogue flouté, et plus aucune feuille ne recouvre la fenêtre : catégories, pays, langues, listes, sources et réglages sont dessinés dans l’interface, y compris pendant la lecture. Les films et les séries se filtrent par langue, comme les chaînes par pays. Le dock garde ce que l’on y range, comme celui d’un Mac : des raccourcis vers une chaîne, un film, une série, une saison ou un épisode, dans des sections que l’on nomme, la vidéo en cours, les derniers titres regardés, et des listes de favoris en dossiers qui s’ouvrent en éventail.

iPhone et iPad conservent la disposition de la 0.8.9. Sur Apple TV, les panneaux sont en verre sur tous les modèles, comme sur le Mac : le verre de tvOS 26 à partir de l’Apple TV 4K de 2ᵉ génération, et sur l’Apple TV HD et la première Apple TV 4K, auxquelles tvOS ne le donne pas, un verre dessiné avec le flou du système. Les mouvements de la sélection ont leur propre réglage.

## Le bureau, sur Mac et sur Apple TV

Les deux plateformes partagent les mêmes écrans, **aux mêmes proportions**. Le bureau est dessiné pour les 1920 × 1080 points d’un téléviseur regardé depuis un canapé ; la fenêtre du Mac montre ce bureau-là à sa propre taille : mêmes marges autour de l’image, même colonne, mêmes jaquettes, mêmes touches, mêmes tailles de texte rapportées à l’écran. Ce que l’on voit sur le Mac est ce que la télévision affichera. Sur Apple TV la télécommande remplace le pointeur — l’icône sélectionnée du dock est celle qui grossit — et **Menu** tient lieu de Retour. Sur le Mac, ce dont seul un pointeur a besoin n’apparaît que sous lui : l’étoile et les options d’une jaquette, par exemple.

### Accueil

L’application s’ouvre sur l’accueil : TV, Films, Séries, Recherche, Favoris et Réglages forment un grand dock en bas de la fenêtre, sur une seule rangée, sur le fond adouci de l’écran. Ce que l’on garde dans le dock s’y range à la suite ; ce que la rangée ne peut pas tenir va dans « Autres ». Le nom de la destination pointée s’affiche au-dessus avec son effectif — chaînes, films, séries, listes — et le fond devient celui de cet écran, même quand l’accueil a son propre fond : ce fond-là reste derrière les titres et les dossiers gardés dans le dock. Un clic, ou **Entrée**, ouvre la destination ; une section s’ouvre là où elle a été laissée.

**Retour** est le bouton Précédent d’un navigateur : il referme d’abord ce qui est ouvert dans l’écran — une fiche, une liste, un panneau. Depuis le contenu — une grille de films ou de séries, la liste des chaînes, une page de réglages —, il confie ensuite la sélection au bouton Retour de la barre, à côté de l’accueil et du dock. Un second Retour revient à l’écran précédent, écran après écran, dans l’ordre exact où ils ont été ouverts, jusqu’à l’accueil. Chaque écran se retrouve sur le titre qui y était sélectionné. À gauche du dock, un bouton porte le nom de l’écran où Retour ramène, et une maison ramène directement à l’accueil.

**Maintenu, Retour mène droit à l’accueil**, d’où que l’on soit : **Échap** maintenue au clavier, ou le bouton Retour du dock maintenu sous le pointeur — sous **OK** sur Apple TV. Le bouton Menu d’une télécommande maintenu appartient à tvOS, qui affiche alors son propre accueil : c’est donc le bouton du dock que l’on maintient.

### Une seule logique au clavier et à la télécommande

- **Les flèches** vont au contrôle voisin.
- **OK** valide ; une destination s’ouvre avec la sélection dans son contenu, sur le titre laissé la fois précédente.
- **Retour** sort du contenu vers la barre, puis revient en arrière.

Au-dessus du catalogue, une seule ligne : le nom de ce qui est affiché et ce qu’il contient, la recherche, les pages d’un catalogue de films ou de séries et Actualiser. Les jaquettes et les chaînes commencent juste dessous. **Page suivante** et **Page précédente** gardent la sélection, pour tourner les pages d’affilée ; **Bas** entre dans la page par son haut. Dans une colonne étroite la ligne perd d’abord son sous-titre, puis se replie sur deux.

Sur Apple TV, **Menu** est ce Retour et ne fait rien d’autre. Chaque colonne de l’écran répond comme un tout à la flèche qui pointe vers elle : depuis la liste, **Gauche** mène à la colonne de navigation, **Droite** à Regarder et Favoris, **Haut** à la recherche, **Bas** au dock, où que la télécommande se trouve dans la liste. La colonne s’ouvre sur la ligne de ce qui est affiché — toutes les chaînes, une liste, une catégorie — et non sur celle qui se trouve à la hauteur d’où l’on vient ; **Droite** en ressort sur le titre que l’on venait de quitter.

Au clavier du Mac comme à la télécommande, Retour passe par la barre avant de revenir en arrière. Une longue liste met la ligne de la recherche et la barre du bas à beaucoup de flèches d’un titre : **une touche passe d’une partie de l’écran à l’autre** — **Tab** au clavier (**⇧Tab** en sens inverse), **Lecture/Pause** sur la télécommande d’une Apple TV. Elle fait le tour de l’écran dans le sens des aiguilles d’une montre : depuis le contenu, un appui mène à la barre (après les boutons à droite de l’aperçu d’une chaîne), un deuxième à la colonne, un troisième à la recherche, un quatrième au titre que l’on avait quitté. Un petit plan le rappelle dans le coin bas droite, à côté du dock — au pied de l’écran, au milieu, quand le dock est ailleurs ; il disparaît avec le dock masqué. Il allume la partie qui tient la sélection, près de la touche à presser. **Aucune touche n’est morte au bord de l’écran** : Gauche depuis la colonne mène au bouton Retour, Haut depuis Retour revient où l’on était ; Droite au bout d’une rangée de jaquettes passe au début de la rangée suivante ; Droite au-delà des boutons d’une chaîne et Haut depuis la recherche mènent à l’icône de l’écran ; la barre fait le tour, et Bas depuis elle remonte à la recherche. Une rafale d’appuis s’arrête au bord, l’appui suivant après une courte pause le franchit. Sur le Mac, **⌘ + une flèche** va droit à la partie de ce côté : ⌘↑ la recherche, ⌘↓ la barre, ⌘← la colonne, ⌘→ le contenu. Réglages › Clavier (Télécommande sur Apple TV) choisit ce que fait Retour dans un écran : **Remonter à la barre** (par défaut), **Quitter l’écran** tout de suite, comme jusqu’à la 0.9.3, ou, sur le Mac, **Montrer le plan** de l’écran : il encadre **Haut** (recherche, actualiser, pages), **Colonne**, **Contenu**, **Aperçu** pour la télévision et **Dock**, et écrit où mène chaque flèche ; une flèche saute dans la partie voisine, **OK** la referme, Retour une seconde fois revient à l’écran précédent.

### Dock

Hors de l’accueil, le dock se tient en bas de l’écran, au centre, comme le Dock de macOS, avec les mêmes icônes et le même thème que sur l’accueil. Rien de sa bande n’est perdu : Retour et Accueil sont à sa gauche, le plan de l’écran dans le coin à sa droite, et les colonnes s’arrêtent nettement au-dessus de lui. Les icônes grossissent sous le pointeur comme dans le Dock du système : celle qui est survolée vient en avant, ses voisines suivent, et le point sous le pointeur ne bouge pas. Sous la télécommande et le clavier, l’icône sélectionnée grossit de même. Un trait marque la destination affichée.

- **Emplacement** : en bas au centre (par défaut), sous la colonne de navigation, en haut, ou en colonne à gauche ou à droite. Sous la colonne, le dock est compact et les autres colonnes descendent jusqu’au bord ; Retour et Accueil passent alors en tête de colonne.
- **Afficher le dock sur les écrans** : oui par défaut. Masqué, il laisse toute la fenêtre aux écrans — les colonnes, la grille et les listes descendent jusqu’au bord — et Retour et Accueil passent en tête de colonne ; le plan de l’écran disparaît avec lui. L’accueil garde son dock, d’où l’on va partout. **Dock par défaut** le remontre.
- **Loupe et sélection** : l’agrandissement de l’icône sélectionnée — Aucune, Légère (celle de la 0.9.3), Normale (par défaut), Forte ou Maximale — et son allure : **Contour** blanc comme le focus de tvOS, **Halo** de sa couleur, ou **Soulevé** au-dessus de son ombre.
- **Thèmes** : dix-huit, en cinq familles.
  - Flux : Verre, Couleurs, Fumé, Néon, Sans fond.
  - Téléphones et bureaux d’aujourd’hui : Tactile, Galets, Givre.
  - Années 2000 : Gélule, Collines.
  - Rétro : Biseaux, Huit couleurs, Quatre couleurs, Bureau vert, Phosphore.
  - Illustrés : Néon 90, Verre nocturne, Art déco. Leur plaque et leurs icônes sont des images dessinées pour eux.

  Ils rappellent des systèmes connus sans reprendre ni leur nom ni leurs images. Chaque écran peut garder le sien, depuis le studio d’apparence.
- **Ordre** : glisser une icône dans le dock, ou utiliser les flèches de Réglages › Dock.
- Un clic secondaire sur le dock donne l’emplacement, le thème, l’agrandissement et l’allure de l’icône sélectionnée.

### Ce que l’on garde dans le dock

Après ses six destinations, le dock tient ce que l’on y range, chaque partie séparée de la suivante par un trait, comme les parties du Dock d’un Mac :

- **Des raccourcis** vers une chaîne, un film, une série, une de ses saisons ou un de ses épisodes. L’icône est l’image du titre ; une pastille dit la saison ou l’épisode (S3, S12·E15). Une chaîne se lance, un film ouvre sa fiche, une série son rayon de saisons, une saison ou un épisode la fiche de la série ouverte dessus.
- **Des sections nommées.** « Favoris, listes et dock » — l’étoile d’un titre, ou un appui long sur lui — liste sous les listes de favoris les sections du dock : on coche celles qui gardent le titre, on en crée une en la nommant, exactement comme une liste. Depuis une série, on choisit d’y ranger la série, la saison affichée ou l’épisode choisi.
- **La vidéo en cours** : le film ou l’épisode laissé en route, avec sa progression ; un appui reprend la lecture. Puis **les derniers titres regardés**, trois au plus, que l’on peut garder d’un appui long. Réglages › Dock les masque.
- **Des dossiers.** On crée un dossier dans le dock depuis « Favoris, listes et dock » (« Créer un dossier du dock », dans la barre ou dans un autre dossier) ou, vide, depuis Réglages › Dock. C’est une seule icône de la barre, qui s’ouvre **en éventail** : ses titres sortent de l’icône l’un après l’autre, leur nom à côté d’eux. Un dossier peut en contenir d’autres, jusqu’à quatre de profondeur : la ligne d’un dossier montre ses titres à la place des autres, la première ligne et **Retour** ramènent au dossier du dessus. Un dossier long montre ses titres un éventail à la fois. Son icône se choisit parmi vingt-six dans Réglages › Dock, ou sur le Mac par un clic secondaire sur elle ; sans choix, elle montre ses premiers titres. Réglages › Dock fait aussi d’une section un dossier, range un dossier dans un autre, le renomme et le supprime.
- **Les listes de favoris en dossiers.** Une liste de favoris se met dans le dock depuis son écran (« Dossier dans le dock ») ; elle s’ouvre de la même façon, et sa dernière ligne ouvre la liste entière.
- **Le menu Favoris réunit tout.** Sous chaque genre, après ses listes, il montre les sections et les dossiers du dock qui gardent des titres de ce genre.

Le nom complet de l’icône pointée s’affiche au-dessus d’elle. Un appui long sur un raccourci — un clic secondaire sur Mac — rouvre ses listes pour le retirer ou le déplacer ; sur Mac on le fait aussi glisser dans sa section. Réglages › Dock renomme et supprime les sections.

Les icônes ne rapetissent jamais au point de ne plus se lire depuis un canapé : un dock bien rempli les réduit d’un cinquième au plus, cède le nom de l’écran précédent, retire d’abord les titres récents, et range enfin les raccourcis en trop dans un dossier **Autres**, à la suite des raccourcis. Rien de ce que l’on a gardé n’est perdu. Sous la colonne de navigation, le dock compact ne montre que ses destinations. **L’accueil garde ses grandes icônes, sur une seule rangée**, au pied de l’écran : les raccourcis en trop y vont aussi dans **Autres**, et les titres récents ne partent que si la place manque encore. Un dossier qui s’y ouvre a toute la hauteur, jusque sous le haut de l’écran. L’icône sélectionnée y grandit avec ses voisines, comme sous le pointeur, au clavier comme à la télécommande.

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

Les flèches déplacent la sélection entre la colonne, la grille, l’aperçu et le dock, et parcourent le dock de l’accueil ; **Entrée** valide, **Échap** revient à l’écran précédent jusqu’à l’accueil — maintenue, droit à l’accueil —, **Tab** passe à la partie suivante de l’écran et **⌘ + flèche** va droit à celle de ce côté, **Espace** ouvre l’élément sélectionné, **⌘F** place le curseur dans la recherche et **⌘⇧F** bascule le lecteur en plein écran. **O** ouvre « Favoris, listes et dock » pour le titre sélectionné, comme OK maintenu sur une télécommande, et les réglages pendant la lecture.

Dans **Réglages**, les flèches vont d’un contrôle à l’autre : parcourir la colonne affiche chaque page, **Droite** entre dans la page, **Gauche** revient sur la page en cours, **Entrée** fait ce que fait un clic, et au-delà de la dernière ligne la sélection revient au dock. **Tab** passe de la colonne à la page, puis au dock.

## Studio d’apparence

Réglages › Interface › **Studio d’apparence** ouvre en plein écran deux rayons : **Fonds** et **Dock**. Le studio s’ouvre sur sa vitrine : derrière ses onglets passent les trois images dessinées pour la boutique.

- **Pour quel écran** : tous les écrans, ou un seul (Accueil, TV, Films, Séries, Recherche, Réglages). Un écran choisi garde ce qu’on lui donne. « Comme tous les écrans » le rend au choix commun ; « Le même partout » rend tous les écrans au choix commun.
- **Fonds**, trois choix :
  - **Automatique** : chaque écran montre, l’une après l’autre, les images dessinées pour lui ; l’accueil montre celles de l’écran qu’ouvre son icône sélectionnée.
  - **Aucun** : la couleur de l’écran, le plus léger à afficher.
  - **Images choisies** : parmi les seize fonds dessinés (deux ou trois par écran, trois pour la boutique, voir [docs/FONDS.md](docs/FONDS.md)).
- **Diaporama** : plusieurs images choisies passent l’une après l’autre. On règle leur ordre et leur durée (15 s, 30 s, 1, 5 ou 15 min). Elles passent dans l’ordre ou au hasard, en fondu ou d’un coup.
- **Dock** : les dix-huit thèmes, rangés par famille, essayés sur un dock posé sur le fond de l’écran.
- **Essayer avant de garder** : ce sur quoi le curseur s’arrête s’essaie aussitôt derrière le studio, et **Plein écran** le montre seul. **OK** le garde pour l’écran choisi. **Lecture/Pause** sur la télécommande, **Espace** au clavier, passe en plein écran ; une touche en revient. **Retour** referme le studio ; ce qui est gardé reste en place.
- **Collections** : chaque fond et chaque thème appartient à une collection, comme « Fonds dessinés · TV » ou « Docks · Rétro », et porte « Inclus ». Tout est fourni avec l’application ; l’essai restera gratuit quand une collection aura un prix.

Au clavier comme à la télécommande, les flèches parcourent le studio rangée par rangée, et chaque rangée garde sa place, comme sur une console. Le studio dessine son propre curseur. Sur le Mac, le pointeur essaie ce qu’il survole et un clic choisit.

## Couleurs de TV, Films et Séries

Les six thèmes de couleurs restent disponibles : Néo 80–90, Cinéma de minuit, Années 70, Palace Art déco, Scandinave et Futur néon. Dans **Réglages → Interface**, TV, Films et Séries ont chacun le leur : il colore les repères de l’écran et son fond uni.

Derrière les écrans, les fonds sont les images dessinées pour eux ([docs/FONDS.md](docs/FONDS.md)), décodées à la taille où elles s’affichent. Les dix-huit décors précalculés des versions précédentes, leur script Blender et leurs enseignes « FLUX » sont retirés depuis la 0.9.3. Aucun calcul de pièce 3D n’est exécuté dans l’application. Une refonte des trois univers est inscrite à la [feuille de route](docs/ROADMAP.md).

## Apple TV

L’Apple TV reprend le bureau du Mac : accueil, dock en bas au centre, colonne de navigation, télévision en trois colonnes avec l’aperçu, catalogue des films et des séries, rayon des saisons, fiches en verre, favoris, réglages et sources dans l’écran, commandes de lecture, langues et liste des chaînes sur l’image. Les pays et les langues se choisissent dans la colonne. **Menu** revient en arrière comme le Précédent d’un navigateur, après être passé par la barre, et chaque destination s’ouvre avec la télécommande dans son contenu. Ce qui diffère du Mac : pas de plan de l’écran sur Retour, dont la télécommande n’a pas besoin, et le dock ne se réordonne pas à la télécommande ; son emplacement et son thème se règlent dans Réglages › Dock, et le thème de chaque écran dans le studio d’apparence.

**Charger une liste** et **Modifier la source** occupent tout l’écran : le type de source à gauche, les champs et les deux boutons à droite, visibles d’un coup, sans défilement.

### Mode classique ou mode souris

Réglages › **Télécommande** choisit le mode de la télécommande. On passe aussi de l’un à l’autre en maintenant **Lecture/Pause** ; une bulle dit le mode choisi.

- **Classique** : un glissement sur le pavé tactile va d’un élément au suivant, comme jusqu’ici.
- **Souris** : un pointeur suit le pouce sur le pavé. Ce qu’il survole prend la sélection — une jaquette, une chaîne, une icône du dock — et un clic appuie dessus. Un appui sur un bord du pavé déplace toujours la sélection, comme une flèche. Pendant la lecture le pointeur s’efface, et l’image garde ses touches ; il revient au-dessus d’elle avec les réglages ou Audio et sous-titres.

Le pointeur a trois vitesses, trois tailles et deux formes, flèche ou rond. Le passage par Lecture/Pause maintenue se coupe dans la même page. Un appui court de Lecture/Pause agit quand la touche remonte, pour qu’un appui maintenu ne fasse que changer de mode.

Depuis la 0.9.5, le pointeur sélectionne le catalogue, la colonne, la barre, le dock, les fiches et les saisons, les Réglages, « Favoris, listes et dock », les messages, les réglages pendant la lecture et Audio et sous-titres. Dans la colonne des Réglages, la page suit le pointeur, comme elle suit les flèches. Une page des Réglages plus longue que l’écran défile sous le pointeur : poussé contre son bas ou son haut, il s’y arrête et la page avance du reste du geste. Au bout de la page, il continue vers la barre ; Retour y mène plus vite. Ailleurs, une liste défile comme en 0.9.4 : la ligne que le pointeur atteint au bord prend la sélection, et la liste la montre. Le studio d’apparence couvre l’écran avec son propre pointeur : le curseur se pose où il s’arrête, un clic choisit, un glissement ne déplace que le pointeur, et les flèches déplacent le curseur, que le pointeur suit. Le formulaire d’une source garde la télécommande classique : le pointeur s’y efface. Un clic sur ce qui n’est pas une commande ne fait rien.

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
| Chaînes TV | Droite, vers Regarder, Favoris ou le son | Garder l’aperçu de la chaîne |
| Chaînes TV | Valider | Regarder la chaîne en plein écran |
| Catalogue | Appui long | Ouvrir les favoris et listes |

Sur Apple TV comme sur le Mac, **Réglages → Graphismes** règle l’affichage comme dans un jeu. En tête, l’appareil détecté et le préréglage conseillé pour lui. Quatre tuiles :
- **Automatique** suit l’appareil : Fluide pour une Apple TV HD, Équilibré pour la première Apple TV 4K et un Mac Intel, Qualité pour les autres. C’est le réglage d’une nouvelle installation. À la mise à jour depuis la 0.9.3, il ne s’applique que si rien n’avait été coupé à la main : un verre, des mouvements, des fonds ou un aperçu coupés restent tels quels ;
- **Fluide** coupe le verre, les mouvements, les fonds et l’aperçu automatique ;
- **Équilibré** garde le verre, les fonds et les aperçus, sans les mouvements ni le reflet du panneau ;
- **Qualité** garde tout.

Chaque réglage reste modifiable plus bas : Liquid Glass, Mouvements de la sélection (Apple TV), **Repère du panneau actif** (Aucun, Liseré, ou Liseré et reflet), Afficher les fonds, puis l’aperçu des chaînes et son délai. En changer un quitte Automatique. Quand ils ne suivent plus aucun préréglage, la page l’écrit (« Personnalisé… »).

Sur Apple TV, le verre et les mouvements sont actifs au départ sur tous les modèles. **Liquid Glass** : les panneaux en verre, comme sur le Mac. tvOS réserve son propre verre à l’Apple TV 4K de 2ᵉ génération et aux suivantes ; sur l’Apple TV HD et sur la première Apple TV 4K, les panneaux sont dessinés avec le flou du système, sous une teinte légère et un liseré clair, et ce qui est derrière une fiche est assombri au lieu d’être flouté. Coupé, les panneaux sont des surfaces sombres. **Mouvements de la sélection** : ce qui est sélectionné grandit, et les icônes du dock glissent ; coupés, la sélection s’affiche d’un coup. L’inclinaison qui suit le pouce posé sur la télécommande n’existe que sur l’Apple TV 4K de 2ᵉ génération et les suivantes : sur une Apple TV plus ancienne elle s’affichait par à-coups. Le modèle est lu sur l’appareil. Depuis la 0.9.10, le calcul de l’application est mesuré sur une Apple TV 4K de 1re génération ; le dessin des couches reste à mesurer sur l’appareil.

Le délai de l’aperçu des chaînes se règle sur 1, 3, 5 ou 10 secondes : une seconde par défaut partout, Apple TV comprise. Les trois secondes que la 0.9.3 enregistrait sur Apple TV deviennent une seconde ; un autre délai choisi reste.

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

Sur Mac et sur Apple TV, **Réglages** pose deux panneaux de verre sur l’image, qui continue de jouer derrière : Interface, Graphismes, Vidéo, Réseau, Audio et sous-titres, Bibliothèque et Diagnostic. Tant qu’ils sont ouverts, les commandes attendent dessous et rien ne les masque. La croix, **Échap**, **Menu** ou un clic à côté les referment, et la sélection revient sur la touche Réglages. Sur iPhone et iPad, ils restent une feuille.

Un réglage est enregistré dès qu’il est choisi : il n’y a pas de bouton Enregistrer à ne pas manquer. Ceux que le moteur lit à l’ouverture d’un flux — moteur, décodage, cache, délais — s’appliquent au flux suivant ; pendant une lecture, une ligne le dit et propose **Relancer le flux**.

Sur Apple TV comme au clavier du Mac, parcourir la liste des pages affiche chacune aussitôt, **Droite** entre dans la page et **Gauche** revient sur la page en cours. Les choix sont des touches du bureau, lisibles et jamais coupées, avec leur nom au-dessus.

## Ce qui reste à faire pour le clavier du Mac

Le curseur du volume, dans Réglages › Audio et sous-titres, se règle au pointeur ; **Sourdine** est au clavier. Le formulaire d’une source garde les champs du système, hors des flèches. Aucune touche réelle n’a encore parcouru les Réglages : le banc joue les touches par le traitement du clavier.

## Installer

L’archive contient les sources et l’installateur Mac, pas un binaire Apple précompilé.

1. Sur Mac, quitter l’ancienne app et arrêter le lancement depuis Xcode.
2. Décompresser, puis ouvrir **Installer Flux IPTV.command**. L’installateur compile sur ce Mac et vérifie le démarrage ; cette vérification ne remplace pas un essai de lecture.
3. Vérifier **FLUX 0.9.10 · build 51** en bas de la colonne de Réglages.

Prérequis de déploiement : macOS 14, iOS 17 ou tvOS 17. Installer Xcode complet pour compiler ; le verre natif demande la version 26 des systèmes, les versions antérieures reçoivent un matériau translucide. Sur iPhone/iPad ou Apple TV, ouvrir `FluxIPTV.xcodeproj`, choisir **FluxIPTViOS** ou **FluxIPTVTV**, puis renseigner l’équipe de signature pour un appareil physique.

Le Mac garde AVPlayer natif ; le bouton VLC externe reste disponible pour les formats incompatibles. Les identifiants d’application et les préférences existantes sont conservés. Lire `LISEZ-MOI INSTALLATION.txt` pour les détails de signature et de Trousseau.

## Ouvrir le projet Apple TV

Ouvrir **`FluxIPTV-AppleTV.xcodeproj`**, ou lancer **`Ouvrir Flux IPTV Apple TV.command`**. Le projet dédié contient uniquement la cible et le schéma **FluxIPTVTV**. Choisir ensuite une destination Apple TV et exécuter avec ⌘R. Le schéma lance par défaut la configuration Release optimisée, sans débogueur.

« Mismatched platform » avec le schéma **FluxIPTV / My Mac** signifie que la destination ne correspond pas au schéma actif. Les détails sont dans [LISEZ-MOI APPLE TV.txt](<LISEZ-MOI APPLE TV.txt>) et la [documentation Apple](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

## Validation

Le périmètre vérifié pour cette version est dans [docs/VALIDATION-0.9.10.md](docs/VALIDATION-0.9.10.md), avec les mesures et l’audit des ressources dans [docs/OPTIMISATION.md](docs/OPTIMISATION.md) ; il s’ajoute à ceux de la 0.9.9 dans [docs/VALIDATION-0.9.9.md](docs/VALIDATION-0.9.9.md), de la 0.9.8 dans [docs/VALIDATION-0.9.8.md](docs/VALIDATION-0.9.8.md), de la 0.9.7 dans [docs/VALIDATION-0.9.7.md](docs/VALIDATION-0.9.7.md), de la 0.9.6 dans [docs/VALIDATION-0.9.6.md](docs/VALIDATION-0.9.6.md), de la 0.9.5 dans [docs/VALIDATION-0.9.5.md](docs/VALIDATION-0.9.5.md), de la 0.9.4 dans [docs/VALIDATION-0.9.4.md](docs/VALIDATION-0.9.4.md), de la 0.9.3 dans [docs/VALIDATION-0.9.3.md](docs/VALIDATION-0.9.3.md), de la 0.9.2 dans [docs/VALIDATION-0.9.2.md](docs/VALIDATION-0.9.2.md), de la 0.9.1 dans [docs/VALIDATION-0.9.1.md](docs/VALIDATION-0.9.1.md) et de la 0.9.0 dans [docs/VALIDATION-0.9.0.md](docs/VALIDATION-0.9.0.md), avec ce qui ne l’a pas été. Les tests unitaires du cœur ne démontrent ni la compilation des frameworks Apple, ni la fluidité réelle, ni la lecture des flux du fournisseur. Les résultats des versions précédentes ne valident pas la nouvelle interface du Mac.

## Publication sur l’App Store

Ce que demandent la revue d’Apple et App Store Connect, ce que la 0.9.4 a corrigé et ce qui reste à faire au moment de publier est dans [docs/APP-STORE.md](docs/APP-STORE.md) : manifeste de confidentialité, déclaration du chiffrement, accès au réseau local expliqué, licences dans Réglages › Diagnostic, et la variante App Store (`FLUX_APP_STORE=1 scripts/generate-xcodeproj.py`), qui n’a plus rien à écarter depuis que la 0.9.10 a retiré YouTubeKit de l’application. Le brouillon de la politique de confidentialité est dans [docs/CONFIDENTIALITE.md](docs/CONFIDENTIALITE.md).

## GitHub Actions et pack complet

Le dépôt complet est [M4D135/FluxIPTV](https://github.com/M4D135/FluxIPTV). Le workflow [Swift / Apple platforms](https://github.com/M4D135/FluxIPTV/actions/workflows/ci.yml) se lance à chaque push sur `main`, sur les branches `work/three-rooms-*`, lors des pull requests ou à la demande.

Actions exécute les tests du cœur, vérifie les deux projets générés, puis compile séparément macOS, iOS Simulator, tvOS Simulator et tvOS ARM64 pour appareil. Un job indépendant prépare le pack complet des sources du commit exécuté, avec son empreinte SHA-256. Voir [docs/CI.md](docs/CI.md).

### Vérifications locales

```bash
swift test
bash scripts/check-state-declarations.sh
bash scripts/test-live-preview.sh
bash scripts/test-tvos-catalog-ui.sh
bash scripts/test-keychain-interaction.sh
bash scripts/check-keychain-platform.sh tvOS
bash scripts/check-keychain-platform.sh iOS
bash scripts/test-catalog-ui.sh
bash scripts/build-platforms.sh macOS
bash scripts/build-platforms.sh iOS
bash scripts/build-platforms.sh tvOS
bash scripts/build-platforms.sh tvOS-device
```

`scripts/test-catalog-ui.sh` ouvre de vraies fenêtres et prend le premier plan. Pour regarder l’interface sans quitter son travail, `FLUX_CATALOG_UI_BACKGROUND=1` garde les fenêtres hors écran et n’exécute que les captures ; `FLUX_CATALOG_UI_GALLERY=1` ajoute les thèmes et les emplacements du dock, l’accueil avec le pointeur sur Films puis sur Séries et le filtre par langue ; `FLUX_CATALOG_UI_SIZE=1728x1050` choisit la taille de la fenêtre. Vingt-cinq scénarios envoient à l’écran les touches d’une télécommande et vérifient où la sélection arrive ; celui du préréglage Fluide vérifie aussi ce que la touche a enregistré.

Les versions précédentes sont conservées dans [docs/HISTORIQUE.md](docs/HISTORIQUE.md). Leurs anciennes commandes et résultats de tests ne décrivent pas la version actuelle.
