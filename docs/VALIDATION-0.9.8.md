# Validation de FLUX IPTV 0.9.8 — build 49

La 0.9.8 met la barre de l’accueil en bas, sur une seule rangée, à la grande taille de l’accueil. Le nom de ce qui est sélectionné reste à sa hauteur, et un dossier ouvert tient entre la barre et le haut de l’écran. Le dock peut se masquer sous les écrans. Sur l’accueil, une destination sélectionnée montre le fond de son écran, même quand l’accueil a le sien.

David l’a demandé le 27 novembre au soir :
- « améliore moi cette page d'accueil » ;
- « faudrait donner le choix d'afficher ou non la barre dock , si pas affichée ça permet de simpleifier interface et d'avoir en full screen le reste, de bien l'etirer, pas laisser du vide. ça rendrait l'interface plus simple. faut donner le choix d'afficher ou non la barre dans les options » ;
- « descend un peu la barre que les eventails n'entrent pas en collision avec les titres » ;
- « finalement fais qu'une barre sur ecran accueil comme l'autre, extensible en bas , mais garde cette taille pour la page accueil, et plus haut au meme niveau qu'actuel tu affiche les titres, ça fera de la place » ;
- « au survol, sur ecran accueil , pour film serie etc, on affiche l'ecran de fond » ;
- « pourquoi l'apercu disparait si on va dans la zone », avec deux photos de la 0.9.7 sur l’Apple TV du séjour.

Pour le reste, les validations de la 0.9.7 ([VALIDATION-0.9.7.md](VALIDATION-0.9.7.md)) et des versions précédentes valent toujours, avec leurs limites.

Les vérifications ont été faites le 27 novembre 2026 :
- sur un Mac Apple Silicon, macOS 27.2.1, Xcode 27.2 ;
- sur l’état final des sources.

## Les changements

### L’accueil sur une seule barre, en bas

- En 0.9.7, la barre de l’accueil se tenait au milieu de l’écran. En se remplissant, elle prenait une deuxième rangée, puis une troisième : les destinations au-dessus de ce que l’on garde, puis ce qui est en cours et les dossiers.
- Elle se tient désormais au pied de l’écran, sur une seule rangée, comme le dock sous les autres écrans, à 10 points de la marge que tvOS garde au bord du téléviseur. Elle garde la taille des icônes de l’accueil : sur un téléviseur 1080p, onze icônes y tiennent aux neuf dixièmes de cette taille (124 × 135 points au lieu de 138 × 150 sur le banc), dans la largeur que tvOS laisse à l’écran.
- Au-delà, les raccourcis en trop vont dans le dossier « Autres », comme sous les écrans. Si la place manque encore, les titres récents quittent la barre, les plus anciens d’abord. Les destinations, ce qui est en cours et les dossiers restent toujours.
- Le nom de la destination sélectionnée et sa ligne restent où ils se tenaient en 0.9.7 avec une rangée, au-dessus de l’icône que la loupe agrandit. Dans une fenêtre basse du Mac, ils descendent juste au-dessus de la barre.

### Les dossiers de l’accueil sous le haut de l’écran

- En 0.9.7, le nombre de titres d’un dossier ouvert sur l’accueil se comptait comme sous les écrans, où les titres sont plus petits. L’accueil les dessine à sa propre taille : un long dossier pouvait monter jusqu’au nom de l’application et à l’heure.
- Il se compte désormais à la taille de l’accueil, de la barre jusque sous le nom de l’application et l’heure. Moins la barre porte d’icônes, plus elles sont grandes, et moins un dossier montre de titres à la fois. Le reste passe par la dernière ligne, comme avant.
- Le grand nom s’efface toujours pendant qu’un dossier est ouvert.

### Le dock masquable

- Réglages › Dock › Emplacement : « Afficher le dock sur les écrans », oui par défaut. « Dock par défaut » le remontre.
- Masqué, le dock quitte le bas des écrans : les colonnes, la grille et les listes descendent jusqu’au bord, avec la même marge qu’en haut. Le plan de l’écran disparaît avec lui.
- Retour et Accueil passent en haut de la colonne de navigation, comme avec le dock sous la colonne. Depuis le contenu, Retour (Menu, ou Échap sur le Mac) confie d’abord la sélection à ce Retour ; une seconde fois, il revient à l’écran précédent.
- Lecture/Pause, ou Tab sur le Mac, fait le tour de ce qui reste : la colonne, la recherche, le contenu, et les boutons d’une chaîne.
- Sur le Mac, les touches d’un écran qui s’ouvre partent de Retour au lieu de l’icône du dock, et les Réglages prennent le clavier sur leur page.
- Une section vide confie la télécommande à Retour, et non plus à son icône du dock.
- L’accueil garde sa barre : c’est d’elle que l’on va partout.

