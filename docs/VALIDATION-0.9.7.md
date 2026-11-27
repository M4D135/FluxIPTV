# Validation de FLUX IPTV 0.9.7 — build 48

La 0.9.7 retire l’heure de la barre du bas : le plan de l’écran, plus grand, prend sa place dans le coin bas droite. Sur l’accueil, le nom de la destination sélectionnée et sa ligne se tiennent au-dessus de l’icône que la loupe agrandit, et un titre gardé dans la barre n’y porte plus de bulle. La recherche devient un écran à part, avec sa colonne et son fond, et une section ne garde plus de recherche. Une nouvelle installation prend les fonds choisis sur l’Apple TV du séjour.

David l’a demandé le 27 novembre au soir, devant son Apple TV :
- « vire l’heure on s’en fout ou met la tout en haut au milieu » ;
- « l’indicateur de zone fais le plus gros et bien dans le coin bas droite du coup qui remplacera l’heure » ;
- avec une photo de l’accueil, « labels plus haut (favoris...) sur ecran accueil, sinon collision avec icone » ;
- « garde mes preset d'imagesnde fond pour le par defaut », puis « prend les fond que j'ai config pour les reglages par defaut stp » ;
- « pour serie y'a un souci, j'ai le fond de recherche et recherche n'a pas son menu dedié, pas bon , regarde bien sur l'appletv » ;
- avec une photo de l’accueil, un film gardé dans la barre sélectionné, « collision les titres trop bas ».

Pour le reste, les validations de la 0.9.6 ([VALIDATION-0.9.6.md](VALIDATION-0.9.6.md)) et des versions précédentes valent toujours, avec leurs limites.

Les vérifications ont été faites le 27 novembre 2026 :
- sur un Mac Apple Silicon, macOS 27.2.1, Xcode 27.2 ;
- sur l’état final des sources.

## Les changements

### L’heure quitte la barre du bas

- La barre du bas n’affiche plus ni l’heure ni la date. L’heure n’est pas montée en haut au milieu : sur les écrans du catalogue, la ligne du titre et de la recherche s’y tient déjà.
- Le plan de l’écran prend sa place dans le coin bas droite. Il passe de 30 × 17 à 54 × 30 points, et la touche qui mène à la partie suivante de 10 à 17 points, dans une pastille de verre haute de 44 points. Il allume toujours la partie qui a la sélection.
- Quand le dock est plein, la barre ne cède plus que le nom de l’écran précédent : Retour et Accueil restent à gauche.
- L’heure reste sur l’accueil, en haut à droite, et pendant la lecture.
- Avec le dock ailleurs qu’en bas (sous la colonne, en haut, à gauche ou à droite), le plan reste au pied de l’écran, au milieu, plus grand lui aussi.

### Le nom de l’accueil au-dessus de la loupe

- La loupe agrandit toute la case de l’icône sélectionnée depuis son bord bas. Avec la loupe Normale, celle par défaut, l’icône montait d’environ 32 points sur le nom et la ligne de la destination, sur un téléviseur 1080p : c’est ce que montrait la photo.
- Le nom finit désormais au-dessus de l’icône la plus agrandie, quelle que soit la loupe, avec une marge pour l’inclinaison sous le pouce. Sur un téléviseur 1080p, il monte de 16 points en loupe Légère, 49 en Normale, 82 en Forte et 117 en Maximale. En loupe Aucune, il garde sa place de la 0.9.6.
- La barre descend de la moitié de cette montée : l’ensemble reste au milieu de l’écran. La taille des icônes de l’accueil compte cette montée. Avec une rangée, elle ne change pas sur un téléviseur 1080p ; avec deux ou trois rangées, elle perd au plus 6 %, en loupe Maximale.
- Le Mac montre le même accueil à la taille de sa fenêtre et suit les mêmes règles.

### Plus de bulle sur l’accueil

- Un titre gardé dans la barre (chaîne, film, série, dossier, liste) porte, une fois sélectionné, une bulle à son nom complet au-dessus de son icône, comme le Dock d’un Mac. Sur l’accueil, cette bulle montait jusqu’au grand nom, qui dit la même chose : c’est la collision de la photo. Avec deux rangées, elle se posait sur la rangée du dessus.
- L’accueil ne montre plus de bulle : son grand nom suffit. Rien ne se tient plus entre ce nom et l’icône agrandie.
- Sous un écran (TV, Films, Séries…), la barre garde la bulle : rien d’autre n’y nomme le titre.

### La recherche, un écran à part (Mac et Apple TV)

