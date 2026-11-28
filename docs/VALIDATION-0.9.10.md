# Validation de FLUX IPTV 0.9.10 — build 51

La 0.9.10 allège l’application :
- un appui qui mène d’un titre à un autre de la page ne redessine plus l’écran entier ;
- pendant la lecture, seul le bandeau du temps se redessine ;
- le cœur commun lit les listes, construit l’index du catalogue et cherche avec beaucoup moins de calcul et de mémoire.

À l’écran, deux choses changent, sur l’Apple TV seulement :
- l’aperçu d’une chaîne continue quand la sélection quitte la liste ;
- une fiche apparaît et s’efface d’un seul fondu, son boîtier compris : il ne reste plus à l’écran après elle.

David l’a demandé le 28 novembre 2026 :
- « trouve des amélioration en pagaille, des centaines si possible, et surtout des grosse amélioration sur la fluidité et rendre l'app la plus legere possible pour tous les apple tv, mac , faut vraiment focus à fond sur l'optimisation de la consomation ressource et fluidité de lapp » ;
- « tu feras tes test en simulateur xcode » ;
- « on perd l'aperçu si on sort de la liste, c pas bon non plus », avec une photo de son téléviseur : la sélection est dans le dock, et l’aperçu attend ;
- « l'effet transition jaquette c pas bon sur appletv parce que c mal fait et quand on sort de la fiche film ou autre lanpochette rest collé une demi seconde, pas beau » et « fais le en simulateur, l'apple tv n'est pas dispo ».

Les mesures, la liste des changements et l’audit des sources sont dans [OPTIMISATION.md](OPTIMISATION.md). Cette page dit ce qui a été vérifié.

Pour le reste, les validations de la 0.9.9 ([VALIDATION-0.9.9.md](VALIDATION-0.9.9.md)) et des versions précédentes valent toujours, avec leurs limites.

Les vérifications ont été faites le 28 novembre 2026 :
- sur un Mac Apple Silicon, macOS 27.2.1, Xcode 27.2 ;
- au simulateur Apple TV 4K (4e génération), en 1080p, sous tvOS 27.2 ;
- sur l’Apple TV 4K (1re génération) du salon, sous tvOS 26.6.1, pour les mesures sur l’appareil ;
- sur l’état final des sources.

## Ce qui change pour la vérification