### Le fond de l’écran survolé

- La 0.9.7 a donné à l’accueil, sur une nouvelle installation, le fond choisi sur l’Apple TV du séjour, comme celle-ci le faisait déjà. Un accueil qui a son propre fond ne suivait plus l’icône sélectionnée : seul le réglage Automatique le faisait.
- Désormais, une destination sélectionnée sur l’accueil (TV, Films, Séries, Recherche, Favoris, Réglages) montre le fond de son écran, même quand l’accueil a le sien. Favoris, comme en Automatique, garde celui de la dernière catégorie sélectionnée : TV, Films ou Séries.
- Le fond de l’accueil reste derrière ce que l’on garde dans la barre : raccourcis, titres en cours ou récents, dossiers et « Autres ».
- Le studio d’apparence le dit sous le choix propre de l’accueil.

### L’aperçu d’une chaîne gardé dans sa zone

- En 0.9.7, sur Apple TV, l’aperçu ne jouait que tant que la télécommande restait sur la ligne de la chaîne. Une flèche vers Regarder, Favoris ou le son, à côté de l’image, l’arrêtait : le cadre affichait « Aperçu après 1 seconde ». Le bouton du son, qui n’existe que pendant que l’aperçu joue, disparaissait avec lui : la télécommande ne pouvait pas l’atteindre.
- Désormais, l’aperçu continue sur ces trois boutons, et le son se coupe ou se rétablit à la télécommande. Il s’arrête toujours dans la colonne, dans la recherche et dans le dock.
- Rien ne change sur le Mac, où l’aperçu ne dépendait pas de la sélection.

## Exécuté

| Vérification | Résultat |
|---|---|
| Vérification de types : Mac et banc du Mac, tvOS, tvOS du banc, parcours de la télécommande, variante App Store pour tvOS, et iPhone et iPad (simulateur) | Aucune erreur. |
| Tests du cœur (`swift test`) | 204 tests, aucun échec. |
| Banc Apple TV (`scripts/test-tvos-catalog-ui.sh`), simulateur Apple TV 1080p sous tvOS 27.2 | 33 écrans capturés et validés ; 29 parcours de la télécommande sur 29, en 19 min 13 (23 min 54 en tout). Un premier passage, avant la correction de l’aperçu et la nouvelle grille des Réglages, en avait réussi 28 : celui de l’accueil se trompait de mesure (voir plus bas). |
| Banc Mac avec la galerie (`FLUX_CATALOG_UI_BACKGROUND=1 FLUX_CATALOG_UI_GALLERY=1 scripts/test-catalog-ui.sh`) | 95 captures, dont 6 nouvelles, et 29 scénarios de touches, en 6 min 49. Les deux essais précédents s’étaient arrêtés sur le scénario des thèmes (voir plus bas). |
| Apple TV 4K (1re génération), tvOS 26.6.1, téléviseur en 1080p | Compilée en Release depuis les sources finales de l’application et installée le 27 novembre à 22 h 26, après une première installation à 22 h, avant la correction de la grille des Réglages ; l’appareil la donne en 0.9.8 (49). Flux n’y tournait pas : rien n’a été interrompu, et l’app n’a pas été lancée. Aucun parcours n’y a été rejoué. |

## Ce que la vérification a trouvé

- La première vérification de types du Mac a échoué : la taille de l’accueil, qui compte les titres d’un dossier, n’était déclarée que pour l’Apple TV. Elle l’est désormais pour les deux. Aucun banc n’avait encore tourné.
- **La 0.9.7 ne compile pas pour iPhone et iPad.** La CI de `03bd013` l’a montré, et une vérification de types pour le simulateur iPhone l’a reproduit : l’écran d’une section vide renvoyait à une ligne de la colonne de la recherche, qui n’existe que sur Mac et Apple TV. La 0.9.8 réserve ce renvoi à ces deux plateformes. Rien ne change sur Mac ni sur Apple TV. Les vérifications de types de cette session ne couvraient pas iPhone et iPad ; elles les couvrent désormais.
- **Le parcours de l’accueil se trompait de mesure.** Il comparait le milieu de l’icône sélectionnée à celui d’une icône au repos. Or la loupe agrandit la première depuis le bas, et XCTest lit son cadre agrandi : 193 × 210 points au lieu de 124 × 135, d’où 38 points d’écart entre les deux milieux. La barre tenait bien sur une rangée, comme la capture de l’accueil le montre. Le parcours compare désormais le pied des icônes, et lit la taille sur une icône éloignée de la loupe.
- **Sur la page Dock, Bas sautait les thèmes.** Le scénario de touches du Mac qui choisit un thème a échoué deux fois. D’abord, il ignorait l’interrupteur « Afficher le dock sur les écrans », qui prend désormais la première flèche : il passe maintenant par lui (Droite, Bas, Droite, Bas, puis OK sur un thème). Ensuite, Bas, depuis les emplacements, menait droit à « Un thème par écran », sous les thèmes. L’interrupteur avait poussé leurs vignettes sous le bord de la page, et elles n’étaient construites qu’une fois à l’écran : le clavier ne les voyait pas. Les thèmes du dock, les couleurs des écrans et les icônes d’un dossier se construisent désormais d’un coup, dans une grille de même allure (`DeskGrid`), sur Mac comme sur Apple TV.