- La touche Recherche du dock ouvre un écran à part. Il s’intitule « Recherche » et porte le fond de la Recherche. Le dock y montre Recherche comme l’écran en cours. Le champ prend la télécommande, ou le clavier sur le Mac.
- Sa colonne s’intitule « RECHERCHE » et réunit trois choses :
  - « CHERCHER DANS » : Chaînes, Films et Séries, chacun avec le nombre de titres que la recherche y trouve. Ce nombre se calcule en arrière-plan, 300 ms après la dernière touche.
  - « RECHERCHES RÉCENTES » : les six dernières recherches, de la plus récente à la plus ancienne, sans doublon (majuscules et accents ignorés). Une recherche y entre quand elle est envoyée, ou quand un titre trouvé est ouvert. Ces recherches restent sur l’appareil.
  - « Effacer la recherche », tant qu’une recherche est saisie.
- Une ligne de « CHERCHER DANS » relance la même recherche dans une autre catégorie : la recherche ne change pas.
- La recherche porte sur tout le catalogue de la catégorie. Un groupe, une liste de favoris, un dossier du dock ou un pays choisis dans la section ne la restreignent pas ; la section les retrouve en sortant de la recherche.
- Avant la première touche, l’écran affiche « Que cherchez-vous ? ».
- Quand une recherche envoyée ne trouve rien, l’écran affiche « Rien pour « … » dans les films » (ou les chaînes, ou les séries). La télécommande reste alors dans la colonne, sur la catégorie où la recherche a eu lieu. En 0.9.6, elle allait sur l’icône de la section dans le dock, où OK aurait quitté la recherche.
- Retour (Menu, ou Échap sur le Mac) ramène à l’écran d’où la recherche a été ouverte, tel qu’il était : même page, même titre sélectionné, mêmes filtres. Ouverte depuis l’accueil, elle y ramène.
- Une section du dock, les favoris, les réglages ou l’accueil quittent aussi la recherche.
- Sur iPhone et iPad, rien ne change : la recherche reste un champ du catalogue.

### Une section ne garde plus de recherche

- La cause du problème des Séries :
  - en 0.9.6, chaque section gardait sa recherche avec le reste de sa navigation (page, groupe, pays, titre sélectionné), par source et par catégorie, et la remettait à chaque visite ;
  - le fond suivait la recherche dès qu’elle n’était pas vide.
- Une recherche saisie un jour dans les Séries y revenait donc à chaque visite, avec le fond de la Recherche et une liste filtrée.
- Désormais, une section garde sa navigation, jamais de recherche. Une recherche enregistrée par une version précédente est ignorée dès la première visite ; le titre que la section retient est jugé sur ce qu’elle montrera, sans cette recherche. Le fond suit l’écran de la recherche, et non plus le texte saisi.
- Cela vaut pour le Mac et l’Apple TV. Sur iPhone et iPad, où le champ de recherche fait partie de la section, la section garde sa recherche comme avant.

### Les fonds du séjour par défaut

- Les choix de fonds de l’Apple TV du séjour ont été lus dans les préférences de l’application, sur l’appareil. Seules les clés de l’apparence ont été gardées : la copie des préférences a été effacée aussitôt, et rien d’autre n’a été lu.
- Chaque écran a son propre fond, une image fixe :

  | Écran | Fond |
  |---|---|
  | Accueil | Archives infinies |
  | TV | Salon néon 90 |
  | Films | Grande salle |
  | Séries | Coin binge-watching |
  | Recherche | Observatoire |
  | Réglages | Studio aux boutons |

- Ces choix servent quand aucun choix n’est enregistré : nouvelle installation, ou choix illisible. Un choix déjà enregistré ne change pas ; l’Apple TV du séjour garde exactement les siens.
- Les thèmes du dock ne changent pas.

## Exécuté

| Vérification | Résultat |
|---|---|
| Vérification de types : Mac et banc du Mac, tvOS, tvOS du banc, parcours de la télécommande et variante App Store pour tvOS | Aucune erreur. |
| Tests du cœur (`swift test`) | 204 tests, aucun échec. Les fonds par défaut sont identiques à ceux enregistrés sur l’Apple TV du séjour, réglage par réglage. |
| Banc Apple TV (`scripts/test-tvos-catalog-ui.sh`), simulateur Apple TV 1080p sous tvOS 27.2 | 33 écrans, dont la chaîne restaurée trois fois : focus natif sur le contrôle attendu, captures non vides. Au passage complet, 27 parcours XCUIRemote sur 28, en 18 minutes : le 28e, Retour depuis la recherche, échouait (voir plus bas). Après son correctif, il passe ; il a été rejoué sur l’état final avec les parcours de l’accueil et des raccourcis du dock. |
| Banc Mac avec la galerie (`FLUX_CATALOG_UI_BACKGROUND=1 FLUX_CATALOG_UI_GALLERY=1 scripts/test-catalog-ui.sh`) | 89 captures hors écran, galerie comprise, et 27 parcours de touches sur 27, en cinq minutes et demie, sur le commit de la build 48. La fin « PARTIAL » est attendue en local : les scénarios du champ de recherche demandent la fenêtre au premier plan et restent à la CI. |
| Apple TV 4K (1re génération), tvOS 26.6.1, téléviseur en 1080p | L’application en Release est installée ; l’appareil la donne en 0.9.7 (48). Elle n’a pas été lancée : l’Apple TV était en veille, et la réveiller aurait allumé le téléviseur. Les parcours de la télécommande n’y ont pas été rejoués ; la 0.9.6 y passait ses 27. |

