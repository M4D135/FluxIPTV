# Validation de FLUX IPTV 0.9.12 — build 53

La 0.9.12 range les chaînes de la télévision en tableau et replie les panneaux du bureau. Sur le Mac et sur l’Apple TV, les chaînes se rangent par deux à côté de l’aperçu sur l’écran d’une Apple TV, par trois quand l’aperçu est replié, par quatre quand la colonne l’est aussi. L’aperçu se replie par la touche au bout de ses boutons, la colonne de navigation par celle de son en-tête, à la télévision, dans les films et dans les séries. Sous la dernière rangée d’une page, Page précédente et Page suivante se tiennent à portée.

David l’a demandé le 28 novembre 2026 : « le mode tv quand arrive en bas de liste on doit tout remonter jusqu'au debut pour pouvoirnatteindre les boutons de changement de page, ce menu tv ça ne me va pas, la colonne c long a parcourir, faut un tableau et pour l'aperçu faut pouvoir le replier du coup, pareil pour liste de gauche, et aussi pour film serie, pouvoir replier les panels ».

Pour le reste, les validations de la 0.9.11 ([VALIDATION-0.9.11.md](VALIDATION-0.9.11.md)) et des versions précédentes valent toujours, avec leurs limites.

Les vérifications ont été faites le 28 novembre 2026 :
- sur un Mac Apple Silicon, macOS 27.2.1, Xcode 27.2 ;
- au simulateur Apple TV 4K (4e génération), en 1080p, sous tvOS 27.2 ;
- sur l’état final des sources.

## Ce qui change pour la vérification

- **Le tableau des chaînes.** Une chaîne est une case de 300 points de large au moins, et une rangée en tient autant que la largeur laissée par la colonne et l’aperçu, six au plus : deux sur l’écran d’une Apple TV, l’aperçu ouvert ; trois, l’aperçu replié ; quatre, la colonne aussi. Une page tient une quarantaine de chaînes en rangées entières : 40 par deux ou par quatre, 42 par trois. Dans une case, le nom d’une chaîne tient sur deux lignes. L’aperçu prend la largeur que laissent deux cases, et garde sous l’image la hauteur de ce qui y est écrit.
- **Replier.** La touche qui replie l’aperçu se tient au bout de la rangée de ses boutons (Regarder, Favoris, le son) ; celle de la colonne au bout de son en-tête. Un panneau replié laisse le long de son bord une bande de 56 points, qui porte la touche qui le rouvre et, écrit sur sa hauteur, le nom de l’écran ou « APERÇU ». Sur le Mac, un clic n’importe où sur la bande le rouvre aussi. Quand la barre ne porte pas Retour et Accueil, la bande de la colonne les garde au-dessus de sa touche. Replié, l’aperçu ne démarre plus. Ce qui est replié est enregistré sous `fluxiptv.desk.folds.v1` : la colonne de la télévision, des films et des séries chacune à part, et l’aperçu. L’écran de la recherche et celui des favoris gardent leur colonne : c’est ce qu’ils montrent.
- **La télécommande et le clavier.** Un panneau qui se replie laisse la sélection sur la chaîne ou le titre qu’elle tenait, à sa place dans le nouveau tableau ; un panneau qui se rouvre la reçoit : la colonne sur la ligne de ce qui est affiché, l’aperçu sur Regarder. Les flèches vont aux bandes comme aux panneaux. Au clavier du Mac, Haut depuis la première rangée mène aux touches qui la surplombent — la recherche, les pages, Actualiser — et non plus à celles de l’en-tête de la colonne, que l’on atteint depuis la colonne ou depuis la recherche. Sur l’Apple TV, l’application confie la télécommande à une touche qui vient d’apparaître en la lui redemandant jusqu’à ce que la touche dise l’avoir : les touches rondes de l’en-tête de la colonne et des bandes le disent désormais, comme les autres.
- **Le pied de page.** Sous la dernière rangée d’une page des chaînes, des films ou des séries : Page précédente, le numéro de la page et Page suivante. Sur l’Apple TV, Bas depuis la dernière rangée mène à Page suivante, d’où que l’on parte de la rangée, et la page suivante s’ouvre sur son premier titre. Au clavier du Mac, Bas passe d’une page à l’autre sans s’arrêter, comme avant ; le pied sert au pointeur. Les touches du haut de l’écran restent.
- **Le dock dans le coin.** Quand le dock se tient dans le coin, sous la colonne, une colonne repliée le laisse sous le tableau, qui s’arrête au-dessus de lui.