## Ce que les bancs vérifient de nouveau

- **L’accueil sur une barre**, à la télécommande. Les films, la liste gardée et « Autres » se tiennent sur la même rangée, au pied de l’écran, à la taille de l’accueil. « Autres » sélectionné ne porte pas de bulle ; son éventail s’ouvre sous le nom de l’application et l’heure, et Menu le referme sur son icône.
- **L’aperçu gardé dans sa zone**, à la télécommande. Depuis la quatrième chaîne, Droite mène à Regarder, puis à Favoris : un moment après chaque appui, l’aperçu appartient toujours à cette chaîne, alors qu’un aperçu arrêté, comme en 0.9.7, n’appartient à aucune. Le banc coupe l’aperçu automatique et ses chaînes n’ont pas de flux : il lit à quelle chaîne l’aperçu appartient, pas l’image.
- **Le fond de l’écran survolé** : Films sélectionné, le fond montré est celui des films, alors que l’accueil a le sien ; « Autres » sélectionné, c’est celui de l’accueil. Le banc lit quel écran fournit le fond, pas l’image elle-même.
- **Le dock masqué**, à la télécommande. Les films prennent l’écran, sans dock ni plan ; Lecture/Pause mène à la colonne, à la recherche et revient au film ; Menu confie la télécommande à Retour, en haut de la colonne, puis ramène à l’accueil, sur Films. Sur le Mac, Échap mène à Retour en haut de la colonne, et une seconde fois à l’accueil.
- **Des captures du Mac** : `home-fan.png` (une liste gardée ouverte sur l’accueil), `home-more.png` (« Autres » ouvert), `dock-hidden.png` (les films sans dock) et `dock-hidden-live.png` (la télévision sans dock).

## Non vérifié

- **Un accueil bien rempli chez soi** : la barre n’a été vue qu’avec les titres du banc.
- **Le dock masqué avec un autre emplacement** (en haut, à gauche, à droite, sous la colonne) : l’option le masque partout, mais seul l’emplacement par défaut a été capturé et parcouru.
- **iPhone et iPad** : rien n’y change, hormis la compilation rétablie ; la vérification de types passe, seule la CI les compile entièrement.
- **Un aperçu qui joue vraiment pendant que la sélection est sur Regarder, Favoris ou le son** : le banc n’a pas de flux, et la 0.9.8 n’a pas été essayée sur l’Apple TV du séjour, où elle est installée. Le bouton du son n’a donc été atteint par aucun parcours.
- **Les trois grilles des Réglages à l’écran** (thèmes du dock, couleurs des écrans, icônes d’un dossier) : aucune capture des bancs ne les montre, sur Mac comme sur Apple TV ; elles se tiennent sous le bord de la page ou sur une page que les bancs ne capturent pas. Leur allure n’a été comparée à celle de l’ancienne grille que dans un rendu à part, avec des vignettes d’essai, sur le Mac.
- **La page des Réglages qui défile jusqu’au thème choisi au clavier du Mac** : le banc capture ses fenêtres hors de l’écran, où la page reste en haut. La vignette choisie y est sélectionnée sous le bord de la page, en 0.9.8 comme en 0.9.7, où elle dépassait à peine.
- **La CI de GitHub** (tvOS 26.5, Mac hébergé, iPhone et iPad) : elle part avec l’envoi de la 0.9.8 ; son résultat n’est pas dans cette page.

## Limites connues

- Avec la télécommande, l’accueil s’ouvre sur une destination : son propre fond n’apparaît que lorsque l’on sélectionne ce que l’on garde dans la barre.
- Dock masqué, sur Apple TV, les bandes invisibles des bords ne sont pas posées : elles mènent toutes au dock. Une flèche vers un bord où rien ne se tient ne fait rien. Retour se rejoint par Haut, en haut de la colonne, ou par Menu depuis le contenu.
- Les titres récents qui quittent une barre trop pleine ne vont pas dans « Autres ».