## Ce que le banc a trouvé

Au premier passage du banc Apple TV, trois écrans échouaient.

- **Une recherche qui ne trouve rien.** La télécommande devait rester dans la colonne, sur Films. L’écran lui remettait bien la sélection, mais attendait que tvOS l’accuse sur l’icône de la section, dans la barre. L’accusé n’arrivait jamais : la remise restait en suspens, et la sélection ne suivait plus la télécommande. La remise et son accusé visent désormais la même ligne de la colonne. Sans le banc, ce défaut serait arrivé sur l’Apple TV.
- **La chaîne restaurée et les filtres gardés.** Ces deux écrans attendaient encore la recherche « Grand écran », gardée par la section comme en 0.9.6. Ils vérifient désormais le contraire (voir plus bas).

Au passage complet suivant, un parcours sur 28 échouait : **Retour depuis la recherche**.
- Ce qui se passait : les films revenaient sur leur premier titre, et non sur le deuxième, celui qui était sélectionné.
- Ce que la trace a montré : une trace temporaire, posée pour ce seul parcours puis retirée, a établi que la section n'avait retenu aucun titre. Le banc ouvre les films sur le deuxième titre, sans que la télécommande s'y déplace. Or la section n'enregistrait le titre sélectionné qu'au premier mouvement de la télécommande.
- Le correctif : en ouvrant la recherche, une section qui ne retient aucun titre retient celui qu'elle montre. Retour y ramène, quelle que soit la façon dont ce titre a été sélectionné.

## Ce que les bancs vérifient de nouveau

- **L’écran de la recherche**, à la télécommande. Depuis les films, Bas mène au dock, puis Recherche ouvre l’écran : le champ a la sélection, la colonne propose Chaînes, Films et Séries, l’écran affiche « Que cherchez-vous ? » et les films n’y sont plus. Menu ramène aux films, sur le titre laissé.
- **Une recherche qui trouve.** Le film trouvé a la sélection, et la colonne propose « Effacer la recherche ». Gauche entre dans la colonne, sur Films ; Droite revient au film. Les séries puis les films, ouverts depuis le dock, montrent tout ce qu’ils tiennent : ni la recherche, ni sa colonne.
- **Une recherche gardée par la 0.9.6.** Le banc l’enregistre, « Grand écran », avec le pays, le groupe, la recherche du groupe et la chaîne d’une section, comme le faisait la 0.9.6. La section revient sur tout cela, sauf sur la recherche ; le parcours de la chaîne restaurée le vérifie aussi à la télécommande.
- **La recherche hors des filtres de la section.** La section des chaînes montre la France ; une recherche « UK » trouve les deux chaînes britanniques, et la section retrouve la France en sortant de la recherche.
- **Rien de trouvé**, sur Mac comme sur Apple TV : la sélection reste dans la colonne, sur Films.
- **La bulle d’un titre gardé** : sous un écran, le parcours des raccourcis du dock vérifie qu’elle nomme le film sélectionné ; sur l’accueil, le parcours des deux rangées vérifie qu’un titre gardé, sélectionné, n’en a pas. Une capture du Mac montre l’accueil, le pointeur sur un film gardé (`home-dock-title.png`).

## Non vérifié

- **Une vraie saisie** : les parcours écrivent la recherche par le banc. Personne n’a encore tapé une recherche au clavier de tvOS, ni dicté, sur l’écran de la recherche.
- **Les recherches récentes** : enregistrées et affichées, mais aucun parcours n’en choisit une dans la colonne.
- **Un grand catalogue** : le délai des nombres de la colonne n’est mesuré ni avec des dizaines de milliers de titres, ni sur une Apple TV HD.
- **iPhone et iPad** : rien n’y change ; seule la CI les compile.
- **L’Apple TV du séjour** : la 0.9.7 y est installée, mais elle n’y a été ni lancée ni parcourue.

## Limites connues

- Sur Mac et Apple TV, une recherche que la 0.9.6 gardait avec une section est abandonnée ; elle n’entre pas dans les recherches récentes.
- La recherche porte sur toute une catégorie : elle ne se limite pas à un groupe, à un pays ou à une liste de favoris.
- Les nombres de la colonne arrivent un instant après les résultats : 300 ms après la dernière touche, puis le temps de compter.