## Exécuté

| Vérification | Résultat |
|---|---|
| Vérification de types : Mac (production, et avec le banc du Mac), tvOS, tvOS du banc, parcours de la télécommande, variante App Store pour tvOS, et iPhone et iPad (simulateur) | Aucune erreur. |
| Tests du cœur (`swift test`) | 230 tests, aucun échec. |
| Banc Mac avec la galerie (`FLUX_CATALOG_UI_BACKGROUND=1 FLUX_CATALOG_UI_GALLERY=1 scripts/test-catalog-ui.sh`) | 101 captures et 32 scénarios de touches, aucun échec ; 5 min 44 de la première capture à la dernière. Comme en 0.9.11, ce mode laisse de côté les scénarios de la recherche qui demandent la fenêtre active. |
| Les captures de la télévision et des films, ouvertes et repliées, regardées en planche | Deux chaînes par rangée à côté de l’aperçu, trois l’aperçu replié, quatre la colonne aussi ; six jaquettes par rangée dans les films sans leur colonne. Chaque bande porte sa touche et son nom, « APERÇU », « TÉLÉVISION » ou « FILMS », écrit sur sa hauteur. |
| Banc Apple TV complet (`scripts/test-tvos-catalog-ui.sh`), Apple TV 4K (4e génération) en 1080p sous tvOS 27.2 | Les 39 écrans, tous valides, dont les trois aux panneaux repliés ; 29 parcours sur 33 en 21 min 21, 26 min 46 en tout. Trois des quatre autres supposaient une colonne de chaînes ; le quatrième a attendu neuf secondes une réponse de l’application, qui n’est pas venue (voir plus bas). |
| Les quatre parcours, repassés seuls (`FLUX_TVOS_FLOWS`) après la correction des trois | Aucun échec : 61,7 s, 48,4 s, 31,6 s et 14,2 s. |

## Ce que la vérification a trouvé

- **Les projets Xcode générés ne connaissaient pas le nouveau fichier du cœur.** La première compilation du banc Apple TV a échoué sur `DeskFolds`, `DeskPanel` et `DeskChannelGrid` : le cœur est compilé dans les applications, et chaque nouveau fichier doit figurer dans les deux projets. Ils sont régénérés, et la CI vérifie qu’ils le sont.
- **Haut depuis la première chaîne menait à la touche de la colonne.** Au clavier du Mac, la ligne du haut associe une colonne de la grille à la touche de même rang ; la touche qui replie la colonne, en tête de cette ligne, prenait la place de la recherche au-dessus de la première chaîne. La grille monte désormais aux seules touches qui la surplombent. Avec le dock masqué, Haut depuis le premier film ou la première série d’une page menait de même à Retour, en haut de la colonne ; il mène désormais à la recherche.
- **Trois parcours de l’Apple TV supposaient une colonne de chaînes.** Bas depuis la recherche se pose sur la case que le système trouve sous le champ, la deuxième de la première rangée, comme dans la grille des films ; le parcours qui visite toutes les zones revient de là à la première chaîne par Gauche. Droite, le long de la première rangée, passe par la deuxième chaîne avant les actions de l’aperçu : la télévision la garde comme le titre quitté et se rouvre sur elle, depuis le dock comme par Menu. Le pointeur qui longe la liste partait de dix-huit chaînes, neuf rangées du tableau : la liste cessait de défiler sous le pouce avant que l’on voie le pointeur garder sa hauteur ; il part désormais d’une page entière, 110 chaînes.
- **Une question du banc restée sans réponse.** Au banc complet, le parcours où aucun appui ne mène nulle part a attendu neuf secondes que l’icône de la télévision perde la télécommande, après Haut depuis la barre. La vidéo du parcours montre la sélection sur la treizième chaîne moins d’une seconde après l’appui, et l’arbre relevé à l’échec la montre au même endroit : c’est la question du banc qui est restée sans réponse, comme celle de sept secondes notée en 0.9.0 sur une machine hébergée. Repassé seul, le parcours a eu sa réponse aussitôt. La cause n’est toujours pas connue.
- **Le départ du banc Mac.** Jusqu’à la 0.9.11, le premier focus de la fenêtre posait la sélection sur la première ligne de la colonne de la télévision, à la place de la chaîne que l’écran demandait ; les scénarios du bord de l’écran partaient de là. Le premier focus se pose désormais un instant sur la touche de la colonne, en tête de la fenêtre, puis la demande de l’écran aboutit : la télévision s’ouvre sur sa première chaîne, comme le dit le README (« une destination s’ouvre avec la sélection dans son contenu »). Les scénarios partent de cette chaîne.

