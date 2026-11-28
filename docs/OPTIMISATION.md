# Optimisation — FLUX IPTV 0.9.10

David a demandé, le 28 novembre 2026 :
- « trouve des amélioration en pagaille, des centaines si possible, et surtout des grosse amélioration sur la fluidité et rendre l'app la plus legere possible pour tous les apple tv, mac , faut vraiment focus à fond sur l'optimisation de la consomation ressource et fluidité de lapp » ;
- « tu feras tes test en simulateur xcode » ;
- puis, l’Apple TV HD de la chambre n’étant pas disponible : « ne mesusre pas sur l'appletv chambre qui n'est pas dispo, mesusre sur l'appletv salon ».

La 0.9.10 ne change rien à ce que l’on voit. Elle dépense moins : moins de calcul à chaque appui de la télécommande, moins pendant la lecture, moins de mémoire partout. Les gains ont été mesurés avant d’être gardés, au simulateur Apple TV et sur le Mac, puis sur l’Apple TV 4K du salon.

Les candidats viennent de deux sources :
- des mesures, de l’échantillonnage de l’application pendant les parcours, et de la lecture du code ;
- un audit des sources de la 0.9.8 fait par le Spark, fichier par fichier. Chaque constat a été relu sur le code de la 0.9.10, puis appliqué, écarté ou classé (voir [L’audit du Spark](#laudit-du-spark)).

## Ce qui a été mesuré

### Au simulateur Apple TV

Conditions :
- simulateur Apple TV 4K (4e génération), en 1080p, sous tvOS 27.2 ;
- application compilée comme pour le banc (configuration Debug), sur un Mac Apple Silicon ;
- chaque parcours est joué trois fois par XCTest ; le tableau donne la moyenne ;
- le temps de calcul et les instructions sont ceux du processus de l’application. Le dessin des couches se fait hors de ce processus et n’y est pas compté ;
- « Écran redessiné » compte, sur les trois passes, les évaluations du corps de l’écran entier (`FluxScreen`).

| Parcours | Calcul 0.9.9 | Calcul 0.9.10 | Écart | Instructions | Mémoire de pointe | Écran redessiné |
|---|---|---|---|---|---|---|
| Un film en lecture, 10 s | 0,381 s | 0,183 s | **−52 %** | −72 % | 43,3 → 36,1 Mo (−17 %) | 69 → 0 |
| 20 appuis vers le bas puis 20 vers le haut, 24 665 chaînes | 2,070 s | 1,423 s | **−31 %** | −40 % | 117,6 → 89,1 Mo (−24 %) | 160 → 0 |
| 10 rangées vers le bas puis 10 vers le haut, 58 093 films | 0,906 s | 0,791 s | **−13 %** | +4,5 % | 191,3 → 135,6 Mo (−29 %) | 64 → 0 |

Dans la grille des films, l’écran n’est plus redessiné, mais chaque rangée qui entre dans la liste construit ses cinq pochettes : 310 pochettes sur les trois passes, contre 110 en 0.9.9. Le calcul total baisse quand même. Une variante qui suit le déplacement une image plus tard ne construit que 50 pochettes, mais redessine l’écran à chaque appui (70 fois) ; elle coûte plus cher (voir [Le recentrage de la liste](#le-recentrage-de-la-liste)).

La 0.9.9 de la grille variait d’une passe à l’autre (±6,8 %). La grille a donc été rejouée, la 0.9.10 puis la 0.9.9, l’une après l’autre : 0,977 → 0,803 s (**−18 %**), 19 % de cycles en moins, 179,7 → 134,8 Mo de mémoire de pointe (−25 %). Le gain se retrouve.

### Sur l’Apple TV 4K du salon

Conditions :
- l’Apple TV « Séjour », une Apple TV 4K de 1re génération, sous tvOS 26.6.1. Elle dormait, et tvOS refuse alors de lancer une application ; avec l’accord de David, un appui sur Menu du banc l’a réveillée avant chaque série de mesures ;
- le banc compilé pour l’appareil en Release, avec ses conditions de test (`DEBUG`, `FLUX_CATALOG_UI_TESTING`) : en Debug, le fil principal de l’appareil déborde dès le lancement ;
- les six parcours du simulateur, trois passes chacun ; la 0.9.9 est celle de `a96d322`.

| Parcours | Calcul 0.9.9 | Calcul 0.9.10 | Écart | Instructions | Mémoire de pointe | Écran redessiné |
|---|---|---|---|---|---|---|
| Un film en lecture, 10 s | 0,312 s | 0,105 s | **−66 %** | −76 % | 24,5 → 23,8 Mo (−3 %) | 68 → 0 |
| L’accueil au repos, 10 s | 0,051 s | 0,050 s | −2 % | +0,4 % | 26,0 → 26,2 Mo | 0 → 0 |
| La télévision au repos, 24 665 chaînes, 10 s | plante | 0,039 s | | | 66,9 Mo | 0 |
| Le pointeur sur la télévision, 10 s | plante | 0,041 s | | | 67,3 Mo | 0 |
| 20 appuis vers le bas puis 20 vers le haut, 24 665 chaînes | plante | 3,433 s | | | 68,8 Mo | 0 |
| 10 rangées vers le bas puis 10 vers le haut, 58 093 films | plante | 2,083 s | | | 92,6 Mo | 0 |

Un film en lecture occupe 1 % du processeur au lieu de 3 %. L’accueil au repos ne change pas. Descendre puis remonter la liste de 24 665 chaînes coûte 3,4 s de calcul en 10,5 s, deux fois et demie le simulateur ; la grille de 58 093 films, 2,1 s en 5 s.

Les quatre autres parcours de la 0.9.9 plantent en 3 s, à l’ouverture de leur écran : la pile du fil principal déborde (`EXC_BAD_ACCESS` dans sa page de garde, en construisant la bande du haut du catalogue des chaînes, `deskTopBand`). Celle du simulateur, qui tourne sur le Mac, est bien plus grande : rien ne s’y voyait. Ce n’est pas la compilation : la 0.9.9 compilée en module entier déborde encore sur la télévision et sur la liste, et la 0.9.10 compilée fichier par fichier y passe. C’est le code de la 0.9.10 qui construit ces écrans avec moins de pile. Les conditions de test du banc ajoutent des vues que l’application livrée n’a pas ; la 0.9.8, installée sur cette Apple TV, y ouvre la télévision, mais sa marge n’est mesurée nulle part (voir [Ce qui reste à faire](#ce-qui-reste-à-faire)).

### En Release

Les mesures ci-dessus sont faites en Debug, comme les bancs. Les trois parcours qui bougent ont été rejoués en Release, la configuration que le schéma de l’Apple TV installe, sur la 0.9.10 : compilée fichier par fichier comme jusqu’ici, puis en module entier (voir [La compilation](#la-compilation)).

| Parcours (temps de calcul) | Debug | Release, fichier par fichier | Release, module entier |
|---|---|---|---|
| Un film en lecture, 10 s | 0,183 s | 0,192 s | 0,191 s |
| 20 appuis vers le bas puis 20 vers le haut, 24 665 chaînes | 1,423 s | 1,503 s | 1,547 s |
| 10 rangées vers le bas puis 10 vers le haut, 58 093 films | 0,791 s | 0,773 s | 0,796 s |

Les instructions, très stables d’une passe à l’autre dans la liste et la grille (±0,7 % au plus), y baissent de 1 à 2 % en Release : 6 846, 6 761 et 6 733 millions pour la liste, 5 572, 5 474 et 5 482 pour la grille. Celles du film montent : 215, 241 et 233 millions. Le travail d’un appui se fait presque tout entier dans SwiftUI et UIKit, qu’Apple compile une fois pour toutes. Ce que la 0.9.10 gagne vient de ce qu’elle leur demande moins, et se retrouve en Release.

### Au repos

Au repos, l’application ne fait presque rien, et le calcul ne départage pas les deux versions. Échantillonnée pendant l’accueil au repos, elle est inactive 98 % du temps dans les deux, avec le même travail sur le fil principal : 124 échantillons actifs sur 7 520 en 0.9.9, 127 sur 7 565 en 0.9.10. Rien n’y est redessiné, ni dans l’une ni dans l’autre.

D’une exécution du banc à l’autre, un même code y change davantage qu’entre les versions : l’accueil de la 0.9.9 a dépensé 107 millions d’instructions en 10 s à la première exécution, 155 à la seconde ; celui de la 0.9.10, 136 puis 108. Les trois parcours au repos ont donc été rejoués, la 0.9.10 puis la 0.9.9, l’une après l’autre :

| Parcours au repos, 10 s | Calcul, 1re exécution | Calcul, 2e exécution | Mémoire de pointe |
|---|---|---|---|
| L’accueil | 0,105 → 0,120 s | 0,120 → 0,094 s | 38,9 → 38,1 Mo (−2 %) |
| La télévision, 24 665 chaînes | 0,085 → 0,077 s | 0,077 → 0,074 s | 119,6 → 90,0 Mo (−25 %) |
| Le pointeur sur la télévision | 0,077 → 0,086 s | 0,083 → 0,071 s | 116,3 → 89,4 Mo (−23 %) |

La première exécution donnait à l’accueil 14 % de calcul en plus, la seconde 22 % en moins : au repos, l’écart est du bruit. La mémoire, elle, baisse d’un quart sur la télévision et le pointeur à chaque exécution ; c’est celle de l’index et des titres gardés.

### Sur le Mac, pour le cœur commun

Compilation optimisée (`-O`), sur le Mac, avec des catalogues fabriqués de la taille de ceux de David (92 000 entrées M3U, 92 000 titres Xtream). Chaque temps est le meilleur de trois exécutions, sur les sources finales des deux versions ; les deux versions rendent les mêmes titres (même empreinte).

| Mesure | 0.9.9 | 0.9.10 |
|---|---|---|
| Lecture d’une liste M3U de 92 000 entrées | 2 611 ms | 182 ms |
| Décodage des séries Xtream (20 000) | 291 ms | 204 ms |
| Décodage des films (60 000) et des chaînes (12 000) Xtream | 261 et 43 ms | 273 et 46 ms |
| Index du catalogue, source Xtream | 236 ms | 126 ms |
| Index du catalogue, source M3U | 459 ms | 112 ms |
| Une recherche dans tout le catalogue | 72 ms | 1 ms |
| Mémoire de l’index | 115,6 Mo | 7,5 Mo |
| Mémoire des titres Xtream gardés | 117,2 Mo | 78,1 Mo |
| Mémoire des titres M3U gardés | 144,3 Mo | 83,1 Mo |

Le décodage des films et des chaînes ne gagne rien : le gain du chargement vient des séries, des adresses gardées comme texte et des sections lues côte à côte.

Le chargement complet d’un catalogue Xtream de 92 000 titres, par `URLSession`, les réponses du serveur servies en mémoire :

| Mesure | 0.9.9 | 0.9.10 |
|---|---|---|
| Durée | 860 ms | 512 ms (−40 %) |
| Mémoire de pointe pendant le chargement | +197 Mo | +188 Mo (−4 %) |
| Mémoire gardée ensuite | +113 Mo | +63 Mo (−44 %) |

Une Apple TV HD est environ dix fois plus lente que ce Mac : la lecture de cette liste M3U y passerait d’environ 26 s à moins de 2 s (estimation : rien n’est mesuré sur l’appareil).

## Ce qui a changé

### La télécommande

- **Les déplacements discrets.** Un appui qui mène d’un titre à un autre de la page affichée ne redessine plus l’écran entier. La liste montre le focus elle-même ; seules les vues qui montrent la sélection (aperçu, fiche à côté de la liste) se redessinent. En 0.9.9, la descente d’une longue liste redessinait tout l’écran à chaque rangée : deux cinquièmes du travail d’un appui.
- **Le recentrage tout de suite.** La liste se recentre sur le titre dans le même tour que le déplacement.
- `browseItemID`, le titre sur lequel la télécommande se pose, n’est plus publié : aucune vue ne le dessine, et chaque appui redessinait toutes les vues de la bibliothèque.
- La colonne de gauche se reconnaît à son préfixe (`isDeskSidebarID`), sans reconstruire la liste de ses lignes à chaque appui.
- **Le dock ne trie plus l’historique à chaque appui.** Tant que le dock est affiché, chaque appui calculait son plan entier. Pour proposer la reprise, ce plan triait tout l’historique, jusqu’à 1 000 titres, afin de garder les douze derniers. Ces douze sont désormais gardés en une lecture (`sortedPrefix`). Sur le Mac, pour un historique de 1 000 titres dont 30 à 80 % à reprendre, cela coûte 11 à 21 µs par appui au lieu de 122 à 472 ; pour 100 titres, 2 µs au lieu de 9. Ce gain demande la compilation en module entier : fichier par fichier, la lecture unique coûtait encore 69 à 94 µs (voir [La compilation](#la-compilation)). Les déplacements ne calculent plus que l’ordre des icônes (`dockEntryIDs`), sans les signes des dossiers et des listes, qui lisent chaque liste entière.

### La lecture

- La position, le temps écoulé et la durée vivent à part (`PlaybackProgress`). Seul le bandeau du temps se redessine, 2,5 fois par seconde. En 0.9.9, tout l’écran l’était.
- La position du curseur que l’on déplace vit dans le bandeau (`PlayerChrome`), plus dans l’écran.
- Les pistes audio et sous-titres sont relues à chaque tour pendant les huit premières secondes, puis toutes les deux secondes. Un choix de l’utilisateur les relit aussitôt.
- La roue d’ouverture d’un flux est tournée par Core Animation. Avant, l’application la redessinait trente fois par seconde, au moment où la chaîne s’ouvrait.
- Un changement de chaîne rapide annule l’attente du précédent.

### La bibliothèque et le cœur

- **La lecture des listes M3U se fait sur les octets.** L’ancienne lecture compilait une expression à chaque ligne, mettait chaque ligne en capitales, découpait toute la liste d’un coup et construisait une locale pour chaque mot comparé. Elle reste dans les tests (`M3UParserReferenceTests`), qui comparent les deux lectures.
- **L’index du catalogue est refait.** Les titres sont rangés par places dans des tableaux, sans dictionnaire par catégorie. Les textes sont repliés une fois pour la recherche, qui se fait sur les octets (`ByteSearch`).
- Les adresses d’un titre sont gardées comme texte. Une URL pèse environ 400 octets en mémoire, son texte environ 100, et un catalogue en garde une ou deux par titre : 74 Mo d’URL pour 92 000 entrées.
- Le tableau des titres Xtream réserve sa capacité une fois : la concaténation en gardait 17 Mo inutiles.
- Les textes Xtream deviennent des chaînes natives, le nom d’une saison est construit une fois pour ses épisodes et le préfixe des identifiants une fois par rayon.
- Les octets reçus d’une liste M3U sont libérés dès qu’ils sont lus, avant la construction des titres : 26 Mo pour 92 000 entrées.
- La session réseau d’une liste est fermée après chaque chargement. Une session restait ouverte, avec ses connexions, à chaque rechargement.
- Les comptes de la recherche (TV, films, séries) se font hors du fil principal, sans rassembler les titres trouvés.
- Les saisons des 24 dernières séries ouvertes restent en mémoire, plus toutes celles d’une soirée.

### Les vues

- Les réglages « verre riche », « animations » et « images » sont lus une fois par l’écran et transmis aux vues. Chaque pochette et chaque panneau les lisait dans les préférences : deux lecteurs par pochette, plusieurs centaines sur un grand catalogue.
- Les pochettes d’une liste posée dans le dock, et les titres de son éventail, sont choisis en une seule lecture de la liste : seuls ceux que l’on montre sont triés par nom (`sortedPrefix`). Le tri de toute la liste coûtait, sur le Mac, 1,3 ms pour 200 titres et 9 ms pour 2 000, à chaque déplacement dans le dock ; il en coûte 0,1 et 0,4 ms. Sur une Apple TV HD, environ dix fois plus lente, le tri de 200 titres prendrait presque une image entière (estimation : rien n’est mesuré sur l’appareil).
- Les choix des fonds d’écran sont décodés une fois par texte gardé (`FluxBackdropChoices.reading`). Chaque fond monté et l’accueil les relisaient en JSON à chaque évaluation : 14 µs le décodage sur le Mac, jusqu’à sept fois par appui sur l’accueil, quand la sélection passe d’un écran à l’autre.
- La description complète d’un titre découpe son synopsis en pages une fois (`SynopsisPages.reading`). Elle le redécoupait cinq fois à chaque évaluation, et une fois de plus par appui : six découpages par page tournée. Sur le Mac, en compilation optimisée, un découpage coûte 33 µs pour 300 caractères, 138 µs pour 1 500 et 286 µs pour 3 000. Relues, les pages coûtent de 0,6 à 5 µs.
- Les genres d’une fiche ne paraissent qu’une fois : deux pastilles du même nom avaient la même identité.
- Les ombres des lignes, des icônes du dock, du cadre de la zone et des boutons posés sur l’image sont de rayon nul quand elles sont invisibles.
- Le code mort de l’ancien aperçu du vidéoclub (`currentClubItem`) est retiré.

### Le poids

- **Les fonds de l’Apple TV sont à sa taille.** L’Apple TV décode les images de fond à 1920 points au plus, même en 4K. Elle les reçoit désormais en 1920 × 1080, fabriquées par `scripts/make-tv-backdrops.swift` comme ImageIO les décode, en JPEG de qualité 0,9 : 5,9 Mo au lieu de 14,5 pour les seize. Décodées comme l’Apple TV les décode, les deux versions diffèrent de 42,7 dB de PSNR en moyenne, 39,2 au pire ; l’écart est dans la couleur, aux bords nets. Le Mac, l’iPhone et l’iPad gardent le 3840 × 2160. `swift test` vérifie que l’Apple TV a les mêmes images, en 1920 × 1080, et le générateur des projets s’arrête si les deux dossiers diffèrent.
- **Le lecteur des bandes-annonces et YouTubeKit sont retirés.** Depuis le build 33, les fiches montrent le boîtier du titre et aucune vue ne s’en servait. Partent avec eux : `CaseMediaPreview`, `YouTubeTrailerPlayer`, `NativeYouTubeTrailerResolver`, YouTubeKit (2 146 lignes), leurs deux bancs (`test-youtube-session.sh`, `test-native-youtube.sh`), leurs deux étapes de CI et la licence de YouTubeKit dans les Réglages. La variante App Store n’a plus rien à écarter.
- Deux vues mortes (`CatalogueWallpaper`, `SeriesEpisodesSheet`) sont retirées, avec deux clés de préférences que plus rien ne lisait.
- **L’exécutable est livré sans ses symboles.** Release le dépouille comme le fait une archive (`DEPLOYMENT_POSTPROCESSING`). L’Apple TV installée depuis Xcode recevait un exécutable de 25,9 Mo, dont 19 Mo de noms de fonctions que seul un débogueur lit ; elle en reçoit un de 6,5 Mo. Le dSYM, à côté de l’application, garde ces noms : il porte le même UUID que l’exécutable, et `atos` y retrouve une fonction à son adresse.

L’application de l’Apple TV, compilée en Release pour l’appareil, sans signature, telle que Xcode l’installe :

| | 0.9.9 | 0.9.10 |
|---|---|---|
| Exécutable | 25,87 Mo | 6,54 Mo |
| Exécutable sans ses symboles, comme dans une archive | 6,78 Mo | 6,54 Mo (−3,5 %) |
| YouTubeKit | 0,41 Mo | — |
| Fonds | 14,5 Mo | 5,9 Mo |
| VLCKit | 43,2 Mo | 43,2 Mo |
| Application entière | 89,0 Mo | 61,1 Mo (−31 %) |

VLCKit, le lecteur des flux que AVPlayer ne lit pas, fait désormais plus des deux tiers de l’application.

### La compilation

- **Release compile le module entier** (`SWIFT_COMPILATION_MODE = wholemodule`). Jusqu’ici, Xcode compilait l’application fichier par fichier, même en Release. Une fonction générique d’un fichier n’y était pas spécialisée là où un autre fichier l’appelle. Sur le Mac, garder les douze titres à reprendre d’un historique de 1 000 coûte 11 à 21 µs en module entier, 69 à 94 µs fichier par fichier. Les bancs du cœur, eux, étaient compilés en module entier (`-wmo`) : l’application compile désormais ce qu’ils ont mesuré.
- À l’échelle d’un parcours, rien ne change : les trois parcours rejoués en Release dépensent autant compilés d’une façon ou de l’autre (voir [En Release](#en-release)). La compilation pour l’Apple TV dure autant (127 s contre 128), et le code grossit de 44 Ko. Debug reste incrémental et garde ses symboles.

### Le banc

- Le délai du banc Mac sur les machines hébergées passe à 420 s (600 s avec la galerie) : la 0.9.9 l’a dépassé sur `main` à 240 s, la même sur sa branche non.
- Le parcours qui compte ce qu’un appui reconstruit tolère deux évaluations de l’écran pour trois appuis, au lieu de six : une par appui serait de nouveau la 0.9.9.
- Un nouveau parcours vérifie que le temps d’un film avance à l’écran (`testTheTimeOfAFilmGoesOnWhileItPlays`) : seul son bandeau le suit désormais, et aucun parcours ne regardait le temps.

## Les expériences

### Ce que SwiftUI donne à Core Animation

Une petite application, sur le Mac, décrit les couches que SwiftUI crée pour un flou, une rotation et une ombre. Elle s’ouvre hors de l’écran.
- **Flou de rayon nul :** aucun filtre. SwiftUI ne le pose pas.
- **Rotation en perspective d’angle nul :** aucune transformation. SwiftUI ne la pose pas.
- **Ombre de couleur transparente :** l’ombre est posée quand même, avec une opacité de 1, une couleur d’alpha nul et le rayon donné, sans chemin. Avec un rayon nul, elle reste posée.

Core Animation saute-t-il une ombre de couleur transparente ? Cela ne se mesure pas au simulateur, qui dessine avec le GPU du Mac. Les ombres invisibles ont reçu un rayon nul, ce qui ne coûte rien. La question reste ouverte pour une Apple TV HD : seul Instruments sur l’appareil la tranchera.

### Le recentrage de la liste

Après un déplacement discret, la liste peut se recentrer de trois façons :
- **A, tout de suite**, dans le tour du déplacement ;
- **B, une image plus tard**, comme les autres déplacements ;
- **C, au tour suivant**, hors du rendu.

Les trois placent la grille comme la 0.9.9 : le titre sélectionné se pose à la même hauteur (523 points) dès 50 ms après chaque appui. Cinq appuis rapides mènent les trois cinq rangées plus bas ; la 0.9.9 finissait alors sur le dock.

| Variante | Liste de 24 665 chaînes | Grille de 58 093 films | Écran redessiné (films) | Pochettes construites |
|---|---|---|---|---|
| 0.9.9 | 2,070 s | 0,906 s | 64 | 110 |
| A, tout de suite | 1,426 s | 0,792 s | 0 | 310 |
| B, une image plus tard | 1,827 s | 0,930 s | 70 | 50 |
| C, au tour suivant | 1,354 s | 0,777 s | 0 | 310 |

A et C se valent, à l’écart de mesure près. La 0.9.10 garde A, la plus simple, celle dont la tenue de la grille a été vérifiée.

## L’audit du Spark

Le Spark a lu les sources de la 0.9.8 par morceaux d’environ 150 lignes. Il en a tiré des constats : un fichier, une ligne, une force (FORT, MOYEN, FAIBLE), une catégorie, une description, un remède.

Chaque constat a reçu un statut :
- **Appliqué** dans la 0.9.10 ;
- **Déjà fait** avant la 0.9.10 ;
- **Écarté** : le constat est faux, ou le remède coûterait plus qu’il ne rapporte ;
- **Négligeable** : hors des chemins chauds, une fois par action ;
- **À mesurer sur appareil** : ce que le simulateur ne départage pas, le coût GPU de Core Animation surtout, et quelques mises en page de SwiftUI que seul Instruments montre sur une Apple TV ;
- **Plus tard** : vrai, à faire dans un prochain lot.

Les décisions ont été vérifiées une à une sur le code.

Le 28 novembre à 5 h 25, le Spark avait lu 25 fichiers sur 76, environ les trois quarts des lignes : le cœur commun, la bibliothèque, le lecteur, le dock, la vue principale et le studio d’apparence. 618 de ses constats ont été triés, chacun vérifié sur le code :

| Statut | Constats |
|---|---|
| Appliqué | 58 |
| Déjà fait | 1 |
| Écarté | 132 |
| Négligeable | 398 |
| À mesurer sur appareil | 5 |
| Plus tard | 24 |

Le redémarrage du Mac, le 28 novembre vers 6 h 20, a effacé le dossier de travail qui gardait les réponses du Spark : leurs descriptions sont perdues. Restent, [plus bas](#la-liste-des-constats), chaque décision, sa raison et les lignes qu’elle concerne. Le Spark relit désormais les sources de la 0.9.10, dans un dossier qui survit à un redémarrage, pour le prochain lot.

### Ce qui reste à faire

- **La liste de zapping.** Chaque appui y redessine l’écran : `zapFocusID` est un état de l’écran. Même remède que pour les titres ; un banc est à écrire.
- **La colonne des catégories.** Les déplacements y redessinent encore l’écran.
- **La liste de la colonne.** Chaque appui dans la grille la refait et la parcourt deux fois. Sur le Mac, compilation optimisée : 3 µs pour 50 catégories, 20 µs pour 300, 63 µs pour 1 000. Dans le banc de la liste, elle pèse 7 ms sur 20 s. La reconnaître sans la refaire, comme le fait déjà `isDeskSidebarID`, l’éviterait.
- **Le code des anciennes jaquettes.** Sept types du cœur (`CaseBackMediaLayout`, `CaseInspectorNavigation`, `CasePadRotation`, `CasePreviewFacing`, `CasePreviewProjection`, `ProceduralCase`, `CaseRenderQuality`), environ 480 lignes, ne sont plus appelés par l’application. Seuls leurs tests s’en servent : les retirer ensemble.
- **Le code des anciens décors 3D.** La pièce de chaque thème (`VideoClubTheme.room`), la scène d’une présentation (`ClubInterfaceProfile.stage`) et la géométrie de `ProceduralCinema` (`tube`, `scene`, `project`) ne sont plus dessinées : environ 230 lignes du cœur, que seuls leurs tests appellent. L’application n’en garde que les palettes, qui donnent la couleur des repères de chaque écran et son fond uni, et le réglage qui montre ou cache les fonds (`ProceduralCinema.Style`).
- **Le plan du dock.** La 0.9.10 n’y trie plus l’historique, et les déplacements n’en calculent plus que l’ordre des icônes. Le dessin du dock le refait encore à chaque évaluation de l’écran, en hachant chaque liste qui y est posée. Sur le Mac, en module entier, cela coûte 0,8 µs pour 50 titres, 8 µs pour 500 et 35 µs pour 2 000, et le signe d’un dossier qui en tient deux autres 7 µs (24 dossiers, 500 raccourcis). Une révision des listes l’éviterait.
- **Les cibles du pointeur.** Chaque commande visible relit son cadre à chaque image d’un défilement, même quand le pointeur est coupé : deux lectures des vues défilantes et une écriture dans la table des cibles. Ne l’enregistrer qu’en mode pointeur demande un banc qui passe d’un mode à l’autre.
- **Un garde-fou de la pile.** Le banc de la 0.9.9 débordait la pile d’une Apple TV 4K sans que le simulateur le montre. Relever, pendant les parcours au simulateur, la profondeur de pile du fil principal, et arrêter le banc au-delà d’une marge, protégerait l’application livrée.
- **Le GPU d’une Apple TV.** Les mesures sur l’Apple TV du salon comptent le calcul de l’application, pas le dessin des couches par le serveur de rendu : les ombres, les flous et les matériaux se mesurent avec Instruments, sur l’appareil. L’Apple TV HD de la chambre n’a pas été mesurée.
- **La libération d’un catalogue entier**, au changement de source, se fait sur le fil principal.
- **Les deux groupes de pistes** d’un flux pourraient se charger ensemble : un gain de délai, pas de ressources.
- **L’audit des sources de la 0.9.10.** Le Spark les relit, en 212 morceaux ; ses constats seront triés au prochain lot.

## La liste des constats

Les lignes sont celles de la 0.9.8, que le Spark a lue. Ses descriptions sont perdues (voir [L’audit du Spark](#laudit-du-spark)) : chaque décision est donnée avec sa raison, puis les fichiers et les lignes qu’elle concerne.

### Appliqué (58)

- Index refait (0.9.10) : places en tableaux, sans dictionnaire par groupe ; 231 → 127 ms (Xtream), 462 → 110 ms (M3U), 115,6 → 7,5 Mo. — `CatalogIndex` 78, 127, 139, 192, 194
- Textes repliés une fois à la construction de l'index, recherche sur les octets : 72 → 1 ms. — `CatalogIndex` 199
- Lecture sur les octets (0.9.10) : 2 582 → 177 ms pour 92 000 entrées, l'ancienne lecture gardée pour les tests de comparaison. — `M3UParser` 14, 16, 20, 34, 97
- Mots, chemins et catégories classés une fois par liste (M3UKinds, M3URoute). — `M3UParser` 65, 73, 76
- Un nom par saison, partagé par ses épisodes. — `XtreamClient` 194
- Capacité réservée une fois : la concaténation gardait 17 Mo de capacité inutile pour 92 000 titres. — `XtreamClient` 40
- Préfixe des identifiants construit une fois par section. — `XtreamClient` 145
- Comptés sans rassembler les titres, hors du fil principal (0.9.10). — `IPTVLibrary` 489, 493
- browseItemID n'est plus publié (0.9.10) : un appui ne redessine plus toutes les vues de la bibliothèque. — `ContentView` 1312 ; `IPTVLibrary` 84
- Saisons des 24 dernières séries gardées (0.9.10). — `IPTVLibrary` 126
- La session est invalidée après chaque chargement (0.9.10). — `IPTVLibrary` 671
- Les octets reçus sont libérés une fois lus, avant la construction des titres : 26 Mo pour 92 000 entrées (0.9.10). — `IPTVLibrary` 680
- Position et temps écoulé dans PlaybackProgress (0.9.10) : seul ce qui les montre est redessiné, plus tout l'écran 2,5 fois par seconde. — `ContentView` 88, 2568 ; `PlaybackController` 43, 62 ; `PlayerSurface` 51, 59, 69
- Pistes relues toutes les deux secondes après les huit premières (0.9.10). — `PlaybackController` 136, 143, 165, 463
- La position du curseur vit dans PlayerChrome (0.9.10) : l'écran n'est plus redessiné pendant qu'on la déplace. — `ContentView` 209, 2668
- Ombre de rayon nul hors focus (0.9.10) ; reste une ombre transparente que seul un appareil dira gratuite. — `LiveTVComponents` 213 ; `PlayerChrome` 35
- Le réglage des images est lu une fois en haut de l'arbre (environnement), plus un observateur par image (0.9.10). — `ArtworkView` 83
- Déplacements discrets (0.9.10) : un appui d'un titre à l'autre ne redessine plus l'écran ; le reste change avec le filtre ou la page. — `ContentView` 87
- La tâche d'un changement de chaîne remplacée est annulée (0.9.10) ; elle ne faisait déjà rien en se réveillant. — `PlaybackController` 348
- isDeskSidebarID (0.9.10) : un préfixe, plus un tableau reconstruit à chaque appui. — `ContentView` 714
- Supprimé (0.9.10) : c'était du code mort. — `ContentView` 519
- Position et temps écoulé dans PlaybackProgress (0.9.10) : la barre du lecteur n'est plus reconstruite à chaque tic de la position, seul le bandeau du temps l'est. — `ContentView` 3157, 3180, 3183
- Seuls les premiers titres d'une liste sont triés par nom (sortedPrefix, 0.9.10) : sur le Mac, 1,3 → 0,1 ms pour 200 titres, 9 → 0,4 ms pour 2 000, à chaque déplacement dans le dock. — `ContentView` 4964
- isDeskSidebarID (0.9.10) reconnaît la colonne à son préfixe : la liste n'est plus refaite que dans la recherche et les favoris, qui en ont quelques dizaines. — `ContentView` 5945
- Les choix des fonds sont décodés une fois par texte gardé (FluxBackdropChoices.reading, 0.9.10). Un décodage coûtait 14 µs sur le Mac, jusqu'à sept fois par appui sur l'accueil. — `ContentView` 6065 ; `ProceduralStage` 239
- Vrai, mesuré : la description complète redécoupait le synopsis à chaque lecture de ses pages, cinq fois par évaluation et une de plus par appui, soit six fois par page tournée. Un découpage coûte 33 µs pour 300 caractères, 138 µs pour 1 500 et 286 µs pour 3 000 sur le Mac (compilation optimisée). Depuis la 0.9.10, les pages sont découpées une fois par synopsis (SynopsisPages.reading) ; relues, elles coûtent 0,6 à 5 µs. — `MediaDetailPresentation` 465, 474
- Vrai : deux genres du même nom donnaient à deux pastilles la même identité. Depuis la 0.9.10, chaque genre ne paraît qu'une fois. — `MediaDetailPresentation` 1001, 1378
- La position, le temps et la durée vivent à part depuis la 0.9.10 (PlaybackProgress) : pendant la lecture, la fiche ne suit plus que l'historique, écrit toutes les 20 s. La bibliothèque ne publie que quand le catalogue change, ce qu'aucun appui dans la fiche ne fait. — `MediaDetailPresentation` 48
- L'historique est un dictionnaire, lu en temps constant ; depuis la 0.9.10, la position vit à part (PlaybackProgress) et l'historique ne change que toutes les 20 s pendant la lecture. — `MediaDetailPresentation` 398
- Appliqué : la position, le temps et la durée vivent à part (PlaybackProgress). Le contrôleur ne publie plus qu'aux changements d'état, ses pistes seulement quand elles changent, et l'historique toutes les 20 s pendant la lecture. — `PlaybackSettingsView` 75

### Déjà fait (1)

- Borné à 96 fiches depuis la 0.9.9. — `IPTVLibrary` 12

### Écarté (132)

- Aucun ensemble ni dictionnaire d'IPTVItem dans le code ; l'égalité complète sert aux clés des pochettes, qui doivent voir tout changement. — `IPTVModels` 23
- Un rafraîchissement demande exprès la liste du moment ; un cache de protocole écrirait des dizaines de Mo du catalogue sur le disque. — `IPTVLibrary` 675 ; `XtreamClient` 115
- Les pochettes montrent l'année et la fiche le reste ; des détails paresseux garderaient le dictionnaire JSON de chaque titre en mémoire. — `XtreamClient` 154
- Les panneaux changent le type d'un même champ (nombre, texte, null, tableau vide) ; JSONSerialization et des chaînes natives : 286 → 200 ms. — `XtreamClient` 121
- Change quand un titre est choisi, pas à chaque déplacement. — `IPTVLibrary` 15
- La frappe doit redessiner le champ et la liste ; le filtre prend 1 ms depuis la 0.9.10. — `ContentView` 1895 ; `IPTVLibrary` 16, 50
- Change avec le filtre, la page ou la source : la liste doit être redessinée. — `IPTVLibrary` 87, 360, 377
- La tranche d'une catégorie est prête dans l'index, et index(of:) passe par une table puis une dichotomie. — `ContentView` 431, 1919, 1974, 2046, 2135, 2149, 2251, 2336 ; `IPTVLibrary` 388
- Les tableaux Swift se partagent sans copie tant qu'on ne les modifie pas. — `IPTVLibrary` 405
- UserDefaults écrit sur le disque hors du fil principal. — `IPTVLibrary` 473
- Le survol change à l'entrée et à la sortie d'un contrôle, pas à chaque mouvement du pointeur. — `ContentView` 203, 244, 306, 3263 ; `PlayerChrome` 272
- Évaluer un body ne redessine pas le flou : le matériau est une couche que Core Animation garde. — `PlayerChrome` 167
- Expérience des couches (0.9.10) : à angle nul, SwiftUI ne donne aucune transformation à Core Animation. — `ContentView` 2406 ; `GlassStyle` 165
- DeskFlow ne sert qu'aux réglages et aux fiches, quelques boutons. — `GlassStyle` 588, 630, 636, 644
- Ce GeometryReader n'existe que sur iPhone et iPad. — `LiveTVComponents` 117
- FluxScrollHandles n'est pas observé : l'écriture ne redessine rien. — `ContentView` 597
- onChange se déclenche une fois par changement de valeur, pas à chaque image d'une animation. — `ContentView` 987
- Choix de confidentialité : les images restent en mémoire vive, jamais sur le disque. — `ArtworkView` 33
- 32 Mo, borné par le coût ; plus petit, les affiches se rechargeraient du réseau en remontant une liste. — `ArtworkView` 17
- Sans elle, le décodage reprendrait sur le fil principal, où la tâche de la vue a commencé. — `ArtworkView` 59
- currentTime lit l'horloge locale du lecteur, sans aller-retour réseau. — `PlaybackController` 438
- Une table de l'index ou un ensemble (favoris), pas un parcours. — `ContentView` 638, 722, 850, 1208, 2075, 2150, 2371, 2946, 2947
- C'est le report voulu : l'aperçu attend que la télécommande se pose (délai réglable). — `ContentView` 1215
- Copier un IPTVItem copie des références de chaînes partagées ; l'égalité complète est voulue. — `ContentView` 2370
- FluxScrollHandles est une classe que rien n'observe : l'écriture ne redessine rien. — `ContentView` 283, 2868
- index(of:) et item(id:) passent par une table (dictionnaire), en temps constant, déjà en 0.9.8 : il n'y a pas de parcours. — `ContentView` 3098, 3580, 3906, 4067, 5407, 5858, 5871, 7081, 7137
- FluxPointerTargets est une classe que rien n'observe : l'écriture ne redessine rien. — `ContentView` 4530
- SwiftUI rassemble les changements d'un même tour en une seule mise à jour. — `ContentView` 3946
- Le corps n'est pas réévalué à chaque image d'une animation : SwiftUI interpole hors du corps. — `ContentView` 4424
- C'est le rôle d'equatable() : une comparaison bon marché évite de reconstruire la carte. — `ContentView` 4472
- Des valeurs, sans allocation sur le tas. — `ContentView` 3159
- La tâche précédente est annulée avant d'en créer une autre. — `ContentView` 3382
- FluxProbe ne compte rien hors du banc : la fonction y est vide et mise en ligne. — `ContentView` 4660
- FluxScrollHandles est une classe que rien n'observe : y ranger le lecteur ne redessine rien. — `ContentView` 6354
- slice(group:) lit une table, et le compte d'une part est gardé (CatalogItems.count) : rien n'est filtré. — `ContentView` 6359, 6375, 6740, 7179
- L'identité par rang est celle des identifiants de la télécommande (search-recent-<rang>) ; la liste ne garde que quelques recherches. — `ContentView` 6560
- La taille de l'accueil place la barre et le nom : elle n'est écrite qu'à l'apparition et quand la fenêtre change, sans boucle. — `ContentView` 6190, 6239
- Code que l'application n'exécutait pas : aucune vue ne s'en servait depuis le build 33 (les fiches montrent le boîtier du titre). La 0.9.10 le retire, avec le lecteur YouTube et YouTubeKit. — `CaseMediaPreview` 13, 18, 102, 104, 127, 156, 200, 213, 236, 252, 317, 335, 345, 365, 372, 484, 518, 561, 569 ; `YouTubeTrailerPlayer` 21, 68, 191, 199, 301
- Cet ensemble n'est lu par aucun corps de vue : le modifier ne redessine pas l'écran. Le banc le montre : en descendant une liste de 24 665 chaînes, l'écran est évalué 0 fois en 0.9.10 (160 en 0.9.9). — `ContentView` 7051, 7052
- L'écran observe déjà la bibliothèque : ces lectures n'ajoutent aucune dépendance. — `ContentView` 6959
- LiveTVPreviewObserver est justement la sous-vue qui isole l'observation de l'aperçu : seul son contenu se redessine. — `ContentView` 7166
- Voulu : sous un pointeur, survoler un épisode le choisit, comme dans la fiche du bureau. — `MediaDetailPresentation` 419, 1326
- Nécessaire et borné : le système refuse le focus à une commande qui apparaît encore, et une demande refusée se lit comme accordée. La boucle s'arrête dès que la commande dit avoir la télécommande, en général au premier tour, et ne dépasse pas 12 essais. — `MediaDetailPresentation` 566
- Les images passent par un cache en mémoire partagé, par adresse et en vignettes (ArtworkView) : une nouvelle mise en page relit l'image, sans la retélécharger. — `MediaDetailPresentation` 726
- Faux : en revenant, la vue relit d'abord le cache (NSCache, dans son init puis dans sa tâche) et ne décode que si l'image en est sortie. Lâcher l'image d'un écran qui disparaît est voulu : le cache borne seul la mémoire. — `ProceduralStage` 131
- Faux : active fait partie de l'identité de la tâche (Turn). Quand il change, la tâche est annulée et relancée, et la nouvelle s'arrête avant la boucle. — `ProceduralStage` 200
- Faux : systemUptime lit l'horloge sans appel système. Mesuré sur le Mac : 29 ns. — `TVPointer` 57, 511, 558, 785
- Voulu : le focus suit le pointeur dans la même image. Il n'est demandé que quand la commande sous le pointeur change. — `TVPointer` 817
- Code des parcours du banc (FLUX_CATALOG_UI_TESTING) : il n'est pas compilé dans l'application. — `TVPointer` 1056, 1100, 1164, 1176, 1186
- Voulu : une page neuve repart en haut avec son focus, une fois par changement de page. — `PlaybackSettingsView` 281, 363
- La vue suit tout le contrôleur (ObservableObject) : une sous-vue qui l'observerait serait invalidée de même, et lire un champ de plus n'y change rien. Le contrôleur ne publie qu'aux changements d'état depuis la 0.9.10, et l'historique toutes les 20 s pendant la lecture. — `PlaybackSettingsView` 548, 564
- La fermeture lit draft au moment de l'appui, pas à sa création : aucune copie à l'évaluation. — `PlaybackSettingsView` 506
- La feuille lit la bibliothèque (@EnvironmentObject) pour déverrouiller et enregistrer la source : elle en a besoin. La bibliothèque ne publie qu'au chargement ou au changement d'une source, pas pendant la saisie. — `PlaybackSettingsView` 647
- onAppear ne revient qu'à l'apparition du champ, une fois par renommage ou par dossier créé : une invalidation ne réinsère pas la vue. Mac seulement. — `PlaybackSettingsView` 864, 931
- FluxGraphics.device est un static let : l'appareil n'est reconnu qu'une fois ; recommended n'est qu'un switch. — `PlaybackSettingsView` 1089

### Négligeable (398)

- Quelques lignes d'en-tête, une fois par touche du clavier du Mac ; l'Apple TV suit le focus du système. — `CatalogIndex` 45, 63
- Une fois par filtre ou par historique (au plus 1 000 titres), pas par appui. — `CatalogIndex` 41, 70, 187
- Les chaînes de l'ensemble partagent leur mémoire avec les identifiants gardés ; la table est libérée à la fin de la lecture. — `M3UParser` 12
- Un appel par entrée, compris dans les 177 ms mesurées. — `M3UParser` 42
- Une fois par lecture lancée ou par requête (six par catalogue), pas par titre. — `XtreamClient` 101, 221, 225
- Une requête annulée revient aussitôt et le contrôle final écarte le résultat. — `XtreamClient` 43
- Une saison à la fois, à l'ouverture d'une série. — `XtreamClient` 167, 183, 199
- Au changement de source ou de rayon, pas pendant la navigation. — `IPTVLibrary` 112, 350, 609
- Quelques Ko lus au lancement. — `IPTVLibrary` 132
- Filtre de quelques listes ou valeur déjà calculée par l'index. — `IPTVLibrary` 231, 234, 254
- Une tâche par appui, quelques microsecondes ; l'état n'est écrit qu'au repos (350 ms). — `IPTVLibrary` 294
- Un geste sur le dock, quand les favoris montrent une section ; lu par updateResults, pas par un body. — `IPTVLibrary` 852, 861
- Une fois par action, hors des chemins chauds. — `ContentView` 3457, 3570, 3897, 3899, 5277, 5373 ; `IPTVLibrary` 151, 371, 397, 404, 633, 767, 849, 872 ; `SourcePersistence` 123
- Une écriture toutes les 20 s pendant la lecture, ou à l'ouverture d'un flux. — `ContentView` 1203, 2364 ; `PlaybackController` 47, 213
- Une fois par échec ou fin de flux. — `LiveTVPreviewController` 120, 127
- Une dizaine de cases, pendant un survol ou un glisser du dock sur Mac. — `FluxDock` 333, 338, 540, 546, 656, 836
- Une fermeture par évaluation de l'écran, devenue rare avec les déplacements discrets. — `ContentView` 550, 1704, 1706
- Une page de titres, au changement de page. — `ContentView` 653
- Dix vérifications légères au plus, à l'entrée d'une colonne. — `ContentView` 793
- Une fois par lecture lancée, ou par fiche ouverte sur Mac. — `ContentView` 1219, 1256, 2415, 2449
- Une affiche pèse d'ordinaire moins de 500 Ko ; 8 Mo est la borne, pas le cas courant. — `ArtworkView` 56
- Un seul fond d'écran, une chaîne par appel. — `ArtworkView` 41, 121
- Les deux éditeurs sont des propriétés stockées : rien ne se réabonne. — `GlassStyle` 137, 172
- L'aperçu publie ses phases, quelques fois par chaîne ; un seul aperçu à l'écran. — `LiveTVComponents` 229, 252 ; `LiveTVPreviewController` 100, 107, 176
- Une fois par ligne construite. — `LiveTVComponents` 85, 378
- Toutes les 20 s pendant la lecture, quelques Ko. — `PlaybackController` 56
- 2,5 réveils par seconde, de quelques microsecondes ; la position n'est publiée qu'à PlaybackProgress. — `PlaybackController` 485, 497
- Au lancement, ou dans les réglages et les menus du Mac. — `PlaybackController` 31, 48, 76, 601, 607
- Quelques chaînes par évaluation du bandeau, devenue rare depuis que la position vit à part. — `PlayerChrome` 57, 76, 169, 174, 255, 298
- Un réveil par minute. — `PlayerChrome` 141
- À la création de la surface, et à ses rares mises à jour. — `PlayerSurface` 27, 47
- Un état qui change avec une action (une tâche, un jeton, une saison chargée), pas à chaque appui. — `ContentView` 111, 148, 152, 160, 179, 299
- Une valeur légère calculée quand l'écran est évalué, ce que les déplacements discrets rendent rare. — `ContentView` 139, 292, 435, 468, 494, 548, 1046, 1152, 1177, 1257, 1446, 1650, 1657, 1684, 1806, 1862, 2123, 2181, 2311, 2388, 2659, 4373, 4377, 4517, 4521, 4577, 4578, 4582, 4644, 4672, 4881, 4921, 5007, 5016, 5624, 5625, 5644, 6855, 6857, 6863, 6981
- Le temps d'attendre une ligne ou un contrôle, borné à quelques tours. — `ContentView` 604, 779, 1036, 2731, 2883, 2966, 3420
- Au bord d'un écran, au changement de taille ou à l'apparition, pas à chaque appui. — `ContentView` 818, 919, 979, 992, 1034, 1297
- Au changement de filtre ou de catégorie, pas à chaque appui. — `ContentView` 1172, 1174, 1771, 1928
- Pointeur du Mac ou commandes du lecteur : un minuteur réarmé, sans redessiner. — `ContentView` 2648, 2661, 2804
- Une fois par pochette construite, ou par changement de l'aperçu. — `ContentView` 2165, 2206, 2294, 2410, 2416, 2418
- Une dizaine de cases : le dock n'est évalué que lorsqu'on s'y déplace ou qu'on le survole. — `DockSkins` 219, 291, 356, 443, 476, 506, 601, 681, 763 ; `FluxDock` 194, 233, 253, 300, 306, 356, 357, 401, 443, 465, 507, 598, 608, 635, 646, 671, 782, 822, 852, 883, 892, 918, 932, 940, 993, 1024, 1042, 1052, 1145, 1263, 1329, 1437, 1481
- Une soixantaine de combinaisons au plus : la table est bornée par ce qu'elle garde. — `DockSkins` 288
- Ces réglages ne changent que dans les Réglages. — `FluxDock` 297
- Une dizaine de boutons, calculés quand l'écran est évalué : la lecture ne le redessine plus (0.9.10). — `ContentView` 3033, 3104, 3151, 3257, 3296
- La recherche vide saute le filtre ; avec un filtre, quelques centaines de catégories comparées dans une feuille ouverte. — `ContentView` 3445
- Des panneaux ouverts à la demande ; la bibliothèque ne publie qu'avec une action. — `ContentView` 3489
- Une tâche endormie pèse quelques centaines d'octets : cinquante chaînes en 15 s, quelques dizaines de Ko. — `ContentView` 3856
- Les épisodes d'une série, quelques centaines au plus, à chaque appui dans le lecteur. — `ContentView` 3936, 3939
- Quelques rangées de contrôles, une fois par appui. — `ContentView` 4021, 4105, 4144
- Le dock garde quelques dizaines de raccourcis et de dossiers : les parcourir coûte quelques microsecondes. — `ContentView` 4997, 4998, 5049, 5052, 5053, 5057, 5063, 5069
- Une fois par appui sur Lecture/Pause ou dans le dock, sur cinq zones et quelques rangées. — `ContentView` 5411, 5414, 5417
- La page affichée (quelques dizaines de titres), lue seulement au bout d'une rangée. — `ContentView` 5873
- Quelques raccourcis, listes ou sections du dock, quand l'accueil ou la colonne des favoris est évalué. — `ContentView` 5769, 6024, 6146, 6520, 6528, 6529, 6733
- Une fois par action (entrée dans les favoris, activation d'une ligne, retour du dock), sur trois types et quelques rangées. — `ContentView` 5734, 5799, 5946
- Appelé quand la taille de l'écran change, pas à chaque appui. — `ContentView` 5961
- Six écrans au plus et une transition légère, quand l'écran est évalué. — `ContentView` 6047, 6071, 6092
- Environ 200 pays, quand la colonne des pays est évaluée ; les drapeaux des seules lignes visibles (pile paresseuse). — `ContentView` 6405, 6415, 6443
- Trois types et quelques recherches, quand le focus change dans la colonne de la recherche. — `ContentView` 6593
- Un nom de liste, à chaque frappe pendant qu'on le tape. — `ContentView` 6649
- Une fois par évaluation de l'écran, que les déplacements discrets rendent rare. — `ContentView` 6747, 6750
- Quelques dizaines de lignes visibles : index(of:) passe par une table, isFavorite par un ensemble, selectedByKeyboard compare un identifiant (faux sur l'Apple TV). La clé est construite quand la liste est évaluée, ce que les déplacements discrets rendent rare. — `ContentView` 7008
- Pour la seule chaîne choisie, à chaque déplacement : le début du nom de sa catégorie, une recherche dans un ensemble, une comparaison (fausse sur l'Apple TV). — `ContentView` 7138, 7149, 7158
- Les saisons et les épisodes d'une série, quelques dizaines : chaque parcours coûte quelques microsecondes, et seules les lignes visibles des épisodes sont construites (pile paresseuse). — `MediaDetailPresentation` 103, 106, 127, 144, 188, 373, 549, 1179, 1269, 1273, 1274
- La fiche n'existe que tant qu'un titre est tenu et part après son animation de fermeture : cette couche n'est invisible que pendant l'ouverture et la fermeture, dans une fenêtre étroite du Mac. — `MediaDetailPresentation` 163
- Un GeometryReader lit une taille ; son contenu est évalué avec la fiche, pas une seconde fois, et rien ne change de taille pendant qu'on s'y déplace. — `MediaDetailPresentation` 154, 241, 480, 666, 707
- Sous un pointeur seulement : une tâche qui cède la main une fois puis fait défiler la rangée, à chaque épisode survolé. — `MediaDetailPresentation` 360, 405
- Quelques champs courts, nettoyés quand la fiche est évaluée. Mesuré sur le Mac : l'année 0,6 à 2,3 µs (expression régulière comprise), la durée 0,1 à 0,8 µs, la note 1,1 µs, les genres 0,8 µs. — `MediaDetailPresentation` 113, 117, 959, 965, 976, 983
- Un identifiant court, une fois par déplacement. — `MediaDetailPresentation` 209, 212
- CasePackageFormat.resolve lit les quelques octets de l'année ; un modificateur inactif ne fait que rendre son contenu ; une forme est une valeur, sans allocation. — `MediaDetailPresentation` 663, 673, 860
- Sous un pointeur seulement, à chaque ligne survolée : la fiche est évaluée de nouveau, avec ses quelques lignes visibles. — `MediaDetailPresentation` 1205
- Sur le Mac seulement, une fois par appui : les saisons et les épisodes d'une saison, quelques dizaines d'identifiants. Pour 200 épisodes, quelques microsecondes. — `MediaDetailPresentation` 1426, 1428, 1430, 1435, 1461
- Une série a quelques saisons, une vingtaine au plus : leurs pochettes, leurs identifiants et leur format se construisent en quelques microsecondes, une fois par appui dans l'étagère, pour les seules pochettes visibles (grille paresseuse). — `SeriesSeasonShelf` 42, 62, 66, 68, 73
- Un GeometryReader lit une taille, qui ne change qu'avec la fenêtre : sur une Apple TV, jamais après l'apparition. La tâche du diaporama n'est relancée que si cette taille change. — `ProceduralStage` 108, 167, 177
- Seize images livrées et quelques images choisies : leurs identifiants, le filtre de la bibliothèque, une clé de cache et une lecture du cache coûtent moins d'une microseconde à chaque évaluation. — `ProceduralStage` 102, 116, 180, 242
- Mesuré sur le Mac, en compilation optimisée : trouver la cible sous le pointeur (filtre par couche, cadres, la plus proche) coûte 1,6 µs pour 60 cibles, 2,7 µs pour 150 et 7,2 µs pour 400, à chaque mouvement du pointeur. Les pages d'une couche sont quelques-unes. — `TVPointer` 204, 209, 226, 230
- Une à trois couches de pointeur : le dernier contrôleur se trouve en quelques comparaisons. — `TVPointer` 38, 195
- Le style du curseur compare une clé et s'arrête quand rien n'a changé ; les réglages sont appliqués quand la vue du pointeur est mise à jour, pas à chaque mouvement. — `TVPointer` 483, 650
- Une tâche annulée à l'appui suivant ; une fermeture réaffectée quand la vue est mise à jour. — `TVPointer` 120, 387
- Seulement pendant un mouvement du pointeur, 30 fois par seconde au plus, et quand aucune cible enregistrée n'est sous lui : sur les commandes du système, rares dans l'application. Au repos, rien ne l'appelle. — `TVPointer` 735, 737, 806
- Une fois par sélection déplacée, sur les cibles d'une couche : quelques microsecondes pour quelques centaines (voir la recherche de la cible sous le pointeur). — `TVPointer` 848
- Pendant un geste seulement : une tâche par image, de l'ordre d'une microseconde, et une lecture du focus 30 fois par seconde au plus. Au repos, rien. — `TVPointer` 865, 929, 985
- FluxPointerMotion est une valeur de deux champs : la construire ne coûte rien. — `TVPointer` 898
- Une vue de 1 × 1 point par pointeur, créée une fois ; elle n'est posée que pour les parcours du banc (élément « flux-pointer-state »). — `TVPointer` 1022
- La bulle qui dit le mode ne paraît qu'au changement de mode, une fois par geste ; UIImage(systemName:) garde ses symboles en cache. — `TVPointer` 1375, 1383
- Appelé quelques fois par appui, pour savoir dans quelle zone est le focus : six comparaisons de préfixe sur un tableau littéral, que le compilateur pose sur la pile. Pas à chaque image. — `DockShelf` 211
- Le badge d'une saison ou d'un épisode : une petite chaîne par icône du dock, une vingtaine au plus, à chaque dessin du dock. — `DockShelf` 65
- Construit une fois, quand un épisode est posé dans le dock. — `DockShelf` 60
- Seulement quand le dock a plus d'icônes que de place : quelques entrées retirées d'une vingtaine. — `DockShelf` 269, 282
- Les dossiers du dock sont faits un à un par l'utilisateur : quelques-uns, à quatre niveaux au plus. Ces parcours servent aux réglages, à la fenêtre des listes et aux actions sur un dossier, une fois par action. — `DockShelf` 403, 450, 467, 474, 519
- Quelques sections, filtrées à chaque disposition du dock : de l'ordre de la microseconde. — `DockShelf` 444, 446
- Les raccourcis d'un dossier sont posés un à un : quelques dizaines. Le dessin du dock les relit pour le signe de chaque dossier (voir « Le plan du dock » dans Ce qui reste à faire). — `DockShelf` 490
- Une fois par action de l'utilisateur sur le dock (poser un raccourci, retirer une source, nommer un dossier), sur quelques sections. — `DockShelf` 543, 544, 608, 659
- Les réglages ne sont ouverts que le temps de régler : la bibliothèque n'y change qu'au chargement d'une source, et les préférences qu'aux choix faits ailleurs, rares pendant ce temps. — `PlaybackSettingsView` 101, 107
- Une fois par évaluation des réglages, qui ne se redessinent qu'aux choix de l'utilisateur : une lecture du paquet, un tableau de quelques pages, une passe de mise en page. — `PlaybackSettingsView` 164, 190, 264
- Une fois à l'ouverture des réglages. — `PlaybackSettingsView` 102
- Mesuré sur le Mac, en module entier : trouver la dernière icône coûte 1,9 µs pour 20 icônes, 3,6 µs pour 40, une fois par appui ou par dessin du dossier ouvert ; l'ordre des icônes, 1,4 µs pour 20. — `DockShelf` 249, 257
- Mesuré sur le Mac, en module entier : la disposition d'un dock de 24 dossiers et 500 raccourcis coûte 4,3 µs. — `DockShelf` 638, 651
- Dans les réglages seulement, une fois par changement de page ou par mise en page des réglages : quelques fermetures et les cadres d'une page. — `PlaybackSettingsView` 308, 361, 377
- Tableaux de constantes, que le compilateur range en données statiques (vérifié à l'assembleur pour les préfixes du dock) ; Array(0...5) et les deux ou trois moteurs : quelques éléments, quand la page Vidéo ou Réseau est redessinée. — `PlaybackSettingsView` 495, 516
- Trois nombres pour la source active seulement, quand la page Sources est redessinée. — `PlaybackSettingsView` 599
- Un Binding par contrôle, créé quand la page est redessinée, aux choix de l'utilisateur. — `PlaybackSettingsView` 500, 539
- Une carte par source (quelques-unes), redessinées quand la bibliothèque change de source ou de chargement : quelques chaînes et une passe de mise en page. — `PlaybackSettingsView` 682, 705
- Page Dock des Réglages, redessinée aux choix faits sur elle : quelques paires d'un texte court découpées (sept écrans au plus), l'ordre de six icônes, quelques sections, dossiers et raccourcis filtrés, quelques chaînes. — `PlaybackSettingsView` 770, 772, 783, 785, 790, 791, 814, 816, 911, 912, 941, 995
- Le studio d'apparence, ouvert pour choisir un fond ou un thème : quelques listes de seize fonds, dix-huit thèmes et six écrans refaites quand il est redessiné, pas dans les écrans de tous les jours. — `AppearanceStudio` 108, 110, 136, 148, 160, 202, 206, 207
- Pages Graphismes, Télécommande et Interface des Réglages, redessinées aux choix faits sur elles : quelques options, couleurs, formes et chaînes. — `PlaybackSettingsView` 1090, 1152, 1176, 1179, 1185, 1212, 1213, 1214, 1218, 1355, 1368, 1379, 1398, 1434, 1441, 1459

### À mesurer sur appareil (5)

- Le flou se dessine sur le GPU : à mesurer avec Instruments sur une Apple TV. L'image est celle du boîtier, déjà en mémoire ; sans les effets complets, une Apple TV lente s'en passe. — `MediaDetailPresentation` 923
- À mesurer : ViewThatFits mesure ses variantes jusqu'à la première qui tient, à l'ouverture de la fiche. Qu'un appui entre les commandes, qui ne change ni le texte ni la place, les fasse mesurer de nouveau se voit avec Instruments (SwiftUI), sur une Apple TV. — `MediaDetailPresentation` 1076, 1103, 1368, 1390

### Plus tard (24)

- La libération d'un catalogue entier se fait sur le fil principal, au changement de source : à mesurer sur Apple TV HD. — `IPTVLibrary` 506
- Import d'un fichier M3U choisi par l'utilisateur (Mac, iPhone), lu une fois sur le fil principal. — `SourcePersistence` 171
- iPhone et iPad : la fiche reste dans l'arbre à opacité nulle. — `ContentView` 1429
- Les déplacements dans la colonne des catégories redessinent encore l'écran : à traiter comme les titres (déplacements discrets). — `ContentView` 2018
- Chaque appui dans la liste de zapping redessine l'écran (zapFocusID est un état de l'écran) : même remède que les titres, banc à écrire. — `ContentView` 2851
- Les deux groupes de pistes pourraient se charger ensemble, une fois par flux : un gain de délai, pas de ressources. — `PlaybackController` 243
- Même remède que pour zapFocusID : la liste de zapping redessine l'écran à chaque appui. — `ContentView` 2850
- Vrai : le plan du dock se recalcule à chaque évaluation de l'écran et plusieurs fois par appui dans le dock (l'historique trié, jusqu'à 1 000 entrées ; les listes et les dossiers hachés). Un cache par révision l'éviterait. — `ContentView` 4639, 4901, 4940, 4944, 5112, 5184, 5216, 5225, 5910, 6191
- Vrai, mesuré : la liste de la colonne est refaite et parcourue deux fois à chaque appui dans la grille. Sur le Mac, 3 µs pour 50 catégories, 20 µs pour 300, 63 µs pour 1 000 (environ dix fois plus sur une Apple TV HD, estimation) ; dans le banc de la liste, 7 ms sur un parcours de 20 s. La reconnaître sans la refaire, comme isDeskSidebarID, est pour un prochain lot. — `ContentView` 5832, 5843, 5882
- Vrai : chaque cible visible relit son cadre à chaque image d'un défilement, même quand le pointeur est coupé (deux lectures des vues défilantes, une écriture dans la table des cibles). Ne l'enregistrer qu'en mode pointeur demande un banc qui passe d'un mode à l'autre : prochain lot. — `TVPointer` 266, 268, 283, 359