- **L’aperçu d’une chaîne.** Sur l’Apple TV, depuis la 0.8.8, il ne jouait que si la sélection était sur la chaîne, et depuis la 0.9.8 sur Regarder, Favoris ou le son. Il continue désormais quand la sélection va dans la colonne, la recherche ou le dock, comme sur le Mac. Il s’arrête quand on choisit une catégorie, une liste ou un pays, quand on tape une recherche, quand on change d’écran, et quand un panneau s’ouvre.
- **La fiche sur l’Apple TV.** Son boîtier devait s’envoler de la pochette choisie et y revenir. Sur l’Apple TV, les pochettes de la grille n’ont jamais eu ce vol : le focus les soulève déjà. À la fermeture, le boîtier restait donc sur place, entier, et tournait pendant que la fiche s’effaçait autour de lui, puis disparaissait d’un coup avec elle, au bout de 0,38 s. Désormais, sur l’Apple TV, la fiche entière, boîtier compris, apparaît en 0,22 s et s’efface en 0,18 s, sans vol ni rotation ; les fiches des saisons d’une série, qui gardaient leur vol, font de même. Le Mac garde son vol. La pochette reprend aussi la sélection dès le début du fondu, directement depuis la fiche, et la jaquette d’une série la reprend sans passer par la colonne quand on quitte ses saisons (voir [Ce que la vérification a trouvé](#ce-que-la-vérification-a-trouvé)).
- **Ce qui se redessine.** Un appui discret ne redessine plus l’écran : la liste montre le focus elle-même, et seules les vues qui montrent la sélection (aperçu, fiche à côté de la liste) le suivent. La liste se recentre dans le même tour. Les parcours de la télécommande vérifient toujours où se pose le focus, que l’aperçu suit la chaîne sur laquelle il se pose et que les pages d’un grand catalogue tournent sous la télécommande.
- **La lecture.** La position, le temps écoulé et la durée vivent à part (`PlaybackProgress`). Sur le Mac, l’iPhone et l’iPad, la position du curseur que l’on fait glisser vit dans le bandeau. Le banc Apple TV vérifie que le temps d’un film avance à l’écran et que les pistes audio restent proposées ; aucun banc ne fait glisser le curseur (voir [Non vérifié](#non-vérifié)).
- **Le poids.** Le lecteur des bandes-annonces (`CaseMediaPreview`, `YouTubeTrailerPlayer`, `NativeYouTubeTrailerResolver`) et YouTubeKit sont retirés : depuis le build 33, aucune vue ne s’en servait. Leurs deux bancs et leurs étapes de CI partent avec eux, ainsi que la licence de YouTubeKit dans les Réglages. L’Apple TV reçoit les fonds en 1920 × 1080, la taille à laquelle elle les décode (`BackdropsTV`). Les projets sont régénérés ; les vérifications de types et les bancs, qui compilent les applications, passent sur cet état.
- **La compilation.** Release compile désormais l’application en module entier et livre l’exécutable sans ses symboles ; Debug ne change pas. Les bancs et les vérifications de types compilent en Debug. La compilation Release pour l’Apple TV, et trois parcours mesurés en Release, passent sur cet état.
- **Le dock et la fiche.** Le dock garde les douze titres à reprendre en une lecture de l’historique, et les déplacements ne calculent plus que l’ordre de ses icônes. La description complète d’une fiche découpe son synopsis une fois. Les parcours du dock, de ses dossiers et de ses listes, et ceux des fiches, passent sur cet état.
- **Le cœur.** La lecture des listes M3U se fait sur les octets ; l’ancienne lecture reste dans les tests, qui comparent les deux sur les mêmes listes (`M3UParserReferenceTests`). La recherche se fait sur des textes repliés une fois (`ByteSearch`, `CatalogSearchTests`). Les adresses des titres sont gardées comme texte (`IPTVItemAddressTests`).

## Exécuté

| Vérification | Résultat |
|---|---|
| Vérification de types : Mac (production, et avec le banc du Mac), tvOS, tvOS du banc, parcours de la télécommande, variante App Store pour tvOS, et iPhone et iPad (simulateur) | Aucune erreur. |
| Tests du cœur (`swift test`) | 221 tests, aucun échec. |
| Mesures au simulateur Apple TV : six parcours, trois passes chacun, en 0.9.9 et en 0.9.10 ; les trois parcours au repos et la grille des films rejoués l’un après l’autre | Les chiffres sont dans [OPTIMISATION.md](OPTIMISATION.md#ce-qui-a-été-mesuré). Chaque parcours passe. |
| Bancs du cœur sur le Mac, en compilation optimisée : lecture M3U, décodage Xtream, index, recherche, chargement d’un catalogue Xtream | Les deux versions rendent les mêmes titres (même empreinte). Liste M3U de 92 000 entrées : 2 611 → 182 ms ; chargement d’un catalogue Xtream de 92 000 titres : 860 → 512 ms ; mémoire de l’index : 115,6 → 7,5 Mo ; recherche : 72 → 1 ms. Le détail est dans [OPTIMISATION.md](OPTIMISATION.md#sur-le-mac-pour-le-cœur-commun). |
| Mesures en Release au simulateur Apple TV : un film, la liste de chaînes et la grille de films, trois passes chacun, compilés fichier par fichier puis en module entier | Chaque parcours passe. Le calcul ne change qu’à quelques pour cent près d’une compilation à l’autre, et du Debug au Release (voir [OPTIMISATION.md](OPTIMISATION.md#en-release)). |
| Mesures sur l’Apple TV 4K (1re génération) du salon : six parcours, trois passes chacun, en 0.9.9 et en 0.9.10, compilés en Release pour l’appareil ; puis la télévision et la liste avec la 0.9.9 compilée en module entier et la 0.9.10 fichier par fichier | 0.9.10 : les six parcours passent ; un film en lecture, 0,312 → 0,105 s de calcul pour 10 s (−66 %). 0.9.9 : l’accueil et le film passent ; les quatre autres plantent à l’ouverture de leur écran, pile du fil principal débordée, quel que soit le mode de compilation. Les chiffres sont dans [OPTIMISATION.md](OPTIMISATION.md#sur-lapple-tv-4k-du-salon). |
| Compilation Release de l’Apple TV pour l’appareil, sans signature, par le projet livré, sans réglage ajouté | Réussie en 127 s, en module entier. Application de 61,1 Mo au lieu de 89,0 en 0.9.9, exécutable de 6,54 Mo ; le dSYM porte le même UUID que l’exécutable, et `atos` y retrouve une fonction à son adresse. |
| Fermeture d’une fiche de film, fiche d’une saison et retour des saisons d’une série au catalogue, filmés au simulateur Apple TV (`simctl io recordVideo`) pendant leurs parcours, puis lus image par image, avant et après les corrections | Fiche : le fondu dure environ 0,15 s à l’écran, boîtier compris, et rien ne reste après lui ; la pochette a déjà la sélection sous la fiche qui s’efface. Saisons : la jaquette s’allume 0,05 s après l’apparition de la grille. Le filtre de la colonne ne s’allume plus dans aucun des deux cas. Les cinq parcours filmés (fiches, zones, pointeur) passent. Filmés de nouveau pendant le banc complet de la version finale : mêmes temps. |
| Banc Apple TV complet (`scripts/test-tvos-catalog-ui.sh`), Apple TV 4K (4e génération) en 1080p sous tvOS 27.2 | 33 écrans capturés, le focus natif sur le contrôle attendu dans chacun, et les 32 parcours de la télécommande : aucun échec, en 24 min 31, dont 19 min 55 pour les parcours. Les six parcours de mesure, qui ne tournent qu’à la demande, y sont sautés. |
| Banc Mac avec la galerie (`FLUX_CATALOG_UI_BACKGROUND=1 FLUX_CATALOG_UI_GALLERY=1 scripts/test-catalog-ui.sh`) | 95 captures et 29 scénarios de touches, en 5 min 48. Comme en 0.9.9, ce mode laisse de côté les scénarios de la recherche qui demandent la fenêtre active. |

## Ce que la vérification a trouvé

- **Sur l’Apple TV 4K du salon, le banc de la 0.9.9 débordait la pile du fil principal** dès que la télévision, le pointeur, la liste des chaînes ou la grande grille se construisaient ; celui de la 0.9.10 passe. La 0.9.9 compilée en module entier déborde encore, la 0.9.10 compilée fichier par fichier passe : c’est le code de la 0.9.10 qui construit ces écrans avec moins de pile. Le simulateur, dont la pile est celle du Mac, ne le montrait pas.
- **L’Apple TV du salon dormait** : tvOS refuse alors de lancer une application (« System is asleep »). Avec l’accord de David, un appui sur Menu du banc l’a réveillée avant chaque série de mesures.
- **À la fermeture d’une fiche, la sélection traversait la colonne.** Filmée au simulateur, la fermeture montrait, après le fondu, le filtre de la colonne allumé en blanc pendant 0,05 s, puis sa première ligne, avant que la pochette ne reprenne la sélection, 0,2 s après le fondu. La grille restait bloquée sous la fiche jusqu’à ce que celle-ci disparaisse : le système posait alors la sélection sur le premier contrôle de l’écran. Désormais, la grille répond de nouveau dès le début du fondu, et la pochette prend la sélection à la fiche, qui ne la réclame plus.
- **En quittant les saisons d’une série, la sélection traversait aussi la colonne.** La même vidéo montrait le filtre allumé 0,05 s, puis plus rien pendant 0,1 s, et la jaquette 0,2 s après l’apparition de la grille. La page des saisons partait avec la sélection, et le système la posait de lui-même sur le premier contrôle de l’écran avant que l’application ne la ramène. L’écran lui désigne désormais, pendant ce retour seulement, le titre vers lequel revient la télécommande (`defaultFocus`) : la jaquette s’allume 0,05 s après l’apparition de la grille. Une chaîne quittée depuis son flux revient à la liste par le même chemin ; seul le retour des saisons a été filmé.
- **Désigner ce titre en tout temps déplaçait la sélection de départ.** Une première version désignait au système le titre que nomme la sélection, à chaque fois qu’il place lui-même la télécommande. Au lancement, cette sélection est l’icône TV du dock : l’écran d’une source en erreur s’ouvrait la télécommande sur le dock, et non sur le premier contrôle de la colonne. Le banc complet l’a vu (`testFailedSourceReconnectHighlightFollowsRemoteFocus`) ; le titre n’est plus désigné que pendant un retour, et le banc complet passe de nouveau, ce parcours compris.
- **Au repos, un écart qui n’en était pas un.** La première mesure donnait à l’accueil de la 0.9.10 14 % de calcul en plus ; la seconde, 22 % en moins. Le même code varie davantage d’une exécution à l’autre qu’entre les versions : seule la mémoire y départage les deux.
- **La grille de la 0.9.9 variait de ±6,8 % d’une passe à l’autre.** Rejouée l’une après l’autre, la 0.9.10 y garde son avance (−18 %).
- **Le dock triait tout l’historique à chaque appui**, tant qu’il était affiché, pour proposer la reprise : jusqu’à 1 000 titres pour en garder douze.
- **Les choix des fonds étaient décodés en JSON** à chaque évaluation de chaque fond, jusqu’à sept fois par appui sur l’accueil.
- **La description complète redécoupait son synopsis six fois par page tournée.**
- **L’Apple TV recevait des fonds en 3840 × 2160** qu’elle décode en 1920 × 1080 : 8,6 Mo de trop.
- **Le lecteur des bandes-annonces et YouTubeKit restaient dans l’application** sans qu’aucune vue s’en serve depuis le build 33, ainsi que deux vues et deux préférences mortes.
- **Deux genres du même nom** donnaient à deux pastilles d’une fiche la même identité.
- **Release compilait l’application fichier par fichier.** Une fonction générique d’un fichier n’y était pas spécialisée là où un autre fichier l’appelle : garder les douze titres à reprendre d’un historique de 1 000, 11 à 21 µs en module entier, en coûtait 69 à 94 fichier par fichier. Les bancs du cœur, eux, étaient compilés en module entier. La 0.9.10 compile ainsi l’application ; à l’échelle d’un parcours, rien ne change.
- **Debug et Release dépensent autant** dans les parcours mesurés, à quelques pour cent près : le travail d’un appui se fait dans SwiftUI et UIKit. Les mesures en Debug valent pour l’application installée.
- **L’Apple TV installée depuis Xcode recevait 19 Mo de symboles** dans un exécutable de 25,9 Mo : Release ne le dépouillait pas, seule une archive le faisait.
- **La CI de la 0.9.9 (`a96d322`)** : la branche est verte. Sur `main`, le Mac hébergé a dépassé l’échéance du rendu de ses captures, 240 secondes ; elle passe à 420 secondes, 600 avec la galerie.
- **Des constats faux de l’audit** : la lecture de l’horloge (`systemUptime`) n’est pas un appel système (29 ns) ; une image de fond revenue à l’écran est relue dans le cache, sans être décodée de nouveau. Les constats vérifiés et leur statut sont dans [OPTIMISATION.md](OPTIMISATION.md#la-liste-des-constats).

## Ce que les bancs vérifient de nouveau

- **L’aperçu hors de la liste.** Le parcours des zones (`testArrowsAloneReachEveryZoneOfTheScreen`) vérifie que l’aperçu garde sa chaîne dans la recherche, dans la colonne et dans le dock, en plus de Regarder et de Favoris.
- **Ce qu’un appui reconstruit.** Le banc Apple TV compte les évaluations du corps de l’écran (`FluxScreen`), de la bande des catégories, de la barre, des lignes de chaînes et des pochettes. Le long d’une rangée de pochettes et en descendant une liste de chaînes, l’écran n’est plus redessiné : 3 évaluations en 0.9.9, 0 en 0.9.10.
- **Le temps d’un film.** Un nouveau parcours (`testTheTimeOfAFilmGoesOnWhileItPlays`) lit le bandeau d’un film qui joue et vérifie que son temps avance : seul ce bandeau suit désormais la lecture, et aucun parcours ne regardait le temps.
- **Ce que l’application dépense.** Six parcours mesurent le temps de calcul, les instructions, les cycles et la mémoire de l’application, trois fois chacun : l’accueil, la télévision et le pointeur au repos, un film en lecture, une liste de 24 665 chaînes et une grille de 58 093 films parcourues à la télécommande (voir [OPTIMISATION.md](OPTIMISATION.md)).
- **Les tests du cœur :**
  - la lecture M3U sur les octets, comparée à l’ancienne sur plus d’une centaine de lignes piégées (neuf fins de ligne, attributs mal formés, accents combinants, espaces exotiques, adresses) et sur des listes fabriquées par un générateur fixe ;
  - la recherche repliée (accents, casse, pleine chasse, ß et œ, plusieurs alphabets), comparée à `localizedStandardContains` sur chaque titre ;
  - les adresses gardées comme texte, qui rendent les URL données ;
  - le tri des premiers titres d’une liste du dock, comparé au tri complet sur des listes fabriquées par un générateur fixe (égalités et accents compris) ;
  - les choix des fonds décodés une fois par texte, relus après d’autres textes ou les mêmes, comparés au décodage complet ;
  - les pages d’une description découpées une fois par synopsis, relues après d’autres textes, d’autres longueurs ou les mêmes, comparées au découpage complet, avec chaque mot gardé dans son ordre ;
  - les fonds de l’Apple TV : les mêmes images que ceux du Mac, en 1920 × 1080.

## Non vérifié

- **L’application livrée sur une Apple TV.** Les mesures sur l’Apple TV du salon passent par le banc et son catalogue de démonstration. L’application livrée n’y est pas installée, la 0.9.8 y reste : David l’installe depuis le dossier livré. Sa marge de pile n’est mesurée nulle part.
- **Un aperçu qui joue pendant qu’on parcourt l’écran.** Les chaînes du banc n’ont pas de flux : le parcours voit à quelle chaîne l’aperçu appartient, pas une image qui joue. Ce que coûte un aperçu qui joue pendant que la loupe du dock s’anime n’est mesuré ni au simulateur, ni sur une Apple TV.
- **Une flèche pendant la fermeture d’une fiche.** Le code garde le titre qu’atteint une flèche pressée pendant les 0,18 s du fondu ; aucun parcours n’appuie aussi vite.
- **Le dessin des couches.** Le simulateur dessine avec le GPU du Mac, et les mesures sur l’Apple TV du salon ne comptent que le processus de l’application : les ombres, les flous et les matériaux ne se mesurent qu’avec Instruments, sur une Apple TV. Les constats de l’audit sur le GPU restent « à mesurer sur appareil ».
- **Une Apple TV HD.** Celle de la chambre n’était pas disponible. Elle est environ dix fois plus lente que le Mac ; les gains relatifs devraient s’y retrouver, sans y avoir été mesurés.
- **Les fonds en 1920 × 1080 sur un téléviseur.** L’écart avec les fonds 4K décodés par l’Apple TV est mesuré (PSNR), et les captures du banc les montrent au simulateur ; personne ne les a regardés sur un téléviseur.
- **Le curseur de lecture du Mac, de l’iPhone et de l’iPad.** Sa position vit désormais dans le bandeau ; aucun banc ne le fait glisser. La vérification de types passe.
- **iPhone et iPad** : rien n’y change à l’écran. La vérification de types passe ; seule la CI les compile entièrement.
- **La CI de GitHub** : celle de la 0.9.10 part avec son envoi, et son résultat n’est pas dans cette page.

## Limites connues

- **Au repos, le banc ne départage pas les deux versions.** D’une exécution à l’autre, un même code y varie davantage qu’entre elles : l’accueil de la 0.9.9 a dépensé 107 puis 155 millions d’instructions en 10 s. Seule la mémoire y baisse nettement, d’un quart sur la télévision. Voir [OPTIMISATION.md](OPTIMISATION.md#au-repos).
- **La colonne des catégories et la liste de zapping** : leurs déplacements redessinent encore l’écran. Le même remède que pour les titres s’y appliquera dans un prochain lot.