## Ce que les bancs vérifient de nouveau

- **Les panneaux repliés sur l’Apple TV.** Trois captures : la télévision l’aperçu replié, puis la colonne aussi, et les films la colonne repliée, avec le focus natif sur le contrôle attendu (`FLUX_UI_FOLDS`).
- **Replier et rouvrir à la télécommande.** Un nouveau parcours replie l’aperçu puis le rouvre, replie la colonne puis la rouvre, la télécommande chaque fois sur le contrôle attendu, et tourne la page par son pied. Les parcours qui longent une rangée de chaînes comptent les deux cases du tableau et la touche qui replie l’aperçu.
- **Replier au clavier du Mac.** Deux scénarios replient l’aperçu et la colonne et lisent ce que l’application a enregistré ; un troisième vérifie que Haut depuis la première chaîne mène à la recherche. Trois captures montrent les mêmes panneaux repliés.
- **Les tests du cœur :** ce qui est replié, écran par écran, et ce qui s’enregistre ; le nombre de cases d’une rangée et d’une page ; la grille qui monte aux touches qui la surplombent.

## Non vérifié

- **Sur une Apple TV.** Rien n’a été installé sur une Apple TV : le tableau, les panneaux repliés et le pied de page n’y ont pas été vus.
- **Le banc Apple TV entier après la correction des trois parcours.** Seuls les quatre parcours ont été repassés ; l’application n’a pas changé entre les deux passages. La CI rejoue le banc entier sous tvOS 26.5.
- **Le clic sur une bande, sur le Mac.** Le banc du Mac joue le clavier ; le clic n’importe où sur une bande pour rouvrir son panneau n’y est pas joué.
- **Ce que coûte le tableau.** Le parcours qui compte ce qu’un appui reconstruit passe dans le tableau d’un catalogue de 24 665 chaînes ; le temps de calcul de la descente d’une longue liste n’a pas été mesuré de nouveau.
- **iPhone et iPad** : la liste des chaînes y reste une liste, sans panneau à replier. La vérification de types passe ; seule la CI les compile entièrement.
- **La CI de GitHub** : celle de la 0.9.12 part avec son envoi, et son résultat n’est pas dans cette page. Celle de la 0.9.11 (`dd5b2d7`) est passée entièrement, sur la branche et sur main.

## Limites connues

- **Les couleurs des écrans** (Réglages › Interface) donnent toujours aux thèmes leurs deux couleurs, et le fond uni quand un écran n’a pas d’image ; les ranger dans le thème reste pour une prochaine version.
- **Le pied de page au clavier du Mac.** Bas y passe d’une page à l’autre sans s’arrêter au pied, qui sert au pointeur.
